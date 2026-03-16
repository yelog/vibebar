import Foundation

public struct UsagePricingResolver: Sendable {
    public init() {}

    public func normalizedModelName(for rawValue: String) -> String {
        normalizeModelName(rawValue)
    }

    public func pricing(for modelName: String) async -> UsageModelPricing? {
        await PricingManager.shared.getPricing(for: modelName)
    }

    public func pricing(forNormalizedModelName normalizedModelName: String) async -> UsageModelPricing? {
        await PricingManager.shared.getPricing(for: normalizedModelName)
    }

    public func resolveCost(for event: UsageEvent) async -> UsageEvent {
        let pricing = await PricingManager.shared.getPricing(for: event.modelName)
        return resolveCost(
            for: event,
            normalizedModelName: normalizeModelName(event.modelName),
            pricing: pricing
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

        let estimatedCost = calculateTieredCost(
            inputTokens: event.inputTokens,
            outputTokens: event.outputTokens,
            cacheWriteTokens: event.cacheWriteTokens,
            cacheReadTokens: event.cacheReadTokens,
            pricing: pricing
        )

        var resolved = event
        resolved.costUSD = estimatedCost
        resolved.costIsEstimated = true
        resolved.costIsIncomplete = false
        return resolved
    }

    private func calculateTieredCost(
        inputTokens: Int,
        outputTokens: Int,
        cacheWriteTokens: Int,
        cacheReadTokens: Int,
        pricing: UsageModelPricing
    ) -> Double {
        let threshold: Int = 200_000

        let inputCost = tieredCost(
            tokens: inputTokens,
            basePrice: pricing.inputCostPerMillion,
            tieredPrice: pricing.inputCostPerMillionAbove200k,
            threshold: threshold
        )

        let outputCost = tieredCost(
            tokens: outputTokens,
            basePrice: pricing.outputCostPerMillion,
            tieredPrice: pricing.outputCostPerMillionAbove200k,
            threshold: threshold
        )

        let cacheWriteCost = tieredCost(
            tokens: cacheWriteTokens,
            basePrice: pricing.cacheWriteCostPerMillion,
            tieredPrice: pricing.cacheWriteCostPerMillionAbove200k,
            threshold: threshold
        )

        let cacheReadCost = tieredCost(
            tokens: cacheReadTokens,
            basePrice: pricing.cacheReadCostPerMillion,
            tieredPrice: pricing.cacheReadCostPerMillionAbove200k,
            threshold: threshold
        )

        return (inputCost + outputCost + cacheWriteCost + cacheReadCost) / 1_000_000
    }

    private func tieredCost(
        tokens: Int,
        basePrice: Double,
        tieredPrice: Double?,
        threshold: Int
    ) -> Double {
        guard tokens > 0 else { return 0 }

        if tokens > threshold, let tiered = tieredPrice {
            let below = min(tokens, threshold)
            let above = tokens - threshold
            return Double(below) * basePrice + Double(above) * tiered
        }

        return Double(tokens) * basePrice
    }

    private func normalizeModelName(_ raw: String) -> String {
        var value = raw.lowercased()

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

        if value.hasSuffix("-latest") {
            value = String(value.dropLast(7))
        }

        return value
    }
}