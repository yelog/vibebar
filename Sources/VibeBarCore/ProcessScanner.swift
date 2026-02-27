import Foundation

/// Fallback detector using ps command
/// Detects all supported tools but with limited state accuracy (CPU-based)
public struct ProcessScanner: AgentDetector {
    public init() {}

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
            let parts = line.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 4,
                  let pid = Int32(parts[0]) else { continue }
            let command = String(parts[3])
            parentCommands[pid] = URL(fileURLWithPath: command).lastPathComponent.lowercased()
        }

        // First pass: collect candidate processes (filter, no cwd yet)
        struct Candidate {
            var pid: Int32; var ppid: Int32; var cpu: Double; var tool: ToolKind; var args: String
        }
        var candidates: [Candidate] = []

        for line in lines {
            let parts = line.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 5 else { continue }

            guard let pid = Int32(parts[0]) else { continue }
            guard let ppid = Int32(parts[1]) else { continue }
            guard let cpu = Double(parts[2]) else { continue }

            let command = String(parts[3])
            let args = String(parts[4])
            let detectedTool = ToolKind.detect(command: command, args: args)
            let tool = detectedTool ?? detectGeminiFromRuntime(command: command, args: args)
            guard let tool else { continue }

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

            candidates.append(Candidate(pid: pid, ppid: ppid, cpu: cpu, tool: tool, args: args))
        }

        // Bulk-fetch cwds for all candidates in one lsof call
        let cwds = bulkGetCwds(pids: candidates.map(\.pid))

        return candidates.map { c in
            let state: ToolActivityState = c.cpu >= 3.0 ? .running : .idle
            return SessionSnapshot(
                id: "ps-\(c.pid)",
                tool: c.tool,
                pid: c.pid,
                parentPID: c.ppid,
                status: state,
                source: .processScan,
                startedAt: now,
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
            loweredArgs.contains("/gemini.mjs") {
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


    /// Fetch working directories for multiple PIDs in a single `lsof` call.
    /// Returns a mapping pid → absolute cwd path.
    private func bulkGetCwds(pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -a: AND (select only cwd descriptor for the given PIDs)
        // -Fp: include pid lines (p<pid>); -Fn: include name lines (n<path>)
        process.arguments = ["-a", "-p", pids.map(String.init).joined(separator: ","),
                             "-d", "cwd", "-Fp", "-Fn"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

        // lsof -Fp -Fn output alternates: "p<pid>" then "n<path>"
        var result: [Int32: String] = [:]
        var currentPID: Int32?
        for line in text.split(separator: "\n") {
            let s = String(line)
            if s.hasPrefix("p"), let pid = Int32(s.dropFirst()) {
                currentPID = pid
            } else if s.hasPrefix("n"), let pid = currentPID {
                let path = String(s.dropFirst())
                if !path.isEmpty { result[pid] = path }
                currentPID = nil
            }
        }
        return result
    }

    private func runPS() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,ppid=,pcpu=,comm=,args="]

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
}
