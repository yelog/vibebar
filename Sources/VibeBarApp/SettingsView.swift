import SwiftUI
import VibeBarCore

// MARK: - Root Settings View

struct SettingsView: View {
    private enum Layout {
        static let windowWidth: CGFloat = 450
    }

    let onHeightChange: (CGFloat) -> Void
    @State private var selectedTab = 0
    @ObservedObject private var l10n = L10n.shared

    init(onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.onHeightChange = onHeightChange
    }

    private var tabs: [(name: String, icon: String)] {
        [
            (l10n.string(.tabGeneral), "gearshape.fill"),
            (l10n.string(.tabAbout), "info.circle.fill"),
        ]
    }

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

            Group {
                switch selectedTab {
                case 0:  GeneralSettingsView()
                default: AboutSettingsView()
                }
            }
        }
        .frame(width: Layout.windowWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(key: SettingsHeightPreferenceKey.self, value: proxy.size.height)
            }
        )
        .onPreferenceChange(SettingsHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            onHeightChange(height)
        }
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

private struct SettingsHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - General Tab

struct GeneralSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var wrapperCommandModel = WrapperCommandViewModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.string(.languageTitle))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .textCase(.uppercase)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Picker("", selection: $l10n.language) {
                        Text(l10n.string(.langFollowSystem)).tag(AppLanguage.system)
                        ForEach(AppLanguage.allCases.filter { $0 != .system }) { lang in
                            Text(lang.nativeName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()

                    Text(l10n.string(.languageDesc))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(l10n.string(.iconStyleTitle))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .textCase(.uppercase)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        ForEach(IconStyle.allCases) { style in
                            IconStyleCard(
                                style: style,
                                isSelected: settings.iconStyle == style
                            ) {
                                settings.iconStyle = style
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Text(l10n.string(.iconStyleDesc))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(l10n.string(.colorThemeTitle))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .textCase(.uppercase)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Picker(l10n.string(.colorThemeTitle), selection: $settings.colorTheme) {
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

                    Text(l10n.string(.colorThemeDesc))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Divider()

                    CustomColorRow(
                        label: l10n.string(.stateRunning),
                        color: $settings.customRunningColor,
                        settings: settings
                    )
                    CustomColorRow(
                        label: l10n.string(.stateAwaitingInput),
                        color: $settings.customAwaitingColor,
                        settings: settings
                    )
                    CustomColorRow(
                        label: l10n.string(.stateIdle),
                        color: $settings.customIdleColor,
                        settings: settings
                    )
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(l10n.string(.systemTitle))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .textCase(.uppercase)

            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(l10n.string(.launchAtLogin), isOn: $settings.launchAtLogin)
                        .font(.system(size: 13))

                    Text(l10n.string(.launchAtLoginDesc))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)

                    Divider()
                        .padding(.vertical, 2)

                    Toggle(l10n.string(.notifyAwaitingInput), isOn: $settings.notifyAwaitingInput)
                        .font(.system(size: 13))

                    Text(l10n.string(.notifyAwaitingInputDesc))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(l10n.string(.wrapperCommandTitle))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .textCase(.uppercase)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("vibebar")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        wrapperCommandActionView
                    }

                    Text(l10n.string(.wrapperCommandDesc))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if let path = wrapperCommandPath {
                        Text(l10n.string(.wrapperCommandPathFmt, path))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    if wrapperCommandShowsExternalHint {
                        Text(l10n.string(.wrapperCommandExternalHint))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    if let error = wrapperCommandError {
                        Text(error)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 20)
        .onAppear {
            wrapperCommandModel.refreshIfNeeded()
        }
    }

    @ViewBuilder
    private var wrapperCommandActionView: some View {
        switch wrapperCommandModel.status {
        case .checking:
            statusText(l10n.string(.wrapperCommandChecking))
        case .notInstalled:
            actionTextButton(l10n.string(.wrapperCommandInstallNow), color: .blue) {
                wrapperCommandModel.installCommand()
            }
        case .installedManaged:
            HStack(spacing: 10) {
                statusText(l10n.string(.wrapperCommandInstalled))
                actionTextButton(l10n.string(.wrapperCommandUninstallNow), color: .orange) {
                    wrapperCommandModel.uninstallCommand()
                }
            }
        case .installedExternal:
            statusText(l10n.string(.wrapperCommandInstalledExternal))
        case .installing:
            statusText(l10n.string(.wrapperCommandInstalling))
        case .uninstalling:
            statusText(l10n.string(.wrapperCommandUninstalling))
        case .installFailed:
            actionTextButton(l10n.string(.wrapperCommandRetry), color: .blue) {
                wrapperCommandModel.installCommand()
            }
        case .uninstallFailed:
            actionTextButton(l10n.string(.wrapperCommandRetry), color: .orange) {
                wrapperCommandModel.uninstallCommand()
            }
        }
    }

    private var wrapperCommandPath: String? {
        switch wrapperCommandModel.status {
        case .installedManaged(let path), .installedExternal(let path):
            return path
        default:
            return nil
        }
    }

    private var wrapperCommandShowsExternalHint: Bool {
        if case .installedExternal = wrapperCommandModel.status {
            return true
        }
        return false
    }

    private var wrapperCommandError: String? {
        switch wrapperCommandModel.status {
        case .installFailed(let message), .uninstallFailed(let message):
            return message
        default:
            return nil
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
    }

    private func actionTextButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
    }
}

// MARK: - About Tab

struct AboutSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var l10n = L10n.shared

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

                Text(l10n.string(.versionFmt, BuildInfo.version))
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
                Text(l10n.string(.updateTitle))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)
                    .textCase(.uppercase)

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(l10n.string(.autoCheckUpdates), isOn: $settings.autoCheckUpdates)
                            .font(.system(size: 13))

                        Text(l10n.string(.autoCheckUpdatesDesc))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 20)
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(l10n.string(.checkUpdatesBtn)) {
                    UpdateChecker.shared.checkForUpdates(silent: false)
                }
                .controlSize(.regular)
            }
            .padding(.horizontal, 28)

        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 20)
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

// MARK: - Icon Style Card

private struct IconStyleCard: View {
    let style: IconStyle
    let isSelected: Bool
    let onTap: () -> Void

    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                Image(nsImage: StatusImageRenderer.renderPreview(style: style))
                    .interpolation(.high)
                    .frame(width: 48, height: 48)

                Text(style.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 72, height: 72)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
