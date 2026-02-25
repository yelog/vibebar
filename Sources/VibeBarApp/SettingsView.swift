import SwiftUI
import VibeBarCore

// MARK: - Root Settings View

struct SettingsView: View {
    @State private var selectedTab = 0

    private let tabs: [(name: String, icon: String)] = [
        ("通用", "gearshape.fill"),
        ("关于", "info.circle.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar — color-only selection, no focus-ring border
            HStack(spacing: 20) {
                ForEach(tabs.indices, id: \.self) { index in
                    tabButton(for: index)
                }
            }
            .frame(height: 46)
            .padding(.top, 28)
            .padding(.bottom, 12)

            Divider()
                .padding(.horizontal, 24)

            ZStack(alignment: .topLeading) {
                GeneralSettingsView()
                    .opacity(selectedTab == 0 ? 1 : 0)

                AboutSettingsView()
                    .opacity(selectedTab == 1 ? 1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 450, height: 500)
    }

    @ViewBuilder
    private func tabButton(for index: Int) -> some View {
        let selected = selectedTab == index

        Button {
            selectedTab = index
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tabs[index].icon)
                    .font(.system(size: 18))
                Text(tabs[index].name)
                    .font(.system(size: 10))
            }
            .foregroundStyle(selected ? .primary : Color.secondary.opacity(0.55))
            .frame(width: 58, height: 46)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - General Tab

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("图标样式")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .textCase(.uppercase)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $settings.iconStyle) {
                        ForEach(IconStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text("选择菜单栏中显示的图标样式")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("颜色方案")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .textCase(.uppercase)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("颜色方案", selection: $settings.colorTheme) {
                        ForEach(ColorTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .onChange(of: settings.colorTheme) { newTheme in
                        if newTheme != .custom {
                            settings.applyPresetToCustomColors(newTheme)
                        }
                    }

                    Text("选择会话状态的配色方案")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Divider()

                    CustomColorRow(
                        label: "运行中",
                        color: $settings.customRunningColor,
                        settings: settings
                    )
                    CustomColorRow(
                        label: "等待用户",
                        color: $settings.customAwaitingColor,
                        settings: settings
                    )
                    CustomColorRow(
                        label: "空闲",
                        color: $settings.customIdleColor,
                        settings: settings
                    )
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text("系统")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .textCase(.uppercase)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("开机时自动启动", isOn: $settings.launchAtLogin)
                        .font(.system(size: 13))

                    Text("登录 macOS 时自动在后台启动 VibeBar")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
    }
}

// MARK: - About Tab

struct AboutSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 12) {
            // Icon + version info
            VStack(spacing: 6) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.cyan.opacity(0.12), radius: 16, x: 0, y: 6)
                }

                Text("VibeBar")
                    .font(.system(size: 16, weight: .bold))

                Text("版本 \(BuildInfo.version)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color.primary.opacity(0.55))

                Text(BuildInfo.buildTime)
                    .font(.system(size: 11))
                    .foregroundColor(Color.primary.opacity(0.35))
            }
            .padding(.top, 8)

            Divider().padding(.horizontal, 28)

            // Links with hover highlight
            GroupBox {
                VStack(spacing: 0) {
                    LinkRow(title: "GitHub", urlString: "https://github.com/yelog/VibeBar")
                    Divider().padding(.horizontal, 4)
                    LinkRow(title: "Twitter", urlString: "https://twitter.com/yaborz")
                    Divider().padding(.horizontal, 4)
                    LinkRow(title: "Email", urlString: "mailto:jaytp@qq.com")
                }
            }
            .padding(.horizontal, 28)

            Divider().padding(.horizontal, 28)

            // Update section — checkbox card style
            VStack(alignment: .leading, spacing: 12) {
                Text("更新")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .textCase(.uppercase)

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("自动检查更新", isOn: $settings.autoCheckUpdates)
                            .font(.system(size: 13))

                        Text("启动时检查 GitHub Releases 是否有新版本")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 20)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button("检查更新…") {
                    UpdateChecker.shared.checkForUpdates(silent: false)
                }
                .controlSize(.regular)
            }
            .padding(.horizontal, 28)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

// MARK: - Link Row (with hover)

private struct LinkRow: View {
    let title: String
    let urlString: String
    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isHovered ? Color.primary.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Custom Color Row

private struct CustomColorRow: View {
    let label: String
    @Binding var color: Color
    let settings: AppSettings

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: color) { _ in
                    if settings.colorTheme != .custom {
                        settings.colorTheme = .custom
                    }
                }
        }
    }
}
