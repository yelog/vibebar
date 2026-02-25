import AppKit
import Combine
import Foundation
import VibeBarCore

@MainActor
private enum StatusColors {
    static func activity(_ state: ToolActivityState) -> NSColor {
        AppSettings.shared.nsColor(for: state)
    }

    static func overall(_ state: ToolOverallState) -> NSColor {
        switch state {
        case .running:
            return activity(.running)
        case .awaitingInput:
            return activity(.awaitingInput)
        case .idle:
            return activity(.idle)
        case .stopped, .unknown:
            return NSColor.secondaryLabelColor
        }
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let model = MonitorViewModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        menu.delegate = self
        statusItem.menu = menu
        configureButtonIfPossible()
        bindModel()
        updateUI(summary: model.summary, sessions: model.sessions, pluginStatus: model.pluginStatus)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.postLaunchCheck()
        }
    }

    private func configureButtonIfPossible() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.appearsDisabled = false
        button.title = ""
        button.isHidden = false
        statusItem.isVisible = true
    }

    private func bindModel() {
        model.$summary
            .combineLatest(model.$sessions, model.$pluginStatus)
            .sink { [weak self] summary, sessions, pluginStatus in
                self?.updateUI(summary: summary, sessions: sessions, pluginStatus: pluginStatus)
            }
            .store(in: &cancellables)

        AppSettings.shared.$iconStyle
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateUI(summary: self.model.summary, sessions: self.model.sessions, pluginStatus: self.model.pluginStatus)
            }
            .store(in: &cancellables)

        AppSettings.shared.$colorTheme
            .dropFirst()
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateUI(summary: self.model.summary, sessions: self.model.sessions, pluginStatus: self.model.pluginStatus)
            }
            .store(in: &cancellables)
    }

    private func updateUI(summary: GlobalSummary, sessions: [SessionSnapshot], pluginStatus: PluginStatusReport) {
        guard let button = statusItem.button else { return }

        button.title = ""
        button.image = StatusImageRenderer.render(summary: summary, style: AppSettings.shared.iconStyle)
        button.toolTip = "VibeBar 会话总数: \(summary.total)"

        rebuildMenuItems(summary: summary, sessions: sessions, pluginStatus: pluginStatus)
    }

    private func rebuildMenuItems(summary: GlobalSummary, sessions: [SessionSnapshot], pluginStatus: PluginStatusReport) {
        menu.removeAllItems()

        let title = NSMenuItem(title: "VibeBar", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let updated = DateFormatter.vibeBarClock.string(from: summary.updatedAt)
        let subtitle = NSMenuItem(title: "总会话: \(summary.total) · 更新: \(updated)", action: nil, keyEquivalent: "")
        subtitle.isEnabled = false
        menu.addItem(subtitle)
        menu.addItem(.separator())

        if sessions.isEmpty {
            let empty = NSMenuItem(title: "当前未检测到支持的 TUI 会话", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for session in sessions.prefix(8) {
                let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
                item.attributedTitle = attributedSessionLine(session)
                item.target = self
                item.action = #selector(onNoop)
                item.isEnabled = true
                menu.addItem(item)
            }
        }

        // Plugin status section
        if pluginStatus.needsAttention {
            menu.addItem(.separator())
            let header = NSMenuItem(title: "插件", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for (tool, status) in pluginStatus.visibleItems {
                addPluginMenuItem(to: menu, tool: tool, status: status)
            }
        }

        menu.addItem(.separator())

        let refresh = NSMenuItem(title: "刷新", action: #selector(onRefresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        let openFolder = NSMenuItem(title: "打开状态目录", action: #selector(onOpenFolder), keyEquivalent: "o")
        openFolder.target = self
        menu.addItem(openFolder)

        let purge = NSMenuItem(title: "清理陈旧项", action: #selector(onPurgeStale), keyEquivalent: "c")
        purge.target = self
        menu.addItem(purge)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置...", action: #selector(onSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "退出 VibeBar", action: #selector(onQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func attributedSessionLine(_ session: SessionSnapshot) -> NSAttributedString {
        let prefix = "● "
        let base = "\(session.tool.displayName) · pid \(session.pid) · "
        let status = session.status.displayName
        let separator = " · "
        let directory = displayDirectory(for: session)
        let full = prefix + base + status + separator + directory

        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        )

        let statusColor = StatusColors.activity(session.status)
        attributed.addAttribute(.foregroundColor, value: statusColor, range: NSRange(location: 0, length: 1))
        attributed.addAttributes(
            [
                .foregroundColor: statusColor,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
            ],
            range: NSRange(location: prefix.count + base.count, length: status.count)
        )
        attributed.addAttribute(
            .foregroundColor,
            value: NSColor.secondaryLabelColor,
            range: NSRange(location: prefix.count + base.count + status.count + separator.count, length: directory.count)
        )

        return attributed
    }

    private func displayDirectory(for session: SessionSnapshot) -> String {
        guard let cwd = session.cwd, !cwd.isEmpty else {
            return "目录未知"
        }

        let abbreviated = (cwd as NSString).abbreviatingWithTildeInPath
        if abbreviated.count <= 70 {
            return abbreviated
        }
        return "…" + abbreviated.suffix(69)
    }

    // MARK: - Plugin Menu Items

    private func addPluginMenuItem(to menu: NSMenu, tool: ToolKind, status: PluginInstallStatus) {
        let displayName = tool.displayName + " 插件"
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let optionHeld = NSEvent.modifierFlags.contains(.option)

        switch status {
        case .installed:
            if optionHeld {
                let view = ClickableMenuItemView(
                    attributedTitle: attributedPluginOptUninstallLine(displayName)
                ) { [weak self] in
                    self?.model.uninstallPlugin(tool: tool)
                }
                item.view = view
            } else {
                item.attributedTitle = attributedPluginUpToDateLine(displayName)
                item.isEnabled = false
            }

        case .updateAvailable(let installed, let bundled):
            if optionHeld {
                let view = ClickableMenuItemView(
                    attributedTitle: attributedPluginOptUninstallUpdateLine(displayName, installed: installed, bundled: bundled)
                ) { [weak self] in
                    self?.model.uninstallPlugin(tool: tool)
                }
                item.view = view
            } else {
                let view = ClickableMenuItemView(
                    attributedTitle: attributedPluginUpdateLine(displayName, installed: installed, bundled: bundled)
                ) { [weak self] in
                    self?.model.updatePlugin(tool: tool)
                }
                item.view = view
            }

        case .notInstalled:
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginInstallLine(displayName)
            ) { [weak self] in
                self?.model.installPlugin(tool: tool)
            }
            item.view = view

        case .installing:
            item.title = "  \(displayName): 正在安装..."
            item.isEnabled = false

        case .installFailed(let message):
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginFailedLine(displayName, action: "点击重试")
            ) { [weak self] in
                self?.model.installPlugin(tool: tool)
            }
            item.view = view
            item.toolTip = message

        case .uninstalling:
            item.title = "  \(displayName): 正在卸载..."
            item.isEnabled = false

        case .uninstallFailed(let message):
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginFailedLine(displayName, action: "点击重试卸载")
            ) { [weak self] in
                self?.model.uninstallPlugin(tool: tool)
            }
            item.view = view
            item.toolTip = message

        case .checking:
            item.title = "  \(displayName): 检测中..."
            item.isEnabled = false

        case .cliNotFound:
            return

        case .updating:
            item.title = "  \(displayName): 正在更新..."
            item.isEnabled = false

        case .updateFailed(let message):
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginFailedLine(displayName, action: "点击重试更新")
            ) { [weak self] in
                self?.model.updatePlugin(tool: tool)
            }
            item.view = view
            item.toolTip = message
        }

        menu.addItem(item)
    }

    private func attributedPluginInstallLine(_ name: String) -> NSAttributedString {
        let prefix = "  \(name): 未安装 — "
        let action = "点击安装"
        let full = prefix + action
        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemBlue,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: NSRange(location: prefix.count, length: action.count)
        )
        return attributed
    }

    private func attributedPluginUpToDateLine(_ name: String) -> NSAttributedString {
        let text = "  \(name): 已安装 ✓"
        return NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
    }

    private func attributedPluginOptUninstallLine(_ name: String) -> NSAttributedString {
        let prefix = "  \(name): 已安装 ✓ — "
        let action = "⌥点击卸载"
        let full = prefix + action
        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        )
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemOrange,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: NSRange(location: prefix.count, length: action.count)
        )
        return attributed
    }

    private func attributedPluginOptUninstallUpdateLine(_ name: String, installed: String, bundled: String) -> NSAttributedString {
        let prefix = "  \(name): 有更新 \(installed) → \(bundled) — "
        let action = "⌥点击卸载"
        let full = prefix + action
        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemOrange,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: NSRange(location: prefix.count, length: action.count)
        )
        return attributed
    }

    private func attributedPluginUpdateLine(_ name: String, installed: String, bundled: String) -> NSAttributedString {
        let prefix = "  \(name): 有更新 \(installed) → \(bundled) — "
        let action = "点击更新"
        let full = prefix + action
        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemBlue,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: NSRange(location: prefix.count, length: action.count)
        )
        return attributed
    }

    private func attributedPluginFailedLine(_ name: String, action: String) -> NSAttributedString {
        let prefix = "  \(name): 失败 — "
        let full = prefix + action
        let attributed = NSMutableAttributedString(
            string: full,
            attributes: [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor,
            ]
        )
        attributed.addAttributes(
            [
                .foregroundColor: NSColor.systemRed,
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium),
            ],
            range: NSRange(location: prefix.count, length: action.count)
        )
        return attributed
    }

    @objc
    private func onRefresh() {
        model.refreshNow()
    }

    @objc
    private func onNoop() {}

    @objc
    private func onOpenFolder() {
        model.openSessionsFolder()
    }

    @objc
    private func onPurgeStale() {
        model.purgeStaleNow()
    }

    @objc
    private func onQuit() {
        NSApp.terminate(nil)
    }

    @objc
    private func onSettings() {
        SettingsWindowController.shared.showSettings()
    }

    private func postLaunchCheck() {
        if statusItem.button == nil {
            fputs("VibeBar warning: status bar button unavailable. 可能当前会话不是 GUI/Aqua 会话。\n", stderr)
        }
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        model.checkPluginStatusIfNeeded()
    }
}

@MainActor
private enum StatusImageRenderer {
    private static let segmentThreshold = 8
    private static let lineWidth: CGFloat = 2.8
    private static let gapDegrees: Double = 8.0

    // MARK: - Entry point

    static func render(summary: GlobalSummary, style: IconStyle) -> NSImage {
        switch style {
        case .ring:      return renderRing(summary: summary)
        case .particles: return renderParticles(summary: summary)
        case .energyBar: return renderEnergyBar(summary: summary)
        }
    }

    // MARK: - Shared: center number

    private static func drawCenterNumber(summary: GlobalSummary, center: NSPoint) {
        let text = "\(min(summary.total, 99))"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ]
        let textSize = text.size(withAttributes: attrs)
        let textRect = NSRect(
            x: center.x - textSize.width / 2,
            y: center.y - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attrs)
    }

    // MARK: - Ring renderer (original)

    private static func renderRing(summary: GlobalSummary) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5 - 1.6

        let baseColor: NSColor = summary.total > 0
            ? NSColor.secondaryLabelColor.withAlphaComponent(0.32)
            : NSColor.labelColor.withAlphaComponent(0.68)

        strokeArc(
            center: center,
            radius: radius,
            startFraction: 0,
            endFraction: 1,
            color: baseColor,
            lineWidth: lineWidth,
            cap: .round
        )

        if summary.total > 0 {
            let segments = expandSegments(from: summary.counts)
            if segments.count <= segmentThreshold {
                drawSegmentedRing(center: center, radius: radius, segments: segments)
            } else {
                drawContinuousRing(center: center, radius: radius, summary: summary)
            }
        }

        drawCenterNumber(summary: summary, center: center)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Particles renderer

    private static func renderParticles(summary: GlobalSummary) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size)
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.5 - 1.6

        // Faint orbit circle
        let orbitColor = NSColor.secondaryLabelColor.withAlphaComponent(0.15)
        strokeArc(
            center: center,
            radius: radius,
            startFraction: 0,
            endFraction: 1,
            color: orbitColor,
            lineWidth: 0.5,
            cap: .round
        )

        if summary.total > 0 {
            let segments: [ToolActivityState]
            if summary.total <= segmentThreshold {
                segments = expandSegments(from: summary.counts)
            } else {
                // Fixed 8 positions, proportionally assigned
                segments = distributeToSlots(counts: summary.counts, slots: 8)
            }

            let n = segments.count
            for i in 0..<n {
                // Angle from 12 o'clock, clockwise
                let angle = (Double(i) / Double(n)) * 2.0 * .pi - .pi / 2.0
                let px = center.x + CGFloat(cos(angle)) * radius
                let py = center.y + CGFloat(sin(angle)) * radius
                let color = StatusColors.activity(segments[i])

                // Outer glow
                let glowRect = NSRect(x: px - 2, y: py - 2, width: 4, height: 4)
                let glowColor = color.withAlphaComponent(0.35)
                glowColor.setFill()
                NSBezierPath(ovalIn: glowRect).fill()

                // Inner core
                let coreRect = NSRect(x: px - 1, y: py - 1, width: 2, height: 2)
                color.setFill()
                NSBezierPath(ovalIn: coreRect).fill()
            }
        }

        drawCenterNumber(summary: summary, center: center)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Energy Bar renderer

    private static func renderEnergyBar(summary: GlobalSummary) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        // Left side: number (12pt wide region)
        let numberText = "\(min(summary.total, 99))"
        let numberAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 8, weight: .bold),
            .foregroundColor: NSColor.labelColor,
        ]
        let numberSize = numberText.size(withAttributes: numberAttrs)
        let numberRect = NSRect(
            x: (12 - numberSize.width) / 2,
            y: (18 - numberSize.height) / 2,
            width: numberSize.width,
            height: numberSize.height
        )
        numberText.draw(in: numberRect, withAttributes: numberAttrs)

        // Right side: stacked color blocks
        let blockWidth: CGFloat = 3
        let blockHeight: CGFloat = 2
        let blockSpacing: CGFloat = 1
        let maxBlocks = 6
        let rightX: CGFloat = 13  // start x for blocks

        let segments: [ToolActivityState]
        if summary.total == 0 {
            segments = []
        } else if summary.total <= maxBlocks {
            segments = expandSegments(from: summary.counts)
        } else {
            segments = distributeToSlots(counts: summary.counts, slots: maxBlocks)
        }

        let blockCount = segments.count
        if blockCount > 0 {
            let totalHeight = CGFloat(blockCount) * blockHeight + CGFloat(blockCount - 1) * blockSpacing
            let startY = (18 - totalHeight) / 2

            for i in 0..<blockCount {
                let color = StatusColors.activity(segments[i])
                let y = startY + CGFloat(i) * (blockHeight + blockSpacing)
                let blockRect = NSRect(x: rightX, y: y, width: blockWidth, height: blockHeight)

                // Glow pass (expand 1pt)
                let glowRect = blockRect.insetBy(dx: -1, dy: -1)
                let glowColor = color.withAlphaComponent(0.30)
                glowColor.setFill()
                NSBezierPath(roundedRect: glowRect, xRadius: 1.5, yRadius: 1.5).fill()

                // Solid block
                color.setFill()
                NSBezierPath(roundedRect: blockRect, xRadius: 1, yRadius: 1).fill()
            }
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Proportional slot distribution

    private static func distributeToSlots(counts: [ToolActivityState: Int], slots: Int) -> [ToolActivityState] {
        let order: [ToolActivityState] = [.running, .awaitingInput, .idle, .unknown]
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }

        var result: [ToolActivityState] = []
        var remaining = slots

        for (index, state) in order.enumerated() {
            let count = counts[state, default: 0]
            guard count > 0 else { continue }

            if index == order.count - 1 || remaining <= 0 {
                // Last state gets whatever remains
                if remaining > 0 {
                    result.append(contentsOf: Array(repeating: state, count: remaining))
                }
                break
            }

            let proportion = Double(count) / Double(total)
            var slotCount = Int(round(proportion * Double(slots)))
            slotCount = max(slotCount, 1) // At least 1 slot if count > 0
            slotCount = min(slotCount, remaining)
            result.append(contentsOf: Array(repeating: state, count: slotCount))
            remaining -= slotCount
        }

        // Fill any remaining slots with the dominant state
        while result.count < slots {
            let dominant = order.first { counts[$0, default: 0] > 0 } ?? .unknown
            result.append(dominant)
        }

        return Array(result.prefix(slots))
    }

    // MARK: - Segment expansion

    private static func expandSegments(from counts: [ToolActivityState: Int]) -> [ToolActivityState] {
        let order: [ToolActivityState] = [.running, .awaitingInput, .idle, .unknown]
        var segments: [ToolActivityState] = []
        for state in order {
            let count = counts[state, default: 0]
            segments.append(contentsOf: Array(repeating: state, count: count))
        }
        return segments
    }

    // MARK: - Segmented ring (N <= 8)

    private static func drawSegmentedRing(
        center: NSPoint,
        radius: CGFloat,
        segments: [ToolActivityState]
    ) {
        let n = segments.count
        guard n > 0 else { return }

        if n == 1 {
            let color = StatusColors.activity(segments[0])
            strokeArc(center: center, radius: radius,
                       startFraction: 0, endFraction: 1,
                       color: color, lineWidth: lineWidth, cap: .round)
            return
        }

        let totalGap = Double(n) * gapDegrees
        let arcDegrees = (360.0 - totalGap) / Double(n)
        let halfGap = gapDegrees / 2.0
        let highlightRatio = 0.3

        for i in 0..<n {
            let segStart = Double(i) * (arcDegrees + gapDegrees) + halfGap
            let segEnd = segStart + arcDegrees
            let color = StatusColors.activity(segments[i])

            // Base color pass — full segment
            strokeArcDegrees(center: center, radius: radius,
                             startDeg: segStart - 90, endDeg: segEnd - 90,
                             color: color, lineWidth: lineWidth, cap: .butt)

            // Highlight pass — leading 30% of the arc
            let highlightEnd = segStart + arcDegrees * highlightRatio
            let bright = color.blended(withFraction: 0.25, of: .white) ?? color
            strokeArcDegrees(center: center, radius: radius,
                             startDeg: segStart - 90, endDeg: highlightEnd - 90,
                             color: bright, lineWidth: lineWidth, cap: .butt)
        }
    }

    // MARK: - Continuous ring (N > 8, original behavior)

    private static func drawContinuousRing(
        center: NSPoint,
        radius: CGFloat,
        summary: GlobalSummary
    ) {
        let order: [ToolActivityState] = [.running, .awaitingInput, .idle]
        var current = 0.0
        for state in order {
            let count = summary.counts[state, default: 0]
            guard count > 0 else { continue }
            let fraction = Double(count) / Double(summary.total)
            let next = current + fraction
            strokeArc(
                center: center,
                radius: radius,
                startFraction: current,
                endFraction: next,
                color: StatusColors.activity(state),
                lineWidth: lineWidth,
                cap: .round
            )
            current = next
        }
    }

    // MARK: - Arc helpers

    private static func strokeArc(
        center: NSPoint,
        radius: CGFloat,
        startFraction: Double,
        endFraction: Double,
        color: NSColor,
        lineWidth: CGFloat,
        cap: NSBezierPath.LineCapStyle
    ) {
        let start = CGFloat(startFraction * 360.0 - 90.0)
        let end = CGFloat(endFraction * 360.0 - 90.0)

        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end)
        path.lineWidth = lineWidth
        path.lineCapStyle = cap
        color.setStroke()
        path.stroke()
    }

    private static func strokeArcDegrees(
        center: NSPoint,
        radius: CGFloat,
        startDeg: Double,
        endDeg: Double,
        color: NSColor,
        lineWidth: CGFloat,
        cap: NSBezierPath.LineCapStyle
    ) {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius,
                       startAngle: CGFloat(startDeg), endAngle: CGFloat(endDeg))
        path.lineWidth = lineWidth
        path.lineCapStyle = cap
        color.setStroke()
        path.stroke()
    }

}

private extension DateFormatter {
    static let vibeBarClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - Non-closing menu item view

/// A custom NSView for NSMenuItem that handles clicks without closing the menu.
/// NSMenu only auto-closes on click for items using the standard action/target mechanism.
/// Items with a custom `view` do not trigger menu dismissal.
private final class ClickableMenuItemView: NSView {
    private let label: NSTextField
    private let onClick: () -> Void
    private var isHighlighted = false
    private let itemHeight: CGFloat = 22
    private var originalAttributedTitle: NSAttributedString

    init(attributedTitle: NSAttributedString, onClick: @escaping () -> Void) {
        self.onClick = onClick
        self.originalAttributedTitle = attributedTitle
        self.label = NSTextField(labelWithAttributedString: attributedTitle)
        label.sizeToFit()
        let labelSize = label.frame.size
        let width = labelSize.width + 28  // 14pt padding on each side
        super.init(frame: NSRect(x: 0, y: 0, width: max(width, 200), height: itemHeight))

        label.frame = NSRect(x: 14, y: (itemHeight - labelSize.height) / 2,
                             width: labelSize.width, height: labelSize.height)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(label.fittingSize.width + 28, 200), height: itemHeight)
    }

    override func mouseUp(with event: NSEvent) {
        onClick()
    }

    override func mouseEntered(with event: NSEvent) {
        isHighlighted = true
        label.attributedStringValue = whiteColoredString(originalAttributedTitle)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHighlighted = false
        label.attributedStringValue = originalAttributedTitle
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self
        ))
    }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        }
    }

    private func whiteColoredString(_ source: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: source)
        result.addAttribute(.foregroundColor, value: NSColor.white,
                            range: NSRange(location: 0, length: result.length))
        return result
    }
}
