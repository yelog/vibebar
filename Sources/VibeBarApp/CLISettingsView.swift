import SwiftUI
import VibeBarCore

// MARK: - CLI Settings View

struct CLISettingsView: View {
    @ObservedObject private var manager = CLISettingsManager.shared
    @ObservedObject private var l10n = L10n.shared
    @ObservedObject private var monitorModel = MonitorViewModel.shared
    @ObservedObject private var wrapperCommandModel = WrapperCommandViewModel.shared

    @State private var selectedTool: ToolKind = .claudeCode

    var body: some View {
        HStack(spacing: 0) {
            // Left sidebar: Tool list
            toolList
                .frame(width: 140)

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

        return Button {
            selectedTool = tool
        } label: {
            HStack(spacing: 8) {
                // Status indicator
                Circle()
                    .fill(config.isEnabled ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 6, height: 6)

                Text(tool.displayName)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                Rectangle()
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Tool Detail

    private func toolDetail(for tool: ToolKind) -> some View {
        let config = manager.configuration(for: tool)

        return VStack(alignment: .leading, spacing: 20) {
            // Header with enable toggle
            HStack {
                Text(tool.displayName)
                    .font(.system(size: 18, weight: .bold))

                Spacer()

                Toggle(l10n.string(.cliEnabled), isOn: Binding(
                    get: { config.isEnabled },
                    set: { manager.setEnabled(tool, enabled: $0) }
                ))
                .font(.system(size: 13, weight: .medium))
            }

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
