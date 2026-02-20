import Foundation

public struct ProcessScanner {
    public init() {}

    public func scan(now: Date = Date()) -> [SessionSnapshot] {
        let lines = runPS()
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
            if URL(fileURLWithPath: command).lastPathComponent.lowercased() == "vibebar" {
                continue
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
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        return text
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
