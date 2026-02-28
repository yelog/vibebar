import SwiftUI
import VibeBarCore

// MARK: - CLI Settings View

struct CLISettingsView: View {
    @ObservedObject private var manager = CLISettingsManager.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitorModel = MonitorViewModel.shared
    @ObservedObject private var wrapperCommandModel = WrapperCommandViewModel.shared
    @ObservedObject private var appSettings = AppSettings.shared

    @State private var selectedTool: ToolKind = .claudeCode

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar: Tool list
            toolList
                .frame(width: 190)

            Divider()

            // Right panel: Tool detail
            ScrollView(showsIndicators: false) {
                toolDetail(for: selectedTool)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
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

            // Reset button
            Button {
                manager.resetToDefaults()
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
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
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

        return VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text(tool.displayName)
                    .font(.system(size: 18, weight: .bold))

                Spacer()
            }

            liveStatusSection(for: tool)

            if config.isEnabled {
                // Detection Methods Section
                detectionMethodsSection(for: tool)

                // Plugin Management (if supported)
                if manager.hasPluginSupport(for: tool) {
                    pluginManagementSection(for: tool)
                }

                // Wrapper Command Section
                wrapperCommandSection(for: tool)
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
        }
    }

    private func liveStatusSection(for tool: ToolKind) -> some View {
        let summary = toolSummary(for: tool)

        return VStack(alignment: .leading, spacing: 10) {
            Text(l10n.string(.statsTitle))
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 8) {
                Circle()
                    .fill(overallStateColor(summary.overall))
                    .frame(width: 8, height: 8)

                Text(summary.overall.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(overallStateColor(summary.overall))

                Spacer()

                Text("\(summary.total)")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                statusMetric(state: .running, count: summary.counts[.running, default: 0])
                statusMetric(state: .awaitingInput, count: summary.counts[.awaitingInput, default: 0])
                statusMetric(state: .idle, count: summary.counts[.idle, default: 0])
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func statusMetric(state: ToolActivityState, count: Int) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(activityStateColor(state))
                .frame(width: 6, height: 6)

            Text("\(state.displayName) \(count)")
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

    // MARK: - Detection Methods Section

    private func detectionMethodsSection(for tool: ToolKind) -> some View {
        let availableMethods = manager.availableMethods(for: tool)
        let config = manager.configuration(for: tool)

        return VStack(alignment: .leading, spacing: 10) {
            Text(l10n.string(.cliDetectionMethods))
                .font(.system(size: 13, weight: .semibold))

            Text(l10n.string(.cliDetectionMethodsDesc))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            VStack(spacing: 6) {
                ForEach(availableMethods, id: \.self) { method in
                    DetectionMethodToggle(
                        method: method,
                        isEnabled: Binding(
                            get: { config.enabledDetectionMethods.contains(method) },
                            set: { manager.setDetectionMethod(tool, method: method, enabled: $0) }
                        )
                    )
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            if config.enabledDetectionMethods.isEmpty {
                Text(l10n.string(.cliNoDetectionMethods))
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Plugin Management Section

    private func pluginManagementSection(for tool: ToolKind) -> some View {
        let status = monitorModel.pluginStatus(for: tool)

        return VStack(alignment: .leading, spacing: 10) {
            Text(l10n.string(.cliPluginManagement))
                .font(.system(size: 13, weight: .semibold))

            pluginContent(for: tool, status: status)
        }
    }

    @ViewBuilder
    private func pluginContent(for tool: ToolKind, status: PluginInstallStatus) -> some View {
        switch status {
        case .checking:
            HStack {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text(l10n.string(.pluginChecking))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)

        case .cliNotFound:
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(l10n.string(.pluginCliNotFoundFmt, tool.executable))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)

        case .notInstalled:
            HStack {
                Text(l10n.string(.pluginNotInstalled))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    monitorModel.installPlugin(tool: tool)
                } label: {
                    Text(l10n.string(.pluginInstall))
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(10)

        case .installing:
            HStack {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text(l10n.string(.pluginInstalling))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)

        case .installed:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                if let version = monitorModel.bundledPluginVersion(for: tool) {
                    Text("v\(version) \(l10n.string(.pluginInstalled))")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                } else {
                    Text(l10n.string(.pluginInstalled))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    monitorModel.uninstallPlugin(tool: tool)
                } label: {
                    Text(l10n.string(.pluginUninstall))
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)

        case .updateAvailable(let installed, let bundled):
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
                Text("v\(installed)→v\(bundled)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                HStack(spacing: 8) {
                    Button {
                        monitorModel.updatePlugin(tool: tool)
                    } label: {
                        Text(l10n.string(.pluginUpdate))
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        monitorModel.uninstallPlugin(tool: tool)
                    } label: {
                        Text(l10n.string(.pluginUninstall))
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(10)

        case .updating:
            HStack {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text(l10n.string(.pluginUpdating))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)

        case .installFailed(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                }
                Button {
                    monitorModel.installPlugin(tool: tool)
                } label: {
                    Text(l10n.string(.pluginRetry))
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)

        case .uninstalling:
            HStack {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.7)
                Text(l10n.string(.pluginUninstalling))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)

        case .uninstallFailed(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                }
                Button {
                    monitorModel.uninstallPlugin(tool: tool)
                } label: {
                    Text(l10n.string(.pluginRetryUninstall))
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)

        case .updateFailed(let message):
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                        .lineLimit(2)
                    Spacer()
                }
                Button {
                    monitorModel.updatePlugin(tool: tool)
                } label: {
                    Text(l10n.string(.pluginRetry))
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(10)
        }
    }

    // MARK: - Wrapper Command Section

    private func wrapperCommandSection(for tool: ToolKind) -> some View {
        // Only show for Codex and Aider as they rely more on wrapper
        guard tool == .codex || tool == .aider || tool == .githubCopilot else {
            return AnyView(EmptyView())
        }

        return AnyView(VStack(alignment: .leading, spacing: 10) {
            Text(l10n.string(.cliWrapperCommand))
                .font(.system(size: 13, weight: .semibold))

            wrapperCommandContent
        })
    }

    @ViewBuilder
    private var wrapperCommandContent: some View {
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
            .padding(10)

        case .notInstalled:
            HStack {
                Text(l10n.string(.wrapperCommandNotInstalled))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
            .padding(10)

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
            .padding(10)

        case .installedExternal:
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
                Text(l10n.string(.wrapperCommandInstalledExternal))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(10)

        case .updateAvailable(_, let installedVersion, let bundledVersion):
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(.blue)
                Text("v\(installedVersion)→v\(bundledVersion)")
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
            .padding(10)

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
            .padding(10)

        case .installFailed(let message), .uninstallFailed(let message), .updateFailed(let message):
            VStack(alignment: .leading, spacing: 6) {
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
            .padding(10)
        }
    }
}

// MARK: - Detection Method Toggle

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
