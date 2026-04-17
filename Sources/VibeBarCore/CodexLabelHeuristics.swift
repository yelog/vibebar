import Foundation

public enum CodexLabelHeuristics {
    private static let lowSignalToolLabels: Set<String> = [
        "apply_patch",
        "automation_update",
        "bash",
        "click",
        "edit",
        "exec_command",
        "finance",
        "find",
        "glob",
        "grep",
        "image_query",
        "install_workspace_dependencies",
        "load_workspace_dependencies",
        "ls",
        "multiedit",
        "open",
        "parallel",
        "read",
        "read_thread_terminal",
        "request_user_input",
        "search_query",
        "send_input",
        "spawn_agent",
        "sports",
        "time",
        "tool_search_tool",
        "view_image",
        "wait_agent",
        "weather",
        "write",
        "write_stdin",
    ]

    public static func isLowSignalToolLabel(_ value: String?) -> Bool {
        guard let normalized = normalized(value) else {
            return false
        }

        let lowered = normalized.lowercased()
        if lowSignalToolLabels.contains(lowered) {
            return true
        }

        if lowered.hasPrefix("mcp__") || lowered.hasPrefix("functions.") {
            return true
        }

        return false
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
