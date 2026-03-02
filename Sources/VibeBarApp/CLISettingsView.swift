import SwiftUI
import VibeBarCore

// MARK: - CLI Settings View

struct CLISettingsView: View {
    @ObservedObject private var manager = CLISettingsManager.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitorModel = MonitorViewModel.shared
    @ObservedObject private var wrapperCommandModel = WrapperCommandViewModel.shared
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var selectedTool: ToolKind? = .claudeCode
    @State private var showResetConfirmation = false

    /// Whether wrapper is selected (mutually exclusive with tool selection)
    private var isWrapperSelected: Bool {
        selectedTool == nil
    }

    /// Load tool icon from bundle resources
    private func toolIcon(for tool: ToolKind) -> NSImage? {
        // Try multiple strategies to find the resource bundle
        let bundle = toolIconBundle()
        guard let path = bundle?.path(forResource: tool.iconResourceName, ofType: "png") else {
            return nil
        }
        return NSImage(contentsOfFile: path)
    }

    /// Find the resource bundle containing tool icons
    private func toolIconBundle() -> Bundle? {
        // Strategy 1: Try Bundle.module (SPM generated - for development)
        if let path = Bundle.module.path(forResource: "claudeCode", ofType: "png"),
           FileManager.default.fileExists(atPath: path) {
            return Bundle.module
        }

        // Strategy 2: Try main bundle resources (for development builds)
        if let path = Bundle.main.path(forResource: "claudeCode", ofType: "png"),
           FileManager.default.fileExists(atPath: path) {
            return Bundle.main
        }

        // Strategy 3: Look for VibeBar_VibeBarApp.bundle in released app
        // In released app: VibeBar.app/Contents/Resources/VibeBar_VibeBarApp.bundle
        let releaseBundleURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Resources")
            .appendingPathComponent("VibeBar_VibeBarApp.bundle")

        if FileManager.default.fileExists(atPath: releaseBundleURL.path),
           let bundle = Bundle(url: releaseBundleURL),
           let path = bundle.path(forResource: "claudeCode", ofType: "png"),
           FileManager.default.fileExists(atPath: path) {
            return bundle
        }

        // Strategy 4: Look for bundle next to executable (alternate location)
        let executableBundleURL = Bundle.main.bundleURL
            .appendingPathComponent("VibeBar_VibeBarApp.bundle")

        if FileManager.default.fileExists(atPath: executableBundleURL.path),
           let bundle = Bundle(url: executableBundleURL),
           let path = bundle.path(forResource: "claudeCode", ofType: "png"),
           FileManager.default.fileExists(atPath: path) {
            return bundle
        }

        // Strategy 5: Development paths (only for local development)
        #if DEBUG
        let devPaths = [
            URL(fileURLWithPath: "/Users/yelog/workspace/swift/VibeBar/.build/debug/VibeBar_VibeBarApp.bundle"),
            URL(fileURLWithPath: "/Users/yelog/workspace/swift/VibeBar/.build/arm64-apple-macosx/debug/VibeBar_VibeBarApp.bundle"),
        ]

        for url in devPaths {
            if FileManager.default.fileExists(atPath: url.path),
               let bundle = Bundle(url: url),
               let path = bundle.path(forResource: "claudeCode", ofType: "png"),
               FileManager.default.fileExists(atPath: path) {
                return bundle
            }
        }
        #endif

        return nil
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar: Tool list
            toolList
                .frame(width: 190)

            Divider()

            // Right panel: Tool detail or Wrapper detail
            ScrollView(showsIndicators: true) {
                if let tool = selectedTool {
                    toolDetail(for: tool)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                } else {
                    wrapperDetail
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .onAppear {
            monitorModel.checkPluginStatusIfNeeded()
            monitorModel.refreshToolInstallStatusIfNeeded()
            wrapperCommandModel.refreshIfNeeded()
        }
    }

    // MARK: - Tool List

    private var toolList: some View {
        VStack(spacing: 0) {
            // Header
            Text(l10n.string(.cliSettingsTitle))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 12)

            // Tool buttons
            ForEach(ToolKind.allCases, id: \.self) { tool in
                toolButton(for: tool)
            }

            Spacer()

            // Wrapper button (global, not per-tool)
            wrapperButton

            Divider()
                .padding(.vertical, 8)

            // Reset button
            Button {
                showResetConfirmation = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 10))
                    Text(l10n.string(.cliResetToDefaults))
                        .font(.system(size: 11))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.bottom, 16)
            .confirmationDialog(
                "确认重置",
                isPresented: $showResetConfirmation,
                titleVisibility: .visible
            ) {
                Button("重置为默认设置", role: .destructive) {
                    manager.resetToDefaults()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("这将重置所有 CLI 工具的设置为默认值，包括启用状态和检测方法。")
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
    }

    // MARK: - Wrapper Button

    private var wrapperButton: some View {
        let isSelected = isWrapperSelected

        return Button {
            selectedTool = nil
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 20, height: 20)

                Text("Wrapper")
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()

                // Version status
                wrapperVersionBadge
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .background(
            Rectangle()
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }

    @ViewBuilder
    private var wrapperVersionBadge: some View {
        switch wrapperCommandModel.status {
        case .checking:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.6)
        case .notInstalled:
            Text(l10n.string(.wrapperCommandNotInstalled))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        case .installedManaged(_, let version):
            if let version {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.green)
                    Text("v\(version)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)
            }
        case .installedExternal:
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                Text(l10n.string(.wrapperCommandInstalledExternal))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        case .updateAvailable(_, let installedVersion, _):
            HStack(spacing: 3) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                Text("v\(installedVersion)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        case .installing, .uninstalling, .updating:
            ProgressView()
                .controlSize(.mini)
                .scaleEffect(0.6)
        case .installFailed, .uninstallFailed, .updateFailed:
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Wrapper Detail View

    private var wrapperDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)

                Text("Wrapper 命令")
                    .font(.system(size: 18, weight: .bold))

                Spacer()
            }
            .padding(.bottom, 12)

            Divider()
                .padding(.bottom, 16)

            // Description
            VStack(alignment: .leading, spacing: 12) {
                Text("Wrapper 通过 PTY 包装启动 CLI 工具，可以：")
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                        Text("实时检测工具状态（运行中 / 等待输入 / 空闲）")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                        Text("无需安装插件，开箱即用")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.green)
                        Text("支持所有 6 种 Agent 工具")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, 20)

            // Supported tools
            VStack(alignment: .leading, spacing: 8) {
                Text("支持的工具")
                    .font(.system(size: 13, weight: .semibold))

                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(ToolKind.allCases, id: \.self) { tool in
                        HStack(spacing: 3) {
                            Group {
                                if let icon = toolIcon(for: tool) {
                                    Image(nsImage: icon)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                } else {
                                    Image(systemName: tool.iconName)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 14, height: 14)

                            Text(tool.displayName)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 6)
                        .padding(.trailing, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                        .fixedSize()
                    }
                }
            }
            .padding(.bottom, 20)

            // Usage
            VStack(alignment: .leading, spacing: 8) {
                Text("使用方法")
                    .font(.system(size: 13, weight: .semibold))

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(ToolKind.allCases, id: \.self) { tool in
                        HStack(spacing: 8) {
                            Text("vibebar \(tool.executable)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)

                            Text("# \(tool.displayName)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .padding(.bottom, 20)

            // Install/Status section
            VStack(alignment: .leading, spacing: 10) {
                Text("安装状态")
                    .font(.system(size: 13, weight: .semibold))

                wrapperStatusCard
            }

            Spacer()
        }
    }

    @ViewBuilder
    private var wrapperStatusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch wrapperCommandModel.status {
            case .checking:
                HStack {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Text(l10n.string(.wrapperCommandChecking))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)

            case .notInstalled:
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.string(.wrapperCommandNotInstalled))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    HStack {
                        Spacer()
                        Button {
                            wrapperCommandModel.installCommand()
                        } label: {
                            Text(l10n.string(.pluginInstall))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(12)

            case .installedManaged(_, let version):
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    if let version {
                        Text("v\(version) \(l10n.string(.wrapperCommandInstalled))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(l10n.string(.wrapperCommandInstalled))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        wrapperCommandModel.uninstallCommand()
                    } label: {
                        Text(l10n.string(.pluginUninstall))
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(12)

            case .installedExternal:
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.blue)
                    Text(l10n.string(.wrapperCommandInstalledExternal))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)

            case .updateAvailable(_, let installedVersion, let bundledVersion):
                HStack {
                    Image(systemName: "arrow.up.circle.fill")
                        .foregroundStyle(.blue)
                    Text("v\(installedVersion) → v\(bundledVersion)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 8) {
                        Button {
                            wrapperCommandModel.updateCommand()
                        } label: {
                            Text(l10n.string(.pluginUpdate))
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button {
                            wrapperCommandModel.uninstallCommand()
                        } label: {
                            Text(l10n.string(.pluginUninstall))
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(12)

            case .installing, .uninstalling, .updating:
                HStack {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                    Group {
                        if case .installing = wrapperCommandModel.status {
                            Text(l10n.string(.wrapperCommandInstalling))
                        } else if case .uninstalling = wrapperCommandModel.status {
                            Text(l10n.string(.wrapperCommandUninstalling))
                        } else {
                            Text(l10n.string(.wrapperCommandUpdating))
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(12)

            case .installFailed(let message), .uninstallFailed(let message), .updateFailed(let message):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.red)
                            .lineLimit(2)
                        Spacer()
                    }
                    HStack {
                        Spacer()
                        Button {
                            wrapperCommandModel.installCommand()
                        } label: {
                            Text(l10n.string(.pluginRetry))
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(12)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func toolButton(for tool: ToolKind) -> some View {
        let isSelected = selectedTool == tool
        let config = manager.configuration(for: tool)
        let installStatus = monitorModel.toolInstallStatus(for: tool)

        return HStack(spacing: 8) {
            Button {
                selectedTool = tool
            } label: {
                HStack(spacing: 8) {
                    // Tool icon
                    if let icon = toolIcon(for: tool) {
                        Image(nsImage: icon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: tool.iconName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                            .frame(width: 20, height: 20)
                    }

                    // Status indicator (dynamic)
                    Image(nsImage: toolStatusImage(for: tool))
                        .interpolation(.high)
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.displayName)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .lineLimit(1)

                        Text(installStatusText(installStatus))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .opacity(config.isEnabled ? 1 : 0.75)
            }
            .buttonStyle(.plain)

            Toggle("", isOn: Binding(
                get: { config.isEnabled },
                set: { manager.setEnabled(tool, enabled: $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help(l10n.string(.cliEnabled))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            Rectangle()
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }

    // MARK: - Tool Detail

    private func toolDetail(for tool: ToolKind) -> some View {
        let config = manager.configuration(for: tool)

        return VStack(alignment: .leading, spacing: 0) {
            // Header with icon
            HStack(spacing: 10) {
                // Tool icon
                if let icon = toolIcon(for: tool) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: tool.iconName)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }

                Text(tool.displayName)
                    .font(.system(size: 18, weight: .bold))

                Spacer()
            }
            .padding(.bottom, 12)

            // Divider under title
            Divider()
                .padding(.bottom, 16)

            if config.isEnabled {
                // Real-time status section (compact)
                liveStatusSectionCompact(for: tool)
                    .padding(.bottom, 20)

                // Detection Methods Section with integrated plugin
                detectionMethodsSectionWithPlugin(for: tool)
            } else {
                // Disabled state
                Text("此 CLI 检测已禁用")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.08))
                    )
            }

            Spacer()
        }
    }

    // MARK: - Compact Live Status Section

    private func liveStatusSectionCompact(for tool: ToolKind) -> some View {
        let summary = toolSummary(for: tool)

        return VStack(alignment: .leading, spacing: 10) {
            Text(l10n.string(.statsTitle))
                .font(.system(size: 13, weight: .semibold))

            // Status counts in horizontal layout
            HStack(spacing: 16) {
                statusCountCompact(
                    label: ToolActivityState.idle.displayName,
                    count: summary.counts[.idle, default: 0],
                    color: activityStateColor(.idle)
                )

                statusCountCompact(
                    label: ToolActivityState.running.displayName,
                    count: summary.counts[.running, default: 0],
                    color: activityStateColor(.running)
                )

                statusCountCompact(
                    label: ToolActivityState.awaitingInput.displayName,
                    count: summary.counts[.awaitingInput, default: 0],
                    color: activityStateColor(.awaitingInput)
                )
            }
        }
    }

    private func statusCountCompact(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text("\(label) \(count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func toolSummary(for tool: ToolKind) -> ToolSummary {
        monitorModel.summary.byTool[tool] ?? ToolSummary(
            tool: tool,
            total: 0,
            counts: [:],
            overall: .stopped
        )
    }

    private func toolStatusImage(for tool: ToolKind) -> NSImage {
        let summary = toolSummary(for: tool)
        let iconSummary = GlobalSummary(
            total: summary.total,
            counts: summary.counts,
            byTool: [tool: summary],
            updatedAt: monitorModel.summary.updatedAt
        )
        return StatusImageRenderer.renderSidebar(summary: iconSummary, style: appSettings.iconStyle)
    }

    private func installStatusText(_ status: ToolInstallStatus) -> String {
        switch status {
        case .checking:
            return l10n.string(.pluginChecking)
        case .notInstalled:
            return l10n.string(.pluginNotInstalled)
        case .installed(let version):
            if let version {
                return "v\(version)"
            }
            return l10n.string(.pluginInstalled)
        }
    }

    private func overallStateColor(_ state: ToolOverallState) -> Color {
        switch state {
        case .running:
            return .green
        case .awaitingInput:
            return .orange
        case .idle:
            return .blue
        case .stopped, .unknown:
            return .secondary
        }
    }

    private func activityStateColor(_ state: ToolActivityState) -> Color {
        switch state {
        case .running:
            return .green
        case .awaitingInput:
            return .orange
        case .idle:
            return .blue
        case .unknown:
            return .secondary
        }
    }

    // MARK: - Detection Methods Section with Integrated Plugin

    private func detectionMethodsSectionWithPlugin(for tool: ToolKind) -> some View {
        let availableMethods = manager.availableMethods(for: tool)
        let config = manager.configuration(for: tool)

        return DetectionMethodsSectionContent(
            tool: tool,
            availableMethods: availableMethods,
            enabledMethods: config.enabledDetectionMethods,
            hasNoMethodsWarning: config.enabledDetectionMethods.isEmpty,
            onMethodToggle: { method, enabled in
                manager.setDetectionMethod(tool, method: method, enabled: enabled)
            }
        )
    }

    // MARK: - Wrapper Command Section

    }

// MARK: - Detection Methods Section Content

private struct DetectionMethodsSectionContent: View {
    let tool: ToolKind
    let availableMethods: [DetectionMethodPreference]
    let enabledMethods: [DetectionMethodPreference]
    let hasNoMethodsWarning: Bool
    let onMethodToggle: (DetectionMethodPreference, Bool) -> Void

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitorModel = MonitorViewModel.shared

    var body: some View {
        let pluginStatus = monitorModel.pluginStatus(for: tool)

        return VStack(alignment: .leading, spacing: 12) {
            // Section header with divider style
            sectionHeader

            // Detection methods list
            methodsList(pluginStatus: pluginStatus)

            // Warning if no methods enabled
            if hasNoMethodsWarning {
                noMethodsWarning
            }
        }
    }

    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Text(l10n.string(.cliDetectionMethods))
                .font(.system(size: 13, weight: .semibold))

            Divider()
                .frame(height: 12)

            Text("\(availableMethods.count) 种检测方式")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    private func methodsList(pluginStatus: PluginInstallStatus) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(availableMethods.enumerated()), id: \.element) { index, method in
                DetectionMethodRow(
                    tool: tool,
                    method: method,
                    isEnabled: Binding(
                        get: { enabledMethods.contains(method) },
                        set: { onMethodToggle(method, $0) }
                    ),
                    pluginStatus: pluginStatus,
                    isLast: index == availableMethods.count - 1
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private var noMethodsWarning: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text(l10n.string(.cliNoDetectionMethods))
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Spacer()
        }
        .padding(.top, 4)
    }
}

// MARK: - Detection Method Row (with integrated plugin)

private struct DetectionMethodRow: View {
    let tool: ToolKind
    let method: DetectionMethodPreference
    @Binding var isEnabled: Bool
    let pluginStatus: PluginInstallStatus?
    let isLast: Bool

    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitorModel = MonitorViewModel.shared

    var body: some View {
        VStack(spacing: 0) {
            // Main row with checkbox
            Button {
                isEnabled.toggle()
            } label: {
                HStack(spacing: 10) {
                    // Custom checkbox
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(isEnabled ? Color.accentColor : Color.primary.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 16, height: 16)

                        if isEnabled {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    .frame(width: 16, height: 16)

                    // Priority badge
                    Text("P\(method.priority)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(width: 20, height: 14)
                        .background(
                            Capsule()
                                .fill(priorityColor)
                        )

                    // Method name
                    Text(method.displayName)
                        .font(.system(size: 12))
                        .foregroundStyle(isEnabled ? .primary : .secondary)

                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .background(isEnabled ? Color.accentColor.opacity(0.04) : Color.clear)

            // Description and plugin info (when enabled)
            if isEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    // Method description
                    Text(methodDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    // HTTP API hint for OpenCode
                    if tool == .opencode && method == .httpAPI {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.yellow)
                            Text("需以服务器模式启动：")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text("opencode --port 4096")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                        }
                    }

                    // Plugin status integration (only for plugin-based methods)
                    if isPluginMethod, let status = pluginStatus {
                        pluginStatusContent(status: status)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .padding(.top, -4)
            }

            // Divider (except for last item)
            if !isLast {
                Divider()
                    .padding(.leading, 12)
            }
        }
    }

    @ViewBuilder
    private func pluginStatusContent(status: PluginInstallStatus) -> some View {
        HStack(spacing: 8) {
            switch status {
            case .checking:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                Text(l10n.string(.pluginChecking))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

            case .cliNotFound:
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                Text(l10n.string(.pluginCliNotFoundFmt, tool.executable))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

            case .notInstalled:
                Text(l10n.string(.pluginNotInstalled))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    monitorModel.installPlugin(tool: tool)
                } label: {
                    Text(l10n.string(.pluginInstall))
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)

            case .installing:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                Text(l10n.string(.pluginInstalling))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

            case .installed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.green)

                if let version = monitorModel.bundledPluginVersion(for: tool) {
                    Text("Plugin v\(version) \(l10n.string(.pluginInstalled))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Text(l10n.string(.pluginInstalled))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    monitorModel.uninstallPlugin(tool: tool)
                } label: {
                    Text(l10n.string(.pluginUninstall))
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)

            case .updateAvailable(let installed, let bundled):
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.blue)
                Text("v\(installed) → v\(bundled)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        monitorModel.updatePlugin(tool: tool)
                    } label: {
                        Text(l10n.string(.pluginUpdate))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)

                    Button {
                        monitorModel.uninstallPlugin(tool: tool)
                    } label: {
                        Text(l10n.string(.pluginUninstall))
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                }

            case .updating:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                Text(l10n.string(.pluginUpdating))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

            case .installFailed(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)

                Spacer()

                Button {
                    monitorModel.installPlugin(tool: tool)
                } label: {
                    Text(l10n.string(.pluginRetry))
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)

            case .uninstalling:
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
                Text(l10n.string(.pluginUninstalling))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

            case .uninstallFailed(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)

                Spacer()

                Button {
                    monitorModel.uninstallPlugin(tool: tool)
                } label: {
                    Text(l10n.string(.pluginRetryUninstall))
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)

            case .updateFailed(let message):
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                Text(message)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
                    .lineLimit(1)

                Spacer()

                Button {
                    monitorModel.updatePlugin(tool: tool)
                } label: {
                    Text(l10n.string(.pluginRetry))
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .controlSize(.mini)
            }
        }
        .padding(.leading, 38) // Align with checkbox + badge + spacing
    }

    private var methodDescription: String {
        switch (tool, method) {
        case (.claudeCode, .plugin):
            return "插件检测 - 实时推送，最高精度"
        case (.opencode, .plugin):
            return "插件检测 - 实时推送，最高精度"
        case (.opencode, .httpAPI):
            return "HTTP API 检测 - 无需插件"
        case (.githubCopilot, .plugin):
            return "Hook 检测 - 实时推送"
        default:
            break
        }
        switch method {
        case .processScan:
            return "进程扫描检测 - 兼容模式"
        case .httpAPI:
            return "HTTP API 检测"
        case .jsonRPC:
            return "JSON-RPC 检测"
        case .hookFile:
            return "Hook 文件检测"
        case .transcriptFile:
            return "转录文件检测"
        case .plugin:
            return "插件检测 - 实时推送"
        case .logFile:
            return "日志文件检测"
        }
    }

    /// Determines if this detection method uses plugin for the given tool
    private var isPluginMethod: Bool {
        guard CLIToolConfiguration.hasPluginSupport(for: tool) else { return false }
        return method == .plugin
    }

    private var priorityColor: Color {
        switch method.priority {
        case 6: return .mint
        case 5: return .green
        case 4: return .blue
        case 3: return .purple
        case 2: return .orange
        default: return .gray
        }
    }
}

// MARK: - Legacy Detection Method Toggle (deprecated, kept for compatibility)

private struct DetectionMethodToggle: View {
    let method: DetectionMethodPreference
    @Binding var isEnabled: Bool
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Button {
            isEnabled.toggle()
        } label: {
            HStack(spacing: 10) {
                // Custom checkbox with fixed position
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.primary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 16, height: 16)

                    if isEnabled {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                .frame(width: 16, height: 16)

                // Priority badge with fixed width for alignment
                Text("P\(method.priority)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 14)
                    .background(
                        Capsule()
                            .fill(priorityColor)
                    )

                Text(method.displayName)
                    .font(.system(size: 12))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var priorityColor: Color {
        switch method.priority {
        case 6: return .mint
        case 5: return .green
        case 4: return .blue
        case 3: return .purple
        case 2: return .orange
        default: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    CLISettingsView()
        .frame(width: 600, height: 500)
}

// MARK: - Flow Layout (wrapping horizontal layout)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                // Move to next line
                currentX = 0
                currentY += lineHeight + lineSpacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            currentX += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}
