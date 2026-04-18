import AppKit
import Testing
import VibeBarCore
@testable import VibeBarApp

@MainActor
@Test func stateDrivenBadgeUsesAccentBaseColor() {
    let baseColor = NSColor(calibratedRed: 0.22, green: 0.44, blue: 0.66, alpha: 1)
    let badge = SessionBadge(
        kind: .duration,
        text: "运行中 3m",
        tone: .status,
        accentState: .running
    )

    let colors = SessionBadgeStyle.resolvedColors(for: badge, accentBaseColor: baseColor)

    #expect(colors.textColor.isApproximatelyEqual(to: baseColor))
    #expect(colors.borderColor.alphaComponent.isApproximatelyEqual(to: 0.32))
    #expect(colors.fillColor.alphaComponent.isApproximatelyEqual(to: 0.16))
}

@MainActor
@Test func highlightedBadgeOverridesAccentPalette() {
    let badge = SessionBadge(
        kind: .duration,
        text: "等待输入 1m",
        tone: .status,
        accentState: .awaitingInput
    )

    let colors = SessionBadgeStyle.resolvedColors(
        for: badge,
        accentBaseColor: .systemOrange,
        highlighted: true
    )

    #expect(colors.textColor.isApproximatelyEqual(to: .white))
    #expect(colors.borderColor.alphaComponent.isApproximatelyEqual(to: 0.28))
    #expect(colors.fillColor.alphaComponent.isApproximatelyEqual(to: 0.14))
}

@MainActor
@Test func notchStatusBadgeUsesAppearanceThemeColor() {
    let badge = SessionBadge(
        kind: .duration,
        text: "空闲 3m",
        tone: .status,
        accentState: .idle
    )

    let colors = SessionBadgeStyle.resolvedColors(
        for: badge,
        appearance: .notch
    )

    let expected = AppSettings.shared.nsColor(for: .idle)

    #expect(colors.textColor.isApproximatelyEqual(to: expected))
    #expect(colors.borderColor.alphaComponent.isApproximatelyEqual(to: 0.32))
    #expect(colors.fillColor.alphaComponent.isApproximatelyEqual(to: 0.16))
}

@MainActor
@Test func semanticToneBadgesKeepExistingPalette() {
    let badge = SessionBadge(kind: .client, text: "Ghostty", tone: .client)

    let colors = SessionBadgeStyle.resolvedColors(for: badge)

    #expect(colors.textColor.isApproximatelyEqual(to: .systemBlue))
    #expect(colors.borderColor.alphaComponent.isApproximatelyEqual(to: 0.28))
    #expect(colors.fillColor.alphaComponent.isApproximatelyEqual(to: 0.14))
}

private extension NSColor {
    func isApproximatelyEqual(to other: NSColor, tolerance: CGFloat = 0.002) -> Bool {
        let lhs = rgbaComponents
        let rhs = other.rgbaComponents
        return abs(lhs.red - rhs.red) <= tolerance
            && abs(lhs.green - rhs.green) <= tolerance
            && abs(lhs.blue - rhs.blue) <= tolerance
            && abs(lhs.alpha - rhs.alpha) <= tolerance
    }

    var rgbaComponents: (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let converted = self.usingColorSpace(.sRGB)
            ?? self.usingColorSpace(.deviceRGB)
            ?? self
        return (
            red: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: converted.alphaComponent
        )
    }
}

private extension CGFloat {
    func isApproximatelyEqual(to other: CGFloat, tolerance: CGFloat = 0.002) -> Bool {
        abs(self - other) <= tolerance
    }
}
