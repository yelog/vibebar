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

        var results: [SessionSnapshot] = []

        for line in lines {
            let parts = line.split(maxSplits: 4, omittingEmptySubsequences: true, whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 5 else { continue }

            guard let pid = Int32(parts[0]) else { continue }
            guard let ppid = Int32(parts[1]) else { continue }
            guard let cpu = Double(parts[2]) else { continue }

            let command = String(parts[3])
            let args = String(parts[4])
            guard let tool = ToolKind.detect(command: command, args: args) else { continue }

            // 避免把 wrapper 进程自身识别为业务进程。
            let commandName = URL(fileURLWithPath: command).lastPathComponent.lowercased()
            if commandName == "vibebar" {
                continue
            }

            // 只保留由 shell 或终端直接启动的进程（真实用户会话），
            // 过滤掉由 bun/node 等运行时派生的内部工作进程。
            if let parentName = parentCommands[ppid] {
                // 如果父进程在已知 shell/终端列表中，接受
                if Self.shells.contains(parentName) {
                    // 接受
                }
                // 如果父进程是 launchd（系统启动），也接受
                else if parentName == "launchd" {
                    // 接受
                }
                // 否则过滤掉（可能是 node/bun 的子进程）
                else {
                    continue
                }
            }

            let state: ToolActivityState = cpu >= 3.0 ? .running : .idle

            results.append(
                SessionSnapshot(
                    id: "ps-\(pid)",
                    tool: tool,
                    pid: pid,
                    parentPID: ppid,
                    status: state,
                    source: .processScan,
                    startedAt: now,
                    updatedAt: now,
                    lastOutputAt: nil,
                    lastInputAt: nil,
                    cwd: nil,
                    command: [args],
                    notes: String(format: "cpu=%.1f%%", cpu)
                )
            )
        }

        return results
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
