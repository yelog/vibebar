import AppKit
import Combine
import Foundation
import VibeBarCore

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

        for tool in ToolKind.allCases {
            let toolSummary = summary.byTool[tool] ?? ToolSummary(tool: tool, total: 0, counts: [:], overall: .stopped)
            let item = NSMenuItem(title: toolLine(toolSummary), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        if sessions.isEmpty {
            let empty = NSMenuItem(title: "当前未检测到支持的 TUI 会话", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for session in sessions.prefix(8) {
                let line = "\(session.tool.displayName) · pid \(session.pid) · \(session.status.displayName)"
                let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                item.isEnabled = false
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

        let purge = NSMenuItem(title: "清理完成项", action: #selector(onPurgeCompleted), keyEquivalent: "c")
        purge.target = self
        menu.addItem(purge)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出 VibeBar", action: #selector(onQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func toolLine(_ summary: ToolSummary) -> String {
        let running = summary.counts[.running, default: 0]
        let awaiting = summary.counts[.awaitingInput, default: 0]
        let idle = summary.counts[.idle, default: 0]
        let completed = summary.counts[.completed, default: 0]

        return "\(summary.tool.displayName): \(summary.total)（运行 \(running) / 等待 \(awaiting) / 空闲 \(idle) / 完成 \(completed)）"
    }

    @objc
    private func onRefresh() {
        model.refreshNow()
    }

    @objc
    private func onOpenFolder() {
        model.openSessionsFolder()
    }

    @objc
    private func onPurgeCompleted() {
        model.purgeCompleted()
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

        let order: [ToolActivityState] = [.running, .awaitingInput, .idle, .completed]
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
                    color: color(for: state),
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

    private static func color(for state: ToolActivityState) -> NSColor {
        switch state {
        case .running:
            return NSColor(calibratedRed: 0.17, green: 0.70, blue: 0.32, alpha: 1)
        case .awaitingInput:
            return NSColor(calibratedRed: 0.95, green: 0.55, blue: 0.12, alpha: 1)
        case .idle:
            return NSColor(calibratedRed: 0.20, green: 0.53, blue: 0.98, alpha: 1)
        case .completed:
            return NSColor(calibratedRed: 0.15, green: 0.75, blue: 0.70, alpha: 1)
        case .unknown:
            return NSColor.secondaryLabelColor
        }
    }
}

private extension DateFormatter {
    static let vibeBarClock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
