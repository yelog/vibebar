import SwiftUI
import VibeBarCore

struct MenuContentView: View {
    @ObservedObject var model: MonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                ForEach(ToolKind.allCases) { tool in
                    toolRow(tool)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("会话详情")
                    .font(.subheadline.weight(.semibold))

                if model.sessions.isEmpty {
                    Text("当前未检测到支持的 TUI 会话")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.sessions.prefix(8)) { session in
                        sessionRow(session)
                    }
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button("打开状态目录") {
                    model.openSessionsFolder()
                }

                Button("清理完成项") {
                    model.purgeCompleted()
                }

                Spacer(minLength: 0)

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 360)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VibeBar")
                .font(.headline)

            HStack {
                Text("总会话: \(model.summary.total)")
                Spacer()
                Text("更新: \(Self.timeFormatter.string(from: model.summary.updatedAt))")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(legendText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var legendText: String {
        "颜色: 绿=运行中, 橙=等待用户, 蓝=空闲, 青=已完成"
    }

    @ViewBuilder
    private func toolRow(_ tool: ToolKind) -> some View {
        let summary = model.summary.byTool[tool] ?? ToolSummary(tool: tool, total: 0, counts: [:], overall: .stopped)

        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle()
                    .fill(color(for: summary.overall))
                    .frame(width: 8, height: 8)

                Text(tool.displayName)
                    .font(.subheadline)

                Spacer()

                Text("\(summary.total)")
                    .font(.subheadline.monospacedDigit())
            }

            Text(summaryText(summary))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sessionRow(_ session: SessionSnapshot) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color(for: session.status))
                .frame(width: 6, height: 6)

            Text("\(session.tool.displayName) • pid \(session.pid)")
                .font(.caption)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(session.status.displayName)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func summaryText(_ summary: ToolSummary) -> String {
        let running = summary.counts[.running, default: 0]
        let awaiting = summary.counts[.awaitingInput, default: 0]
        let idle = summary.counts[.idle, default: 0]
        let completed = summary.counts[.completed, default: 0]
        return "运行 \(running) / 等待 \(awaiting) / 空闲 \(idle) / 完成 \(completed)"
    }

    private func color(for state: ToolOverallState) -> Color {
        switch state {
        case .running:
            return color(for: ToolActivityState.running)
        case .awaitingInput:
            return color(for: ToolActivityState.awaitingInput)
        case .idle:
            return color(for: ToolActivityState.idle)
        case .completed:
            return color(for: ToolActivityState.completed)
        case .stopped:
            return .gray
        case .unknown:
            return .secondary
        }
    }

    private func color(for state: ToolActivityState) -> Color {
        switch state {
        case .running:
            return Color(red: 0.17, green: 0.70, blue: 0.32)
        case .awaitingInput:
            return Color(red: 0.95, green: 0.55, blue: 0.12)
        case .idle:
            return Color(red: 0.20, green: 0.53, blue: 0.98)
        case .completed:
            return Color(red: 0.15, green: 0.75, blue: 0.70)
        case .unknown:
            return .secondary
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
