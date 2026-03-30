import Foundation

public enum UsageTokenFormatter {
    private static let unitSuffixes = ["", "K", "M", "B"]

    public static func compactTokenLabel(_ tokens: Int, decimals: Int = 0) -> String {
        let clamped = max(tokens, 0)
        guard clamped >= 1_000 else { return "\(clamped)" }

        var value = Double(clamped)
        var unitIndex = 0

        while value >= 999.5, unitIndex < unitSuffixes.count - 1 {
            value /= 1_000.0
            unitIndex += 1
        }

        let rounded = (value * 10).rounded() / 10
        var adjustedValue = rounded
        var adjustedIndex = unitIndex

        if rounded >= 1_000, unitIndex < unitSuffixes.count - 1 {
            adjustedValue /= 1_000.0
            adjustedIndex += 1
        }

        let format = decimals == 0 ? "%.0f" : String(format: "%%.%df", decimals)
        return String(format: format, adjustedValue) + unitSuffixes[adjustedIndex]
    }

    public static func tooltipTokenText(_ tokens: Int) -> String {
        let unit = tokens == 1 ? "token" : "tokens"
        return "\(compactTokenLabel(tokens, decimals: 0)) \(unit)"
    }

    public static func footerTokenText(_ tokens: Int) -> String {
        let unit = tokens == 1 ? "token" : "tokens"
        return "\(compactTokenLabel(tokens, decimals: 1)) \(unit)"
    }
}
