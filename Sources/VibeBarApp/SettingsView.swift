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
    case cli
    case appearance
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
            (.cli, l10n.string(.tabCLI), "terminal.fill"),
            (.appearance, l10n.string(.tabAppearance), "paintpalette.fill"),
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
                case .cli:
                    CLISettingsView()
                case .appearance:
                    AppearanceSettingsView()
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
        .focusable(false)
        .keyboardShortcut(tabShortcut(for: tab.tab), modifiers: .command)
        .onHover { isHovering in
            hoveredTab = isHovering ? tab.tab : (hoveredTab == tab.tab ? nil : hoveredTab)
        }
    }

    private func tabShortcut(for tab: SettingsTab) -> KeyEquivalent {
        switch tab {
        case .general:
            return KeyEquivalent("1")
        case .cli:
            return KeyEquivalent("2")
        case .appearance:
            return KeyEquivalent("3")
        case .about:
            return KeyEquivalent("4")
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
    @ObservedObject private var monitorModel = MonitorViewModel.shared
    @ObservedObject private var wrapperCommandModel = WrapperCommandViewModel.shared

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

            SettingsSection(title: l10n.string(.systemTitle)) {
                VStack(alignment: .leading, spacing: 10) {
                    SettingsToggleRow(
                        title: l10n.string(.launchAtLogin),
                        description: l10n.string(.launchAtLoginDesc),
                        isOn: $settings.launchAtLogin
                    )
                }
            }

            notificationSettingsSection

            SettingsSection(title: l10n.string(.sessionTitle)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(l10n.string(.refresh))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button {
                            monitorModel.refreshNow()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }

                    Divider()

                    HStack {
                        Text(l10n.string(.openSessionsDir))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button {
                            monitorModel.openSessionsFolder()
                        } label: {
                            Image(systemName: "folder")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }

                    Divider()

                    HStack {
                        Text(l10n.string(.purgeStale))
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Button {
                            monitorModel.purgeStaleNow()
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.orange)
                    }
                }
            }

        }
        .padding(.horizontal, SettingsPanelLayout.horizontalPadding)
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var notificationSettingsSection: some View {
        let config = settings.notificationConfig

        SettingsSection(title: l10n.string(.notificationTitle)) {
            VStack(alignment: .leading, spacing: 12) {
                // Master toggle
                SettingsToggleRow(
                    title: l10n.string(.notificationEnable),
                    description: l10n.string(.notificationEnableDesc),
                    isOn: Binding(
                        get: { config.isEnabled },
                        set: { newValue in
                            var newConfig = config
                            newConfig.isEnabled = newValue
                            settings.notificationConfig = newConfig
                        }
                    )
                )

                if config.isEnabled {
                    Divider()
                        .padding(.vertical, 1)

                    // Transition toggles
                    Text(l10n.string(.notificationTransitions))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(l10n.string(.notifyTransitionRunningToIdle), isOn: Binding(
                            get: { config.enabledTransitions.contains(.runningToIdle) },
                            set: { isOn in
                                var newConfig = config
                                if isOn {
                                    if !newConfig.enabledTransitions.contains(.runningToIdle) {
                                        newConfig.enabledTransitions.append(.runningToIdle)
                                    }
                                } else {
                                    newConfig.enabledTransitions.removeAll { $0 == .runningToIdle }
                                }
                                settings.notificationConfig = newConfig
                            }
                        ))
                        .font(.system(size: 12))

                        Toggle(l10n.string(.notifyTransitionRunningToAwaiting), isOn: Binding(
                            get: { config.enabledTransitions.contains(.runningToAwaiting) },
                            set: { isOn in
                                var newConfig = config
                                if isOn {
                                    if !newConfig.enabledTransitions.contains(.runningToAwaiting) {
                                        newConfig.enabledTransitions.append(.runningToAwaiting)
                                    }
                                } else {
                                    newConfig.enabledTransitions.removeAll { $0 == .runningToAwaiting }
                                }
                                settings.notificationConfig = newConfig
                            }
                        ))
                        .font(.system(size: 12))
                    }
                    .padding(.leading, 22)

                    Divider()
                        .padding(.vertical, 1)

                    // Custom content editor
                    NotificationContentEditor(config: config)
                }
            }
        }
    }

// MARK: - Notification Content Editor

private struct NotificationContentEditor: View {
    let config: NotificationConfig
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var isExpanded = false

    // Default content values
    private var defaultTitle: String { "VibeBar" }
    private var defaultBody: String { "{tool} " + l10n.string(.notifyBodyTemplateSuffix) }

    var body: some View {
        VStack(spacing: 0) {
            // Header button - clickable entire row
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text(l10n.string(.notificationCustomContent))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    // Title field
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l10n.string(.notificationTitleLabel))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        TextField(
                            "",
                            text: Binding(
                                get: { config.customTitle ?? defaultTitle },
                                set: { newValue in
                                    var newConfig = config
                                    // Save as nil if equal to default
                                    newConfig.customTitle = newValue == defaultTitle ? nil : newValue
                                    settings.notificationConfig = newConfig
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12))
                    }

                    // Body field
                    VStack(alignment: .leading, spacing: 4) {
                        Text(l10n.string(.notificationBodyLabel))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        TextEditor(
                            text: Binding(
                                get: { config.customBody ?? defaultBody },
                                set: { newValue in
                                    var newConfig = config
                                    // Save as nil if equal to default
                                    newConfig.customBody = newValue == defaultBody ? nil : newValue
                                    settings.notificationConfig = newConfig
                                }
                            )
                        )
                        .font(.system(size: 12))
                        .frame(height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                        )
                    }

                    // Available variables hint
                    Text(l10n.string(.notificationVariablesHint))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.top, 8)
                .padding(.leading, 22)
            }
        }
    }
}

    @ViewBuilder
    private func pluginToolRow(tool: ToolKind, description: String, status: PluginInstallStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(tool.displayName + l10n.string(.pluginSuffix))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                pluginActionView(tool: tool, status: status)
            }

            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if let error = pluginError(for: status) {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var wrapperToolRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(l10n.string(.wrapperCommandDisplayName))
                    .font(.system(size: 13, weight: .semibold))
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

    @ViewBuilder
    private func pluginActionView(tool: ToolKind, status: PluginInstallStatus) -> some View {
        switch status {
        case .checking:
            statusText(l10n.string(.pluginChecking))
        case .cliNotFound:
            statusText(l10n.string(.pluginCliNotFoundFmt, tool.executable))
        case .notInstalled:
            actionTextButton(l10n.string(.pluginInstall), color: .blue) {
                monitorModel.installPlugin(tool: tool)
            }
        case .installing:
            statusText(l10n.string(.pluginInstalling))
        case .installed:
            HStack(spacing: 10) {
                if let version = monitorModel.bundledPluginVersion(for: tool) {
                    statusText("v\(version) \(l10n.string(.pluginInstalled))")
                } else {
                    statusText(l10n.string(.pluginInstalled))
                }
                actionTextButton(l10n.string(.pluginUninstall), color: .orange) {
                    monitorModel.uninstallPlugin(tool: tool)
                }
            }
        case .updateAvailable(let installed, let bundled):
            HStack(spacing: 8) {
                statusText("v\(installed)→v\(bundled)")
                actionTextButton(l10n.string(.pluginUpdate), color: .blue) {
                    monitorModel.updatePlugin(tool: tool)
                }
                actionTextButton(l10n.string(.pluginUninstall), color: .orange) {
                    monitorModel.uninstallPlugin(tool: tool)
                }
            }
        case .updating:
            statusText(l10n.string(.pluginUpdating))
        case .installFailed:
            actionTextButton(l10n.string(.pluginRetry), color: .blue) {
                monitorModel.installPlugin(tool: tool)
            }
        case .uninstalling:
            statusText(l10n.string(.pluginUninstalling))
        case .uninstallFailed:
            actionTextButton(l10n.string(.pluginRetryUninstall), color: .orange) {
                monitorModel.uninstallPlugin(tool: tool)
            }
        case .updateFailed:
            actionTextButton(l10n.string(.pluginRetry), color: .blue) {
                monitorModel.updatePlugin(tool: tool)
            }
        }
    }

    @ViewBuilder
    private var wrapperCommandActionView: some View {
        switch wrapperCommandModel.status {
        case .checking:
            statusText(l10n.string(.wrapperCommandChecking))
        case .notInstalled:
            actionTextButton(l10n.string(.pluginInstall), color: .blue) {
                wrapperCommandModel.installCommand()
            }
        case .installedManaged(_, let version):
            HStack(spacing: 10) {
                if let version {
                    statusText("v\(version) \(l10n.string(.wrapperCommandInstalled))")
                } else {
                    statusText(l10n.string(.wrapperCommandInstalled))
                }
                actionTextButton(l10n.string(.pluginUninstall), color: .orange) {
                    wrapperCommandModel.uninstallCommand()
                }
            }
        case .updateAvailable(_, let installedVersion, let bundledVersion):
            HStack(spacing: 8) {
                statusText("v\(installedVersion)→v\(bundledVersion)")
                actionTextButton(l10n.string(.pluginUpdate), color: .blue) {
                    wrapperCommandModel.updateCommand()
                }
                actionTextButton(l10n.string(.pluginUninstall), color: .orange) {
                    wrapperCommandModel.uninstallCommand()
                }
            }
        case .installedExternal:
            statusText(l10n.string(.wrapperCommandInstalledExternal))
        case .installing:
            statusText(l10n.string(.wrapperCommandInstalling))
        case .uninstalling:
            statusText(l10n.string(.wrapperCommandUninstalling))
        case .updating:
            statusText(l10n.string(.wrapperCommandUpdating))
        case .installFailed:
            actionTextButton(l10n.string(.wrapperCommandRetry), color: .blue) {
                wrapperCommandModel.installCommand()
            }
        case .uninstallFailed:
            actionTextButton(l10n.string(.wrapperCommandRetry), color: .orange) {
                wrapperCommandModel.uninstallCommand()
            }
        case .updateFailed:
            actionTextButton(l10n.string(.wrapperCommandRetry), color: .blue) {
                wrapperCommandModel.updateCommand()
            }
        }
    }

    private func pluginError(for status: PluginInstallStatus) -> String? {
        switch status {
        case .installFailed(let message), .uninstallFailed(let message), .updateFailed(let message):
            return message
        default:
            return nil
        }
    }

    private var wrapperCommandPath: String? {
        switch wrapperCommandModel.status {
        case .installedManaged(let path, _), .updateAvailable(let path, _, _), .installedExternal(let path):
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
        case .installFailed(let message), .uninstallFailed(let message), .updateFailed(let message):
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

// MARK: - Appearance Tab

struct AppearanceSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var l10n = L10n.shared
    private let iconColumns = Array(repeating: GridItem(.flexible(minimum: 72), spacing: 8), count: 4)

    var body: some View {
        VStack(alignment: .leading, spacing: SettingsPanelLayout.sectionSpacing) {
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
        }
        .padding(.horizontal, SettingsPanelLayout.horizontalPadding)
        .padding(.bottom, 20)
    }
}

// MARK: - About Tab

struct AboutSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var l10n = L10n.shared
    @State private var isCheckingUpdate = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                // MARK: Brand Header with Gradient
                brandHeader
                    .padding(.top, 8)

                // MARK: Connect Links
                connectSection
                    .padding(.top, 20)

                // MARK: Updates
                updateSection
                    .padding(.top, 20)
                    .padding(.bottom, 20)
            }
            .padding(.horizontal, SettingsPanelLayout.horizontalPadding)
        }
    }

    // MARK: - Brand Header


    private var brandHeader: some View {
        VStack(spacing: 10) {
            // App Icon - no shadow for cleaner macOS look
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 72, height: 72)
            }

            // App Name
            Text("VibeBar")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            // Tagline
            Text("AI Coding Agent Monitor for macOS")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            // Version & Author
            HStack(spacing: 6) {
                Text(l10n.string(.versionFmt, BuildInfo.version))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("·")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary.opacity(0.6))

                Text("Built with ❤️ by Yelog")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Connect Section

    private var connectSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: l10n.string(.connectTitle))

            VStack(spacing: 0) {
                SocialLinkRow(
                    icon: "curlybraces",
                    title: "GitHub",
                    urlString: "https://github.com/yelog/VibeBar"
                )

                Divider()
                    .padding(.horizontal, 12)

                SocialLinkRow(
                    icon: "x.circle.fill",
                    title: "Twitter",
                    urlString: "https://x.com/yelogeek"
                )

                Divider()
                    .padding(.horizontal, 12)

                SocialLinkRow(
                    icon: "envelope.fill",
                    title: "Email",
                    urlString: "mailto:yelogeek@gmail.com"
                )
            }
            .background(
                RoundedRectangle(cornerRadius: SettingsPanelLayout.cardCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsPanelLayout.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }

    // MARK: - Update Section

    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: l10n.string(.updateTitle))

            VStack(alignment: .leading, spacing: 14) {
                // Auto-check toggle
                Toggle(l10n.string(.autoCheckUpdates), isOn: $settings.autoCheckUpdates)
                    .font(.system(size: 13, weight: .medium))

                Text(l10n.string(.autoCheckUpdatesDesc))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
.fixedSize(horizontal: false, vertical: true)

                // Update channel picker
                Picker(l10n.string(.updateChannelTitle), selection: $settings.updateChannel) {
                    ForEach(UpdateChannel.allCases) { channel in
                        Text(channel.displayName).tag(channel)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
                .padding(.leading, 22)

                Text(l10n.string(.updateChannelDesc))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
                    .fixedSize(horizontal: false, vertical: true)


                // Current version status
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                    Text(l10n.string(.versionFmt, BuildInfo.version) + " " + l10n.string(.alreadyLatest))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.leading, 22)

                // Check updates button - accent style
                Button {
                    isCheckingUpdate = true
                    UpdateChecker.shared.checkForUpdates(silent: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCheckingUpdate = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isCheckingUpdate {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text(l10n.string(.checkUpdatesBtn))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isCheckingUpdate ? Color.accentColor.opacity(0.6) : Color.accentColor)
                )
                .disabled(isCheckingUpdate)
                .padding(.leading, 22)
            }
.padding(12)
.background(
                RoundedRectangle(cornerRadius: SettingsPanelLayout.cardCornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SettingsPanelLayout.cardCornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

// MARK: - Section Title

private struct SectionTitle: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary.opacity(0.8))
            .tracking(0.5)
    }
}

// MARK: - Social Link Row

private struct SocialLinkRow: View {
    let icon: String
    let title: String
    let urlString: String
    @State private var isHovered = false

    var body: some View {
        Button {
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                // Left icon - unified 16pt size
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isHovered ? Color.accentColor : .secondary)
                    .frame(width: 24, alignment: .leading)
                    .scaleEffect(isHovered ? 1.05 : 1.0)

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)

                Spacer()

                // Right chevron for native mac feel
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.6))
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? Color.accentColor.opacity(0.06) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
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
