import Foundation

public actor PricingManager {
    public static let shared = PricingManager()

    private let liteLLMURL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    private let cacheValidDuration: TimeInterval = 86_400 * 7

    private let providerPrefixes = [
        "anthropic/",
        "openai/",
        "azure/",
        "openrouter/openai/",
        "openrouter/anthropic/",
        "openrouter/google/",
        "google/",
        "googleai/",
    ]

    private let familyPatterns: [String: [String]] = [
        "claude-opus-4-": ["claude-opus-4", "claude-opus-4-1"],
        "claude-sonnet-4-": ["claude-sonnet-4", "claude-sonnet-4-5"],
        "claude-haiku-": ["claude-haiku-3-5", "claude-haiku-4"],
        "gpt-5.": ["gpt-5", "gpt-5.1"],
        "gpt-4.": ["gpt-4.1", "gpt-4o"],
        "gemini-": ["gemini-2.5-pro", "gemini-2.0-flash"],
        "o1": ["o1", "o1-mini"],
        "o3": ["o3", "o3-mini"],
    ]

    private var cache: [String: LiteLLMModelPricing] = [:]
    private var metadata: PricingCacheMetadata?
    private var isInitialized = false

    private init() {}

    public func getPricing(for modelName: String) -> UsageModelPricing? {
        let normalized = normalizeModelName(modelName)

        if let pricing = matchExact(normalized) ?? matchWithPrefix(normalized) {
            let source: PricingSource = metadata?.source == "remote" ? .remote : (metadata?.source == "bundled" ? .bundled : .cached)
            return pricing.toUsageModelPricing(source: source)
        }

        if let pricing = matchFuzzy(normalized) {
            return pricing.toUsageModelPricing(source: .cached)
        }

        if let pricing = findSimilarModelPricing(for: normalized) {
            return pricing
        }

        return getHardcodedPricing(for: normalized)
    }

    public func initialize() async {
        guard !isInitialized else { return }
        isInitialized = true

        if let cached = loadLocalCache() {
            cache = cached.models
            metadata = cached.metadata
        }

        if cache.isEmpty, let bundled = loadBundledPricing() {
            cache = bundled
            metadata = PricingCacheMetadata(
                version: PricingCacheMetadata.currentVersion,
                lastUpdated: Date(),
                source: "bundled",
                modelCount: bundled.count
            )
        }

        Task.detached(priority: .background) {
            try? await Self.shared.refreshFromRemote()
        }
    }

    public func refreshFromRemote() async throws {
        if let last = metadata?.lastUpdated, Date().timeIntervalSince(last) < cacheValidDuration {
            return
        }

        guard let url = URL(string: liteLLMURL) else { return }

        let (data, _) = try await URLSession.shared.data(from: url)
        let parsed = try parseLiteLLMJSON(data)

        cache = parsed
        metadata = PricingCacheMetadata(
            version: PricingCacheMetadata.currentVersion,
            lastUpdated: Date(),
            source: "remote",
            modelCount: parsed.count
        )

        try saveLocalCache()
    }

    public func getCacheInfo() -> (count: Int, lastUpdated: Date?, source: String?) {
        (cache.count, metadata?.lastUpdated, metadata?.source)
    }

    private func matchExact(_ name: String) -> LiteLLMModelPricing? {
        cache[name]
    }

    private func matchWithPrefix(_ name: String) -> LiteLLMModelPricing? {
        for prefix in providerPrefixes {
            if let pricing = cache["\(prefix)\(name)"] {
                return pricing
            }
        }
        return nil
    }

    private func matchFuzzy(_ name: String) -> LiteLLMModelPricing? {
        let lower = name.lowercased()
        var bestMatch: (key: String, pricing: LiteLLMModelPricing, score: Int)?

        for (key, pricing) in cache {
            let keyLower = key.lowercased()
            var score = 0

            if keyLower == lower {
                return pricing
            }

            if keyLower.contains(lower) {
                score = lower.count
            } else if lower.contains(keyLower) {
                score = keyLower.count
            }

            if score > 0, bestMatch == nil || score > bestMatch!.score {
                bestMatch = (key, pricing, score)
            }
        }

        return bestMatch?.pricing
    }

    private func findSimilarModelPricing(for modelName: String) -> UsageModelPricing? {
        for (pattern, candidates) in familyPatterns {
            if modelName.contains(pattern) {
                for candidate in candidates {
                    let normalizedCandidate = normalizeModelName(candidate)
                    if let pricing = cache[normalizedCandidate] ?? matchWithPrefix(normalizedCandidate) {
                        return pricing.toUsageModelPricing(source: .cached)
                    }
                }
                if let hardcoded = getHardcodedPricing(for: candidates[0]) {
                    return hardcoded
                }
            }
        }
        return nil
    }

    private func getHardcodedPricing(for modelName: String) -> UsageModelPricing? {
        switch modelName {
        case "free":
            return UsageModelPricing(
                inputCostPerMillion: 0,
                cacheWriteCostPerMillion: 0,
                cacheReadCostPerMillion: 0,
                outputCostPerMillion: 0
            )
        case "gpt-5", "gpt-5-chat-latest", "gpt-5.1", "gpt-5.1-chat-latest", "gpt-5.4":
            return UsageModelPricing(
                inputCostPerMillion: 1.25,
                cacheWriteCostPerMillion: 1.25,
                cacheReadCostPerMillion: 0.125,
                outputCostPerMillion: 10
            )
        case "gpt-5.2-codex":
            return UsageModelPricing(
                inputCostPerMillion: 1.75,
                cacheWriteCostPerMillion: 1.75,
                cacheReadCostPerMillion: 0.175,
                outputCostPerMillion: 14
            )
        case "gpt-5-mini":
            return UsageModelPricing(
                inputCostPerMillion: 0.25,
                cacheWriteCostPerMillion: 0.25,
                cacheReadCostPerMillion: 0.025,
                outputCostPerMillion: 2
            )
        case "gpt-5-nano":
            return UsageModelPricing(
                inputCostPerMillion: 0.05,
                cacheWriteCostPerMillion: 0.05,
                cacheReadCostPerMillion: 0.005,
                outputCostPerMillion: 0.4
            )
        case "gpt-4.1":
            return UsageModelPricing(
                inputCostPerMillion: 2,
                cacheWriteCostPerMillion: 2,
                cacheReadCostPerMillion: 0.5,
                outputCostPerMillion: 8
            )
        case "gpt-4.1-mini":
            return UsageModelPricing(
                inputCostPerMillion: 0.4,
                cacheWriteCostPerMillion: 0.4,
                cacheReadCostPerMillion: 0.1,
                outputCostPerMillion: 1.6
            )
        case "gpt-4.1-nano":
            return UsageModelPricing(
                inputCostPerMillion: 0.1,
                cacheWriteCostPerMillion: 0.1,
                cacheReadCostPerMillion: 0.025,
                outputCostPerMillion: 0.4
            )
        case "gpt-4o":
            return UsageModelPricing(
                inputCostPerMillion: 2.5,
                cacheWriteCostPerMillion: 2.5,
                cacheReadCostPerMillion: 1.25,
                outputCostPerMillion: 10
            )
        case "gpt-4o-mini":
            return UsageModelPricing(
                inputCostPerMillion: 0.15,
                cacheWriteCostPerMillion: 0.15,
                cacheReadCostPerMillion: 0.075,
                outputCostPerMillion: 0.6
            )
        case "claude-sonnet-4", "claude-sonnet-4-5", "claude-sonnet-4-20250514", "claude-sonnet-3-5-sonnet-20241022", "claude-3-5-sonnet-20241022", "claude-sonnet-4-6", "claude-sonnet-4.6":
            return UsageModelPricing(
                inputCostPerMillion: 3,
                cacheWriteCostPerMillion: 3.75,
                cacheReadCostPerMillion: 0.30,
                outputCostPerMillion: 15,
                inputCostPerMillionAbove200k: 6,
                outputCostPerMillionAbove200k: 30
            )
        case "claude-opus-4", "claude-opus-4-1", "claude-opus-4-20250514", "claude-opus-4-5", "claude-opus-4.5", "claude-opus-4-6", "claude-opus-4.6":
            return UsageModelPricing(
                inputCostPerMillion: 15,
                cacheWriteCostPerMillion: 18.75,
                cacheReadCostPerMillion: 1.5,
                outputCostPerMillion: 75
            )
        case "claude-haiku-3-5", "claude-3-5-haiku-20241022":
            return UsageModelPricing(
                inputCostPerMillion: 0.8,
                cacheWriteCostPerMillion: 1.0,
                cacheReadCostPerMillion: 0.08,
                outputCostPerMillion: 4
            )
        case "claude-haiku-4", "claude-haiku-4-5", "claude-haiku-4.5":
            return UsageModelPricing(
                inputCostPerMillion: 1,
                cacheWriteCostPerMillion: 1.25,
                cacheReadCostPerMillion: 0.10,
                outputCostPerMillion: 5
            )
        case "gemini-2.5-pro":
            return UsageModelPricing(
                inputCostPerMillion: 1.25,
                cacheWriteCostPerMillion: 1.25,
                cacheReadCostPerMillion: 0.125,
                outputCostPerMillion: 10
            )
        case "gemini-2.5-flash":
            return UsageModelPricing(
                inputCostPerMillion: 0.30,
                cacheWriteCostPerMillion: 0.30,
                cacheReadCostPerMillion: 0.03,
                outputCostPerMillion: 2.5
            )
        case "gemini-2.5-flash-lite":
            return UsageModelPricing(
                inputCostPerMillion: 0.10,
                cacheWriteCostPerMillion: 0.10,
                cacheReadCostPerMillion: 0.01,
                outputCostPerMillion: 0.4
            )
        case "gemini-2.0-flash":
            return UsageModelPricing(
                inputCostPerMillion: 0.10,
                cacheWriteCostPerMillion: 0.10,
                cacheReadCostPerMillion: 0.025,
                outputCostPerMillion: 0.4
            )
        default:
            return nil
        }
    }

    private func normalizeModelName(_ raw: String) -> String {
        var value = raw.lowercased()

        if value.hasPrefix("[pi] ") {
            value.removeFirst(5)
        }

        for prefix in providerPrefixes where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }

        if value.hasSuffix(":free") || value == "openrouter/free" {
            return "free"
        }

        if value.hasPrefix("claude-"), value.count > 9 {
            let parts = value.split(separator: "-")
            if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
                value = parts.dropLast().joined(separator: "-")
            }
        }

        if value.hasSuffix("-latest") {
            value = String(value.dropLast(7))
        }

        switch value {
        case "gpt-5-codex", "gpt-5.1-codex":
            return "gpt-5"
        case "gpt-5.2-codex", "gpt-5.3-codex":
            return "gpt-5.2-codex"
        case "gpt-5.2":
            return "gpt-5.2-codex"
        case "claude-sonnet-4-20250514":
            return "claude-sonnet-4"
        case "claude-opus-4-20250514":
            return "claude-opus-4"
        case "claude-sonnet-4-5", "claude-sonnet-4.5", "claude-sonnet-4-5-latest":
            return "claude-sonnet-4-5"
        case "claude-opus-4-1", "claude-opus-4.1":
            return "claude-opus-4-1"
        default:
            return value
        }
    }

    private func loadLocalCache() -> (models: [String: LiteLLMModelPricing], metadata: PricingCacheMetadata)? {
        let cacheURL = VibeBarPaths.pricingCacheURL
        let metadataURL = VibeBarPaths.pricingMetadataURL

        guard FileManager.default.fileExists(atPath: cacheURL.path),
              let cacheData = try? Data(contentsOf: cacheURL),
              let metadataData = try? Data(contentsOf: metadataURL) else {
            return nil
        }

        guard let meta = try? JSONDecoder().decode(PricingCacheMetadata.self, from: metadataData),
              meta.version == PricingCacheMetadata.currentVersion else {
            return nil
        }

        let models: [String: LiteLLMModelPricing]
        do {
            models = try JSONDecoder().decode([String: LiteLLMModelPricing].self, from: cacheData)
        } catch {
            return nil
        }

        return (models, meta)
    }

    private func loadBundledPricing() -> [String: LiteLLMModelPricing]? {
        if let url = Bundle.main.url(forResource: "pricing", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let parsed = try? parseLiteLLMJSON(data) {
            return parsed
        }

        if VibeBarPaths.runMode == .source {
            if let repoRoot = VibeBarPaths.repoRoot {
                let sourceURL = repoRoot
                    .appendingPathComponent("Sources")
                    .appendingPathComponent("VibeBarApp")
                    .appendingPathComponent("Resources")
                    .appendingPathComponent("pricing.json")
                if FileManager.default.fileExists(atPath: sourceURL.path),
                   let data = try? Data(contentsOf: sourceURL),
                   let parsed = try? parseLiteLLMJSON(data) {
                    return parsed
                }
            }

            let exe = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
                .resolvingSymlinksInPath()
            let bundleURL = exe.deletingLastPathComponent()
                .appendingPathComponent("VibeBar_VibeBarApp.bundle")
            if FileManager.default.fileExists(atPath: bundleURL.path),
               let bundle = Bundle(url: bundleURL),
               let url = bundle.url(forResource: "pricing", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let parsed = try? parseLiteLLMJSON(data) {
                return parsed
            }
        }

        return nil
    }

    private func saveLocalCache() throws {
        let cacheURL = VibeBarPaths.pricingCacheURL
        let metadataURL = VibeBarPaths.pricingMetadataURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let cacheData = try encoder.encode(cache)
        let metadataData = try encoder.encode(metadata)

        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let tempCache = cacheURL.appendingPathExtension("tmp")
        let tempMetadata = metadataURL.appendingPathExtension("tmp")

        try cacheData.write(to: tempCache)
        try metadataData.write(to: tempMetadata)

        _ = try FileManager.default.replaceItemAt(cacheURL, withItemAt: tempCache)
        _ = try FileManager.default.replaceItemAt(metadataURL, withItemAt: tempMetadata)
    }

    private func parseLiteLLMJSON(_ data: Data) throws -> [String: LiteLLMModelPricing] {
        struct RawPricing: Codable {
            let input_cost_per_token: Double?
            let output_cost_per_token: Double?
            let cache_creation_input_token_cost: Double?
            let cache_read_input_token_cost: Double?
            let input_cost_per_token_above_200k_tokens: Double?
            let output_cost_per_token_above_200k_tokens: Double?
            let cache_creation_input_token_cost_above_200k_tokens: Double?
            let cache_read_input_token_cost_above_200k_tokens: Double?
            let max_input_tokens: Int?
            let max_output_tokens: Int?
            let litellm_provider: String?
        }

        let raw = try JSONDecoder().decode([String: RawPricing].self, from: data)

        var result: [String: LiteLLMModelPricing] = [:]
        for (key, value) in raw {
            guard value.input_cost_per_token != nil || value.output_cost_per_token != nil else {
                continue
            }

            let pricing = LiteLLMModelPricing(
                inputCostPerToken: value.input_cost_per_token,
                outputCostPerToken: value.output_cost_per_token,
                cacheCreationInputTokenCost: value.cache_creation_input_token_cost,
                cacheReadInputTokenCost: value.cache_read_input_token_cost,
                inputCostPerTokenAbove200k: value.input_cost_per_token_above_200k_tokens,
                outputCostPerTokenAbove200k: value.output_cost_per_token_above_200k_tokens,
                cacheCreationCostAbove200k: value.cache_creation_input_token_cost_above_200k_tokens,
                cacheReadCostAbove200k: value.cache_read_input_token_cost_above_200k_tokens,
                maxInputTokens: value.max_input_tokens,
                maxOutputTokens: value.max_output_tokens,
                litellmProvider: value.litellm_provider
            )
            result[key] = pricing
        }

        return result
    }
}
