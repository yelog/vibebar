import AppKit
import Combine
import Foundation
import VibeBarCore

private enum StatusColors {
    static func activity(_ state: ToolActivityState) -> NSColor {
        switch state {
        case .running:
            return NSColor(calibratedRed: 0.10, green: 0.82, blue: 0.30, alpha: 1)
        case .awaitingInput:
            return NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.00, alpha: 1)
        case .idle:
            return NSColor(calibratedRed: 0.10, green: 0.57, blue: 1.00, alpha: 1)
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
}

@MainActor
final class StatusItemController: NSObject {
    private let model = MonitorViewModel()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables = Set<AnyCancellable>()

    override init() {
        super.init()
        configureButtonIfPossible()
        bindModel()
        updateUI(summary: model.summary, sessions: model.sessions)

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.postLaunchCheck()
        }
    }

    private func configureButtonIfPossible() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageLeading
        button.appearsDisabled = false
        button.title = "VB0"
        button.isHidden = false
        statusItem.isVisible = true
    }

    private func bindModel() {
        model.$summary
            .combineLatest(model.$sessions)
            .sink { [weak self] summary, sessions in
                self?.updateUI(summary: summary, sessions: sessions)
            }
            .store(in: &cancellables)
    }

    private func updateUI(summary: GlobalSummary, sessions: [SessionSnapshot]) {
        guard let button = statusItem.button else { return }

        button.title = "VB\(summary.total)"
        button.image = StatusImageRenderer.render(summary: summary)
        button.toolTip = "VibeBar 会话总数: \(summary.total)"

        statusItem.menu = buildMenu(summary: summary, sessions: sessions)
    }

    private func buildMenu(summary: GlobalSummary, sessions: [SessionSnapshot]) -> NSMenu {
        let menu = NSMenu()

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

        return menu
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

private enum StatusImageRenderer {
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
            lineWidth: 2.8
        )

        let order: [ToolActivityState] = [.running, .awaitingInput, .idle]
        var current = 0.0
        if summary.total > 0 {
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
                    lineWidth: 2.8
                )
                current = next
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

    private static func strokeArc(
        center: NSPoint,
        radius: CGFloat,
        startFraction: Double,
        endFraction: Double,
        color: NSColor,
        lineWidth: CGFloat
    ) {
        let start = CGFloat(startFraction * 360.0 - 90.0)
        let end = CGFloat(endFraction * 360.0 - 90.0)

        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
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
