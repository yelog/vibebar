import SwiftUI
import VibeBarCore

struct HookEditView: View {
    let hook: HookConfig?
    let onSave: (HookConfig) -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var l10n = L10n.shared

    @State private var name: String = ""
    @State private var isEnabled: Bool = true
    @State private var selectedTriggers: Set<HookTrigger> = []
    @State private var selectedTools: Set<ToolKind> = []
    @State private var applyToAllTools: Bool = true
    @State private var actionType: HookActionType = .shell
    @State private var shellCommand: String = ""
    @State private var webhookURL: String = ""
    @State private var webhookMethod: String = "POST"
    @State private var webhookHeadersText: String = ""
    @State private var timeout: Double = 30

    @State private var showingValidationError = false
    @State private var validationMessage = ""
    @State private var selectedExampleTrigger: HookTrigger = .sessionStarted

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                Divider()

                basicInfoSection

                Divider()

                triggersSection

                Divider()

                toolsSection

                Divider()

                actionSection

                Divider()

                examplesSection

                if showingValidationError {
                    validationErrorView
                }

                Divider()

                buttonSection
            }
            .padding(24)
        }
        .frame(width: 600, height: 750)
        .onAppear {
            loadExistingHook()
        }
    }

    private var headerSection: some View {
        Text(hook == nil ? l10n.string(.hooksAddHook) : l10n.string(.hooksEditHook))
            .font(.system(size: 18, weight: .semibold))
    }

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.string(.hooksName))
                .font(.system(size: 13, weight: .medium))

            TextField(l10n.string(.hooksNamePlaceholder), text: $name)
                .textFieldStyle(.roundedBorder)

            Toggle(l10n.string(.hooksEnabled), isOn: $isEnabled)
                .toggleStyle(.checkbox)
        }
    }

    private var triggersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.string(.hooksTriggers))
                .font(.system(size: 13, weight: .medium))

            Text(l10n.string(.hooksTriggersDesc))
                .font(.caption)
                .foregroundColor(.secondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(HookTrigger.allCases, id: \.self) { trigger in
                    Toggle(trigger.displayName, isOn: Binding(
                        get: { selectedTriggers.contains(trigger) },
                        set: { isSelected in
                            if isSelected {
                                selectedTriggers.insert(trigger)
                            } else {
                                selectedTriggers.remove(trigger)
                            }
                        }
                    ))
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(l10n.string(.hooksToolsAll), isOn: $applyToAllTools)
                .toggleStyle(.checkbox)

            if !applyToAllTools {
                Text(l10n.string(.hooksTools))
                    .font(.system(size: 13, weight: .medium))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(ToolKind.allCases, id: \.self) { tool in
                        Toggle(tool.displayName, isOn: Binding(
                            get: { selectedTools.contains(tool) },
                            set: { isSelected in
                                if isSelected {
                                    selectedTools.insert(tool)
                                } else {
                                    selectedTools.remove(tool)
                                }
                            }
                        ))
                        .toggleStyle(.checkbox)
                    }
                }
            }
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(l10n.string(.hooksActionType))
                .font(.system(size: 13, weight: .medium))

            Picker("", selection: $actionType) {
                ForEach(HookActionType.allCases, id: \.self) { type in
                    Text(type.displayName).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if actionType == .shell {
                shellCommandSection
            } else {
                webhookSection
            }

            HStack {
                Text(l10n.string(.hooksTimeout))
                Slider(value: $timeout, in: 5...120, step: 5)
                Text("\(Int(timeout))s")
                    .frame(width: 40)
            }
        }
    }

    private var shellCommandSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.string(.hooksShellCommand))
                .font(.system(size: 13, weight: .medium))

            TextEditor(text: $shellCommand)
                .font(.system(.body, design: .monospaced))
                .frame(height: 80)
                .border(Color.secondary.opacity(0.3))

            Text(l10n.string(.hooksShellCommandPlaceholder))
                .font(.caption)
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text("环境变量:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("VIBEBAR_TRIGGER, VIBEBAR_TOOL, VIBEBAR_STATUS, VIBEBAR_PID, VIBEBAR_CWD, VIBEBAR_SESSION_ID, VIBEBAR_EVENT_TIME")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }

    private var webhookSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(l10n.string(.hooksWebhookURL))
                .font(.system(size: 13, weight: .medium))

            TextField(l10n.string(.hooksWebhookURLPlaceholder), text: $webhookURL)
                .textFieldStyle(.roundedBorder)

            HStack {
                Text(l10n.string(.hooksWebhookMethod))
                Picker("", selection: $webhookMethod) {
                    Text("POST").tag("POST")
                    Text("GET").tag("GET")
                    Text("PUT").tag("PUT")
                    Text("PATCH").tag("PATCH")
                }
                .frame(width: 100)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(l10n.string(.hooksWebhookHeaders) + " (JSON)")
                    .font(.system(size: 13, weight: .medium))

                TextEditor(text: $webhookHeadersText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 60)
                    .border(Color.secondary.opacity(0.3))

                Text("示例: {\"Authorization\": \"Bearer xxx\", \"X-Custom\": \"value\"}")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("调用示例")
                .font(.system(size: 13, weight: .medium))

            Text("点击左侧触发器查看对应的调用示例")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(HookTrigger.allCases, id: \.self) { trigger in
                        Button {
                            selectedExampleTrigger = trigger
                        } label: {
                            HStack {
                                Text(trigger.displayName)
                                    .font(.system(size: 12))
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(selectedExampleTrigger == trigger ? Color.accentColor.opacity(0.15) : Color.clear)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 120)
                .padding(4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    exampleShellSection
                    Divider()
                    exampleWebhookSection
                }
                .frame(maxWidth: .infinity)
                .padding(12)
            }
            .frame(height: 280)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
    }

    private var exampleShellSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "terminal")
                    .font(.system(size: 11))
                Text("Shell 环境变量")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.secondary)

            ScrollView {
                Text(shellExampleText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 90)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
        }
    }

    private var exampleWebhookSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "network")
                    .font(.system(size: 11))
                Text("Webhook JSON Payload")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.secondary)

            ScrollView {
                Text(webhookExampleText)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(height: 90)
            .background(Color(NSColor.textBackgroundColor))
            .cornerRadius(4)
        }
    }

    private var shellExampleText: String {
        let trigger = selectedExampleTrigger
        return """
        # 触发器: \(trigger.displayName)
        VIBEBAR_TRIGGER=\(trigger.rawValue)
        VIBEBAR_SESSION_ID=abc123-def456
        VIBEBAR_TOOL=claude-code
        VIBEBAR_TOOL_DISPLAY="Claude Code"
        VIBEBAR_STATUS=\(statusForTrigger(trigger))
        VIBEBAR_PID=12345
        VIBEBAR_CWD=/Users/dev/project
        VIBEBAR_EVENT_TIME=2024-01-15T10:30:00.000Z
        """
    }

    private var webhookExampleText: String {
        let trigger = selectedExampleTrigger
        return """
        {
          "trigger": "\(trigger.rawValue)",
          "timestamp": "2024-01-15T10:30:00.000Z",
          "session": {
            "id": "abc123-def456",
            "tool": "claude-code",
            "tool_display": "Claude Code",
            "pid": 12345,
            "status": "\(statusForTrigger(trigger))",
            "cwd": "/Users/dev/project",
            "started_at": "2024-01-15T10:00:00.000Z"
          }
        }
        """
    }

    private func statusForTrigger(_ trigger: HookTrigger) -> String {
        switch trigger {
        case .sessionStarted: return "running"
        case .sessionEnded: return "stopped"
        case .stateChanged: return "running"
        case .runningToIdle: return "idle"
        case .runningToAwaiting: return "awaiting_input"
        case .idleToRunning: return "running"
        }
    }

    private var validationErrorView: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(validationMessage)
                .font(.caption)
                .foregroundColor(.orange)
        }
        .padding(8)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(6)
    }

    private var buttonSection: some View {
        HStack {
            Button(l10n.string(.closeWindow)) {
                dismiss()
            }
            .keyboardShortcut(.escape, modifiers: [])

            Spacer()

            Button(hook == nil ? l10n.string(.hooksAddHook) : l10n.string(.hooksEditHook)) {
                saveHook()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])
            .disabled(!isValid)
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !selectedTriggers.isEmpty &&
        (actionType != .shell || !shellCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (actionType != .webhook || URL(string: webhookURL) != nil)
    }

    private func loadExistingHook() {
        guard let hook else { return }

        name = hook.name
        isEnabled = hook.isEnabled
        selectedTriggers = hook.triggers

        if let tools = hook.tools {
            applyToAllTools = false
            selectedTools = tools
        } else {
            applyToAllTools = true
        }

        actionType = hook.action.type

        if let cmd = hook.action.shellCommand {
            shellCommand = cmd
        }

        if let url = hook.action.webhookURL {
            webhookURL = url
        }

        if let method = hook.action.webhookMethod {
            webhookMethod = method
        }

        if let headers = hook.action.webhookHeaders {
            if let data = try? JSONSerialization.data(withJSONObject: headers, options: .prettyPrinted),
               let text = String(data: data, encoding: .utf8) {
                webhookHeadersText = text
            }
        }

        timeout = hook.action.timeout
    }

    private func saveHook() {
        guard isValid else { return }

        var headers: [String: String]?
        if actionType == .webhook && !webhookHeadersText.isEmpty {
            if let data = webhookHeadersText.data(using: .utf8),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                headers = dict
            }
        }

        let action: HookAction
        if actionType == .shell {
            action = HookAction.shell(command: shellCommand, timeout: timeout)
        } else {
            action = HookAction.webhook(
                url: webhookURL,
                method: webhookMethod,
                headers: headers,
                timeout: timeout
            )
        }

        let newHook = HookConfig(
            id: hook?.id ?? UUID().uuidString,
            name: name.trimmingCharacters(in: .whitespaces),
            isEnabled: isEnabled,
            triggers: selectedTriggers,
            tools: applyToAllTools ? nil : selectedTools,
            action: action
        )

        onSave(newHook)
        dismiss()
    }
}