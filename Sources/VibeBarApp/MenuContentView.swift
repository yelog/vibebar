import SwiftUI
import VibeBarCore

struct MenuContentView: View {
    @ObservedObject var model: MonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("会话")
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

                Button("清理陈旧项") {
                    model.purgeStaleNow()
                }

                Spacer(minLength: 0)

                Button("退出") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
        .padding(12)
        .frame(width: 420)
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
        "颜色: 亮绿=运行中, 亮黄=等待用户, 亮蓝=空闲"
    }

    @ViewBuilder
    private func sessionRow(_ session: SessionSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Circle()
                    .fill(color(for: session.status))
                    .frame(width: 6, height: 6)

                Text("\(session.tool.displayName) • pid \(session.pid)")
                    .font(.caption)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(session.status.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(color(for: session.status))
            }

            Text(displayDirectory(for: session))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func color(for state: ToolActivityState) -> Color {
        switch state {
        case .running:
            return Color(red: 0.10, green: 0.82, blue: 0.30)
        case .awaitingInput:
            return Color(red: 1.0, green: 0.70, blue: 0.00)
        case .idle:
            return Color(red: 0.10, green: 0.57, blue: 1.00)
        case .unknown:
            return .secondary
        }
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
