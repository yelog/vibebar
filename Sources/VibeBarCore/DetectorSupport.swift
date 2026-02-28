import Foundation

/// Shared infrastructure for agent detectors.
///
/// Centralises OS-level operations that were previously duplicated across
/// individual detector implementations, including process listing, TCP port
/// discovery, bulk CWD lookup, and ISO-8601 date parsing.
public enum DetectorSupport {

    // MARK: - Process listing

    /// A single row from `ps -axo pid=,ppid=,comm=,args=`
    public struct ProcEntry: Sendable {
        /// Process ID
        public let pid: Int32
        /// Parent process ID
        public let ppid: Int32
        /// `comm` column: the short executable name as reported by the kernel
        public let command: String
        /// `args` column: full command-line string (may start with the executable path)
        public let args: String
        /// Lowercase basename of `command` (strips any leading path components)
        public var commandName: String {
            URL(fileURLWithPath: command).lastPathComponent.lowercased()
        }
    }

    /// Run `ps -axo pid=,ppid=,comm=,args=` and return one entry per process.
    ///
    /// Uses `.isoLatin1` as fallback encoding to tolerate truncated multi-byte
    /// sequences that `ps` can produce for non-ASCII process names.
    public static func listProcesses() -> [ProcEntry] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-axo", "pid=,ppid=,comm=,args="]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1) else { return [] }

        return text.split(separator: "\n").compactMap { line in
            // Split into at most 4 parts: pid  ppid  comm  <rest-as-args>
            let parts = line.split(maxSplits: 3,
                                   omittingEmptySubsequences: true,
                                   whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 3,
                  let pid  = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else { return nil }
            let command = String(parts[2])
            let args    = parts.count >= 4 ? String(parts[3]) : ""
            return ProcEntry(pid: pid, ppid: ppid, command: command, args: args)
        }
    }

    // MARK: - TCP port discovery

    /// Find the TCP port that `pid` is listening on using `lsof`.
    ///
    /// Recognises the address patterns `*:PORT`, `[::]:PORT`, and
    /// `127.0.0.1:PORT` that lsof uses on macOS.
    public static func findListeningPort(pid: Int32) -> Int? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -a: AND all filters so we only get TCP LISTEN sockets for this PID
        proc.arguments = ["-a", "-p", "\(pid)", "-Pn", "-iTCP", "-sTCP:LISTEN"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        let patterns = [#"\*:(\d+)"#, #"\[::\]:(\d+)"#, #"127\.0\.0\.1:(\d+)"#]
        for line in text.split(separator: "\n") {
            let str = String(line)
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)),
                   let range = Range(match.range(at: 1), in: str),
                   let port  = Int(str[range]) {
                    return port
                }
            }
        }
        return nil
    }

    // MARK: - Bulk CWD lookup

    /// Fetch working directories for multiple PIDs in a single `lsof` call.
    ///
    /// Returns a mapping `pid → absolute cwd path`.
    /// Parses `-Fp -Fn` output where lines alternate between `p<pid>` and `n<path>`.
    public static func bulkGetCwds(pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        proc.arguments = ["-a", "-p", pids.map(String.init).joined(separator: ","),
                          "-d", "cwd", "-Fp", "-Fn"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return [:] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }

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

    // MARK: - Date parsing

    /// Parse an ISO 8601 date string, falling back from fractional-seconds to
    /// whole-seconds format so both `2024-01-01T00:00:00.000Z` and
    /// `2024-01-01T00:00:00Z` are accepted.
    public static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
