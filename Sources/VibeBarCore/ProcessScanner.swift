import Foundation

/// Fallback detector using ps command
/// Detects all supported tools but with limited state accuracy (CPU-based)
public struct ProcessScanner: AgentDetector {
    /// Tools to scan for. If nil, scans for all tools.
    private let allowedTools: Set<ToolKind>?

    public init(allowedTools: Set<ToolKind>? = nil) {
        self.allowedTools = allowedTools
    }

    public func detectSessions() -> [SessionSnapshot] {
        let now = Date()
        return scan(now: now)
    }

    /// Legacy scan method for backward compatibility
    public func scan(now: Date = Date()) -> [SessionSnapshot] {
        let lines = runPS()

        // Build parent command lookup: pid → command basename
        var parentCommands: [Int32: String] = [:]
        for line in lines {
            let parts = line.split(maxSplits: 5, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 5,
                  let pid = Int32(parts[0]) else { continue }
            let command = String(parts[4])
            parentCommands[pid] = URL(fileURLWithPath: command).lastPathComponent.lowercased()
        }

        // First pass: collect candidate processes (filter, no cwd yet)
        struct Candidate {
            var pid: Int32
            var ppid: Int32
            var cpu: Double
            var elapsedSeconds: Int
            var tool: ToolKind
            var args: String
        }
        var candidates: [Candidate] = []

        for line in lines {
            let parts = line.split(maxSplits: 5, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 6 else { continue }

            guard let pid = Int32(parts[0]) else { continue }
            guard let ppid = Int32(parts[1]) else { continue }
            guard let cpu = Double(parts[2]) else { continue }
            let elapsedSeconds = parseElapsed(String(parts[3])) ?? 0

            let command = String(parts[4])
            let args = String(parts[5])
            let detectedTool = ToolKind.detect(command: command, args: args)
            let tool = detectedTool ?? detectGeminiFromRuntime(command: command, args: args)
            guard let tool else { continue }

            // Skip if tool is not in allowed set
            if let allowed = allowedTools, !allowed.contains(tool) {
                continue
            }

            // 避免把 wrapper 进程自身识别为业务进程。
            let commandName = URL(fileURLWithPath: command).lastPathComponent.lowercased()
            if commandName == "vibebar" { continue }

            // 只保留由 shell 或终端直接启动的进程（真实用户会话），
            // 过滤掉由 bun/node 等运行时派生的内部工作进程。
            if let parentName = parentCommands[ppid] {
                if Self.shells.contains(parentName) { }
                else if parentName == "launchd" { }
                else { continue }
            }

            candidates.append(
                Candidate(
                    pid: pid,
                    ppid: ppid,
                    cpu: cpu,
                    elapsedSeconds: elapsedSeconds,
                    tool: tool,
                    args: args
                )
            )
        }

        // Bulk-fetch cwds for all candidates in one lsof call
        let cwds = DetectorSupport.bulkGetCwds(pids: candidates.map(\.pid))

        return candidates.map { c in
            let state: ToolActivityState = c.cpu >= 3.0 ? .running : .idle
            let startedAt = now.addingTimeInterval(-TimeInterval(c.elapsedSeconds))
            return SessionSnapshot(
                id: "ps-\(c.pid)",
                tool: c.tool,
                pid: c.pid,
                parentPID: c.ppid,
                status: state,
                source: .processScan,
                startedAt: startedAt,
                updatedAt: now,
                lastOutputAt: nil,
                lastInputAt: nil,
                cwd: cwds[c.pid],
                command: [c.args],
                notes: notes(for: c.tool, cpu: c.cpu)
            )
        }
    }

    private func detectGeminiFromRuntime(command: String, args: String) -> ToolKind? {
        let commandName = URL(fileURLWithPath: command).lastPathComponent.lowercased()
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
        // Shells
        "bash", "zsh", "fish", "sh", "dash", "tcsh", "csh", "ksh",
        "-bash", "-zsh", "-fish", "-sh", "-dash", "-tcsh", "-csh", "-ksh",
        // Terminal emulators
        "login", "sshd", "tmux", "screen",
        "tmux: server", "tmux:server",
        // macOS Terminal
        "terminal", "terminal.app",
        // iTerm2
        "iterm2", "iterm2-server", "iterm2-server-",
        // VS Code
        "code", "code helper", "code-helper",
        // Other common terminals
        "alacritty", "kitty", "warp", "hyper", "wezterm-gui",
        // If parent is unknown (ppid=1 or missing), still allow it
        // This will be handled by checking if parentCommands[ppid] is nil
    ]


    private func runPS() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,pcpu=,etime=,comm=,args="]

        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        // 先持续读取输出，避免进程输出较大时把 pipe 写满导致 waitUntilExit 死锁。
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        // ps output may contain truncated multi-byte UTF-8 sequences (e.g., Chinese app names
        // like /Applications/闪电说.app truncated mid-character by ps's column width).
        // .utf8 returns nil on any invalid byte; fall back to .isoLatin1 which maps every
        // byte 1-to-1 and never fails — safe because we only match ASCII process names.
        guard let text = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1)
        else { return [] }

        return text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Parses `ps etime` format into total elapsed seconds.
    /// Supported forms: `mm:ss`, `hh:mm:ss`, `dd-hh:mm:ss`.
    private func parseElapsed(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let dayAndTime = trimmed.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true)
        let day: Int
        let timePart: String
        if dayAndTime.count == 2 {
            guard let parsedDay = Int(dayAndTime[0]) else { return nil }
            day = parsedDay
            timePart = String(dayAndTime[1])
        } else {
            day = 0
            timePart = trimmed
        }

        let components = timePart.split(separator: ":", omittingEmptySubsequences: false)
        let hour: Int
        let minute: Int
        let second: Int
        switch components.count {
        case 3:
            guard let parsedHour = Int(components[0]),
                  let parsedMinute = Int(components[1]),
                  let parsedSecond = Int(components[2]) else {
                return nil
            }
            hour = parsedHour
            minute = parsedMinute
            second = parsedSecond
        case 2:
            guard let parsedMinute = Int(components[0]),
                  let parsedSecond = Int(components[1]) else {
                return nil
            }
            hour = 0
            minute = parsedMinute
            second = parsedSecond
        default:
            return nil
        }

        return day * 86_400 + hour * 3_600 + minute * 60 + second
    }
}
