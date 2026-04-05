import Foundation

/// Fallback detector using ps command
/// Detects all supported tools but with limited state accuracy (CPU-based)
public struct ProcessScanner: AgentDetector {
    /// Tools to scan for. If nil, scans for all tools.
    private let allowedTools: Set<ToolKind>?

    public init(allowedTools: Set<ToolKind>? = nil) {
        self.allowedTools = allowedTools
    }

    public func detectSessions() async -> [SessionSnapshot] {
        let context = DetectorSupport.makeContext()
        return await scan(now: Date(), context: context)
    }

    /// Legacy scan method for backward compatibility
    public func scan(
        now: Date = Date(),
        context: DetectorSupport.DetectionContext
    ) async -> [SessionSnapshot] {
        // Build parent command lookup: pid → command basename
        var parentCommands: [Int32: String] = [:]
        for entry in context.processes {
            parentCommands[entry.pid] = entry.commandName
        }

        // First pass: collect candidate processes (filter, no cwd yet)
        struct Candidate {
            var process: DetectorSupport.ProcEntry
            var tool: ToolKind
        }
        var candidates: [Candidate] = []

        for entry in context.processes {
            let detectedTool = ToolKind.detect(command: entry.command, args: entry.args)
            let tool = detectedTool ?? detectGeminiFromRuntime(command: entry.command, args: entry.args)
            guard let tool else { continue }

            if let allowed = allowedTools, !allowed.contains(tool) {
                continue
            }

            let commandName = entry.commandName
            if commandName == "vibebar" { continue }

            if let parentName = parentCommands[entry.ppid] {
                if Self.shells.contains(parentName) { }
                else if parentName == "launchd" { }
                else { continue }
            }

            candidates.append(
                Candidate(
                    process: entry,
                    tool: tool
                )
            )
        }

        let cwds = await DetectorSupport.bulkGetCwds(pids: candidates.map(\.process.pid))

        var sessions: [SessionSnapshot] = []
        sessions.reserveCapacity(candidates.count)

        for candidate in candidates {
            let state: ToolActivityState = candidate.process.cpu >= 3.0 ? .running : .idle
            let startedAt = now.addingTimeInterval(-TimeInterval(candidate.process.elapsedSeconds))
            let originHint: SessionOriginKind? = candidate.tool == .codex ? nil : .cli
            let terminalContext = await TerminalContextResolver.resolve(
                process: candidate.process,
                context: context,
                originHint: originHint
            )

            sessions.append(
                SessionSnapshot(
                    id: "ps-\(candidate.process.pid)",
                    tool: candidate.tool,
                    pid: candidate.process.pid,
                    parentPID: candidate.process.ppid,
                    status: state,
                    source: .processScan,
                    startedAt: startedAt,
                    updatedAt: now,
                    lastOutputAt: nil,
                    lastInputAt: nil,
                    cwd: cwds[candidate.process.pid],
                    command: [candidate.process.args],
                    notes: notes(for: candidate.tool, cpu: candidate.process.cpu),
                    terminalContext: terminalContext
                )
            )
        }

        return sessions
    }

    private func detectGeminiFromRuntime(command: String, args: String) -> ToolKind? {
        let commandName = DetectorSupport.pathBasename(command).lowercased()
        let loweredArgs = args.lowercased()
        let runtimeNames: Set<String> = ["node", "nodejs", "npm", "npx", "pnpm", "yarn", "bun"]
        guard runtimeNames.contains(commandName) else {
            return nil
        }
        if loweredArgs.contains("@google/gemini-cli") ||
            loweredArgs.contains("gemini-cli") ||
            loweredArgs.contains("/gemini.js") ||
            loweredArgs.contains("/gemini.mjs") ||
            loweredArgs.contains("/bin/gemini") {
            return .gemini
        }
        return nil
    }

    private func notes(for tool: ToolKind, cpu: Double) -> String {
        if tool == .gemini {
            return String(format: "process-fallback cpu=%.1f%%", cpu)
        }
        return String(format: "cpu=%.1f%%", cpu)
    }

    /// Known interactive shells and terminal emulators — a process parented by one of these is likely a user session.
    private static let shells: Set<String> = [
        "bash", "zsh", "fish", "sh", "dash", "tcsh", "csh", "ksh",
        "-bash", "-zsh", "-fish", "-sh", "-dash", "-tcsh", "-csh", "-ksh",
        "login", "sshd", "tmux", "screen",
        "tmux: server", "tmux:server",
        "terminal", "terminal.app",
        "iterm2", "iterm2-server", "iterm2-server-",
        "code", "code helper", "code-helper",
        "alacritty", "kitty", "ghostty", "warp", "hyper", "wezterm", "wezterm-gui",
    ]
}
