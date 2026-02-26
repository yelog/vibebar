import SwiftUI
import VibeBarCore

private enum SettingsPanelLayout {
    static let windowWidth: CGFloat = 450
    static let horizontalPadding: CGFloat = 24
    static let tabBarHeight: CGFloat = 70
    static let sectionSpacing: CGFloat = 16
    static let cardCornerRadius: CGFloat = 14
}

enum SettingsTab: Int, CaseIterable {
    case general
    case about
}

@MainActor
final class SettingsViewState: ObservableObject {
    @Published var selectedTab: SettingsTab = .general
}

// MARK: - Root Settings View

struct SettingsView: View {
    let onHeightChange: (CGFloat) -> Void
    @ObservedObject private var viewState: SettingsViewState
    @State private var hoveredTab: SettingsTab?
    @ObservedObject private var l10n = L10n.shared

    init(viewState: SettingsViewState, onHeightChange: @escaping (CGFloat) -> Void = { _ in }) {
        self.viewState = viewState
        self.onHeightChange = onHeightChange
    }

    private var tabs: [(tab: SettingsTab, name: String, icon: String)] {
        [
            (.general, l10n.string(.tabGeneral), "gearshape.fill"),
            (.about, l10n.string(.tabAbout), "info.circle.fill"),
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ForEach(tabs, id: \.tab) { tab in
                    tabButton(for: tab)
                }
            }
            .padding(.horizontal, SettingsPanelLayout.horizontalPadding)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity)
            .frame(height: SettingsPanelLayout.tabBarHeight)

            Divider()

            Group {
                switch viewState.selectedTab {
                case .general:
                    GeneralSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .padding(.top, 10)
        }
        .frame(width: SettingsPanelLayout.windowWidth)
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
    private func tabButton(for tab: (tab: SettingsTab, name: String, icon: String)) -> some View {
        let selected = viewState.selectedTab == tab.tab
        let hovered = hoveredTab == tab.tab

        Button {
            viewState.selectedTab = tab.tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)

                Text(tab.name)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(
                selected
                ? Color.accentColor
                : Color.primary.opacity(hovered ? 0.84 : 0.66)
            )
            .frame(maxWidth: .infinity, minHeight: 36)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(backgroundFill(selected: selected, hovered: hovered))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(borderColor(selected: selected, hovered: hovered), lineWidth: selected ? 1.2 : 1)
            )
            .shadow(
                color: selected ? Color.accentColor.opacity(0.14) : .clear,
                radius: 6,
                x: 0,
                y: 2
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering in
            hoveredTab = isHovering ? tab.tab : (hoveredTab == tab.tab ? nil : hoveredTab)
        }
    }

    private func backgroundFill(selected: Bool, hovered: Bool) -> Color {
        if selected {
            return Color.accentColor.opacity(0.14)
        }
        if hovered {
            return Color.white.opacity(0.06)
        }
        return .clear
    }

    private func borderColor(selected: Bool, hovered: Bool) -> Color {
        if selected {
            return Color.accentColor.opacity(0.45)
        }
        if hovered {
            return Color.white.opacity(0.22)
        }
        return .clear
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
    private let iconColumns = Array(repeating: GridItem(.flexible(minimum: 72), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionSpacing) {
            SettingsSection(title: l10n.string(.languageTitle)) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $l10n.language) {
                        Text(l10n.string(.langFollowSystem)).tag(AppLanguage.system)
                        ForEach(AppLanguage.allCases.filter { $0 != .system }) { lang in
                            Text(lang.nativeName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 190, alignment: .leading)

                    Text(l10n.string(.languageDesc))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection(title: l10n.string(.iconStyleTitle)) {
                VStack(alignment: .leading, spacing: 8) {
                    LazyVGrid(columns: iconColumns, spacing: 8) {
                        ForEach(IconStyle.allCases) { style in
                            IconStyleCard(
                                style: style,
                                isSelected: settings.iconStyle == style
                            ) {
                                settings.iconStyle = style
                            }
                        }
                    }

                    Text(l10n.string(.iconStyleDesc))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            SettingsSection(title: l10n.string(.colorThemeTitle)) {
                VStack(alignment: .leading, spacing: 8) {
                    Picker(l10n.string(.colorThemeTitle), selection: $settings.colorTheme) {
                        ForEach(ColorTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 190, alignment: .leading)
                    .onChange(of: settings.colorTheme) { newTheme in
                        if newTheme != .custom {
                            settings.applyPresetToCustomColors(newTheme)
                        }
                    }

                    Text(l10n.string(.colorThemeDesc))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Divider()

                    VStack(spacing: 6) {
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
                }
            }

            SettingsSection(title: l10n.string(.systemTitle)) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsToggleRow(
                        title: l10n.string(.launchAtLogin),
                        description: l10n.string(.launchAtLoginDesc),
                        isOn: $settings.launchAtLogin
                    )

                    Divider()
                        .padding(.vertical, 1)

                    SettingsToggleRow(
                        title: l10n.string(.notifyAwaitingInput),
                        description: l10n.string(.notifyAwaitingInputDesc),
                        isOn: $settings.notifyAwaitingInput
                    )
                }
            }

            SettingsSection(title: l10n.string(.wrapperCommandTitle)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("vibebar")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Spacer()
                        wrapperCommandActionView
                    }

                    Text(l10n.string(.wrapperCommandDesc))
                        .font(.system(size: 12))
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
            }

        }
        .padding(.horizontal, SettingsPanelLayout.horizontalPadding)
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
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.08))
            )
    }

    private func actionTextButton(_ title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(color.opacity(0.18))
                )
                .overlay(
                    Capsule()
                        .strokeBorder(color.opacity(0.46), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
    }
}

// MARK: - About Tab

struct AboutSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionSpacing) {
            HStack(spacing: 12) {
                if let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .shadow(color: Color.cyan.opacity(0.12), radius: 16, x: 0, y: 6)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("VibeBar")
                        .font(.system(size: 16, weight: .bold))

                    Text(l10n.string(.versionFmt, BuildInfo.version))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.primary.opacity(0.55))

                    Text(BuildInfo.buildTime)
                        .font(.system(size: 11))
                        .foregroundColor(Color.primary.opacity(0.35))
                }
                Spacer(minLength: 0)
            }

            SettingsCard {
                VStack(spacing: 0) {
                    LinkRow(title: "GitHub", urlString: "https://github.com/yelog/VibeBar")
                    Divider().padding(.horizontal, 4)
                    LinkRow(title: "Twitter", urlString: "https://x.com/yelogeek")
                    Divider().padding(.horizontal, 4)
                    LinkRow(title: "Email", urlString: "mailto:yelogeek@gmail.com")
                }
            }

            SettingsSection(title: l10n.string(.updateTitle)) {
                SettingsToggleRow(
                    title: l10n.string(.autoCheckUpdates),
                    description: l10n.string(.autoCheckUpdatesDesc),
                    isOn: $settings.autoCheckUpdates
                )

                Button(l10n.string(.checkUpdatesBtn)) {
                    UpdateChecker.shared.checkForUpdates(silent: false)
                }
                .controlSize(.small)
            }

        }
        .padding(.horizontal, SettingsPanelLayout.horizontalPadding)
        .padding(.bottom, 20)
    }
}

// MARK: - Common Section Components

private struct SettingsSection<Content: View>: View {
    let title: String
    private let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.9))

            SettingsCard {
                content
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: SettingsPanelLayout.cardCornerRadius, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: SettingsPanelLayout.cardCornerRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: $isOn)
                .font(.system(size: 13, weight: .medium))

            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, 22)
                .fixedSize(horizontal: false, vertical: true)
        }
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
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isHovered ? Color.accentColor.opacity(0.12) : Color.clear)
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
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)

            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary.opacity(0.88))

            Spacer()

            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 32, height: 20)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .onChange(of: color) { _ in
                    if settings.colorTheme != .custom {
                        settings.colorTheme = .custom
                    }
                }
        }
        .padding(.vertical, 1)
    }
}

// MARK: - Icon Style Card

private struct IconStyleCard: View {
    let style: IconStyle
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(nsImage: StatusImageRenderer.renderPreview(style: style))
                    .interpolation(.high)
                    .frame(width: 50, height: 50)

                Text(style.displayName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary.opacity(0.88))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 90)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.8) : Color.primary.opacity(0.10),
                        lineWidth: isSelected ? 1.4 : 1
                    )
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.12) : .clear, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}
