import AppKit
import Combine
import Foundation
import VibeBarCore

private enum StatusColors {
    static func activity(_ state: ToolActivityState) -> NSColor {
        switch state {
        case .running:
            return dynamicColor(
                dark: NSColor(calibratedRed: 0.10, green: 0.82, blue: 0.30, alpha: 1),
                light: NSColor(calibratedRed: 0.08, green: 0.66, blue: 0.24, alpha: 1)
            )
        case .awaitingInput:
            return dynamicColor(
                dark: NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.00, alpha: 1),
                light: NSColor(calibratedRed: 0.90, green: 0.58, blue: 0.00, alpha: 1)
            )
        case .idle:
            return dynamicColor(
                dark: NSColor(calibratedRed: 0.10, green: 0.57, blue: 1.00, alpha: 1),
                light: NSColor(calibratedRed: 0.00, green: 0.48, blue: 1.00, alpha: 1)
            )
        case .unknown:
            return NSColor.secondaryLabelColor
        }
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

    private static func dynamicColor(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
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
    }

    private func updateUI(summary: GlobalSummary, sessions: [SessionSnapshot], pluginStatus: PluginStatusReport) {
        guard let button = statusItem.button else { return }

        button.title = ""
        button.image = StatusImageRenderer.render(summary: summary)
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

        switch status {
        case .installed:
            let view = ClickableMenuItemView(
                attributedTitle: attributedPluginInstalledLine(displayName)
            ) { [weak self] in
                self?.model.uninstallPlugin(tool: tool)
            }
            item.view = view

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

    private func attributedPluginInstalledLine(_ name: String) -> NSAttributedString {
        let prefix = "  \(name): 已安装 ✓ — "
        let action = "点击卸载"
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

private enum StatusImageRenderer {
    private static let segmentThreshold = 8
    private static let lineWidth: CGFloat = 2.8
    private static let gapDegrees: Double = 8.0

    static func render(summary: GlobalSummary) -> NSImage {
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

        image.unlockFocus()
        image.isTemplate = false
        return image
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
