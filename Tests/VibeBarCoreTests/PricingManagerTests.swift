import Foundation
import Testing
@testable import VibeBarCore

@Suite("Pricing Manager Tests")
struct PricingManagerTests {
    
    @Test func pricingManagerLoadsPricing() async {
        await PricingManager.shared.initialize()
        
        let claudePricing = await PricingManager.shared.getPricing(for: "claude-sonnet-4")
        #expect(claudePricing != nil)
        #expect(claudePricing?.inputCostPerMillion ?? 0 > 0)
        
        let gpt5Pricing = await PricingManager.shared.getPricing(for: "gpt-5")
        #expect(gpt5Pricing != nil)
        #expect(gpt5Pricing?.inputCostPerMillion ?? 0 > 0)
    }
    
    @Test func pricingManagerHandlesUnknownModel() async {
        await PricingManager.shared.initialize()
        
        let unknownPricing = await PricingManager.shared.getPricing(for: "unknown-model-xyz")
        #expect(unknownPricing == nil)
    }
    
    @Test func tieredPricingCalculation() async {
        let pricing = UsageModelPricing(
            inputCostPerMillion: 3,
            cacheWriteCostPerMillion: 3.75,
            cacheReadCostPerMillion: 0.30,
            outputCostPerMillion: 15,
            inputCostPerMillionAbove200k: 6,
            outputCostPerMillionAbove200k: 30
        )
        
        let resolver = UsagePricingResolver()
        let event = UsageEvent(
            id: "test",
            source: .claudeCode,
            sessionID: "test-session",
            timestamp: Date(),
            modelName: "test-model",
            inputTokens: 300_000,
            outputTokens: 250_000,
            cacheReadTokens: 0,
            cacheWriteTokens: 0
        )
        
        let resolved = resolver.resolveCost(
            for: event,
            normalizedModelName: "test-model",
            pricing: pricing
        )
        
        #expect(resolved.costUSD != nil)
        #expect(resolved.costUSD! > 0)
        #expect(resolved.costIsEstimated == true)
    }
}