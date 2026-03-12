import Foundation

public struct UsagePricingResolver: Sendable {
    public init() {}

    public func normalizedModelName(for rawValue: String) -> String {
        normalizeModelName(rawValue)
    }

    public func pricing(for modelName: String) -> UsageModelPricing? {
        Self.lookupPricing(for: normalizeModelName(modelName))
    }

    public func pricing(forNormalizedModelName normalizedModelName: String) -> UsageModelPricing? {
        Self.lookupPricing(for: normalizedModelName)
    }

    public func resolveCost(for event: UsageEvent) -> UsageEvent {
        resolveCost(
            for: event,
            normalizedModelName: normalizeModelName(event.modelName),
            pricing: pricing(for: event.modelName)
        )
    }

    public func resolveCost(
        for event: UsageEvent,
        normalizedModelName: String,
        pricing: UsageModelPricing?
    ) -> UsageEvent {
        if let costUSD = event.costUSD, costUSD > 0 {
            var resolved = event
            resolved.costIsEstimated = false
            resolved.costIsIncomplete = false
            return resolved
        }

        guard let pricing else {
            var unresolved = event
            unresolved.costUSD = nil
            unresolved.costIsEstimated = false
            unresolved.costIsIncomplete = true
            return unresolved
        }

        let estimatedCost = (
            Double(event.inputTokens) * pricing.inputCostPerMillion +
            Double(event.cacheWriteTokens) * pricing.cacheWriteCostPerMillion +
            Double(event.cacheReadTokens) * pricing.cacheReadCostPerMillion +
            Double(event.outputTokens) * pricing.outputCostPerMillion
        ) / 1_000_000.0

        var resolved = event
        resolved.costUSD = estimatedCost
        resolved.costIsEstimated = true
        resolved.costIsIncomplete = false
        return resolved
    }

    private func normalizeModelName(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return "unknown" }

        if value.hasPrefix("[pi] ") {
            value.removeFirst(5)
        }

        let prefixes = [
            "openrouter/openai/",
            "openrouter/anthropic/",
            "openrouter/google/",
            "openai/",
            "azure/",
            "anthropic/",
            "google/",
            "googleai/",
        ]
        for prefix in prefixes where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
            break
        }

        if value.hasSuffix(":free") || value == "openrouter/free" {
            return "free"
        }

        if value.hasPrefix("claude-"), value.count > 9 {
            let components = value.split(separator: "-")
            if let last = components.last, last.count == 8, last.allSatisfy(\.isNumber) {
                value = components.dropLast().joined(separator: "-")
            }
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
        case "gemini-3-pro-high":
            return "gemini-2.5-pro"
        case "gemini-2.5-flash-preview-09-2025":
            return "gemini-2.5-flash"
        case "gemini-2.5-flash-lite-preview-09-2025":
            return "gemini-2.5-flash-lite"
        default:
            return value
        }
    }

    private static func lookupPricing(for modelName: String) -> UsageModelPricing? {
        switch modelName {
        case "free":
            return UsageModelPricing(
                inputCostPerMillion: 0,
                cacheWriteCostPerMillion: 0,
                cacheReadCostPerMillion: 0,
                outputCostPerMillion: 0
            )

        case "gpt-5", "gpt-5-chat-latest", "gpt-5.1", "gpt-5.1-chat-latest":
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

        case "claude-sonnet-4", "claude-sonnet-4-5":
            return UsageModelPricing(
                inputCostPerMillion: 3,
                cacheWriteCostPerMillion: 3.75,
                cacheReadCostPerMillion: 0.30,
                outputCostPerMillion: 15
            )
        case "claude-opus-4", "claude-opus-4-1":
            return UsageModelPricing(
                inputCostPerMillion: 15,
                cacheWriteCostPerMillion: 18.75,
                cacheReadCostPerMillion: 1.5,
                outputCostPerMillion: 75
            )
        case "claude-haiku-3-5":
            return UsageModelPricing(
                inputCostPerMillion: 0.8,
                cacheWriteCostPerMillion: 1.0,
                cacheReadCostPerMillion: 0.08,
                outputCostPerMillion: 4
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
}
