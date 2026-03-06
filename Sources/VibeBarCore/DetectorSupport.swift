import Foundation

/// Shared infrastructure for agent detectors.
///
/// Centralises OS-level operations that were previously duplicated across
/// individual detector implementations, including process listing, TCP port
/// discovery, bulk CWD lookup, and ISO-8601 date parsing.
public enum DetectorSupport {

    // MARK: - Process listing

    /// A single row from `ps -axo pid=,ppid=,pcpu=,etime=,comm=,args=`
    public struct ProcEntry: Sendable {
        /// Process ID
        public let pid: Int32
        /// Parent process ID
        public let ppid: Int32
        /// CPU usage percentage reported by `ps`
        public let cpu: Double
        /// Process elapsed time in seconds
        public let elapsedSeconds: Int
        /// `comm` column: the short executable name as reported by the kernel
        public let command: String
        /// `args` column: full command-line string (may start with the executable path)
        public let args: String

        /// Lowercase basename of `command` (strips any leading path components)
        public var commandName: String {
            pathBasename(command).lowercased()
        }
    }

    /// Shared per-refresh process snapshot.
    public struct DetectionContext: Sendable {
        public let processes: [ProcEntry]
        private let processesByPID: [Int32: ProcEntry]

        public init(processes: [ProcEntry]) {
            self.processes = processes
            self.processesByPID = Dictionary(uniqueKeysWithValues: processes.map { ($0.pid, $0) })
        }

        public func process(pid: Int32) -> ProcEntry? {
            processesByPID[pid]
        }
    }

    /// Run `ps -axo pid=,ppid=,pcpu=,etime=,comm=,args=` and return one entry per process.
    ///
    /// Uses `.isoLatin1` as fallback encoding to tolerate truncated multi-byte
    /// sequences that `ps` can produce for non-ASCII process names.
    public static func listProcesses() -> [ProcEntry] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-axo", "pid=,ppid=,pcpu=,etime=,comm=,args="]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1) else { return [] }

        return text.split(separator: "\n").compactMap { line in
            let parts = line.split(
                maxSplits: 5,
                omittingEmptySubsequences: true,
                whereSeparator: { $0 == " " || $0 == "\t" }
            )
            guard parts.count >= 5,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else {
                return nil
            }

            let cpu = Double(parts[2]) ?? 0
            let elapsedSeconds = parseElapsed(String(parts[3])) ?? 0
            let command = String(parts[4])
            let args = parts.count >= 6 ? String(parts[5]) : ""
            return ProcEntry(
                pid: pid,
                ppid: ppid,
                cpu: cpu,
                elapsedSeconds: elapsedSeconds,
                command: command,
                args: args
            )
        }
    }

    public static func makeContext() -> DetectionContext {
        DetectionContext(processes: listProcesses())
    }

    // MARK: - TCP port discovery

    public static func findListeningPort(pid: Int32, ttl: TimeInterval = 10) async -> Int? {
        let now = Date()
        switch await runtimeCache.cachedPort(pid: pid, now: now, ttl: ttl) {
        case .hit(let value):
            return value
        case .miss:
            let port = loadListeningPort(pid: pid)
            await runtimeCache.storePort(pid: pid, port: port, now: now)
            return port
        }
    }

    // MARK: - Bulk CWD lookup

    public static func bulkGetCwds(pids: [Int32], ttl: TimeInterval = 10) async -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }

        let now = Date()
        let (cached, missing) = await runtimeCache.cachedCwds(for: pids, now: now, ttl: ttl)
        guard !missing.isEmpty else { return cached }

        let loaded = loadCwds(pids: missing)
        await runtimeCache.storeCwds(loaded, now: now)

        var result = cached
        for (pid, cwd) in loaded {
            result[pid] = cwd
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

    // MARK: - CPU usage

    /// Get CPU usage percentage for a process.
    /// Returns nil if the process doesn't exist or on error.
    public static func getCPUUsage(pid: Int32) -> Double? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/ps")
        proc.arguments = ["-p", "\(pid)", "-o", "pcpu="]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(trimmed)
    }

    /// Check if a process is actively using CPU (above threshold).
    /// Default threshold is 1.0% to filter out idle processes.
    public static func isProcessActive(pid: Int32, threshold: Double = 1.0) -> Bool {
        guard let usage = getCPUUsage(pid: pid) else { return false }
        return usage >= threshold
    }

    // MARK: - Path helpers

    static func pathBasename(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    // MARK: - Private

    private enum CacheLookup<Value: Sendable>: Sendable {
        case hit(Value)
        case miss
    }

    private struct TimedValue<Value: Sendable>: Sendable {
        let value: Value
        let cachedAt: Date
    }

    private actor RuntimeCache {
        private var cwdByPID: [Int32: TimedValue<String>] = [:]
        private var portByPID: [Int32: TimedValue<Int?>] = [:]

        func cachedCwds(
            for pids: [Int32],
            now: Date,
            ttl: TimeInterval
        ) -> (cached: [Int32: String], missing: [Int32]) {
            var cached: [Int32: String] = [:]
            var missing: [Int32] = []

            for pid in pids {
                if let entry = cwdByPID[pid], now.timeIntervalSince(entry.cachedAt) <= ttl {
                    cached[pid] = entry.value
                } else {
                    missing.append(pid)
                }
            }

            return (cached, missing)
        }

        func storeCwds(_ values: [Int32: String], now: Date) {
            for (pid, cwd) in values where !cwd.isEmpty {
                cwdByPID[pid] = TimedValue(value: cwd, cachedAt: now)
            }
        }

        func cachedPort(pid: Int32, now: Date, ttl: TimeInterval) -> CacheLookup<Int?> {
            guard let entry = portByPID[pid], now.timeIntervalSince(entry.cachedAt) <= ttl else {
                return .miss
            }
            return .hit(entry.value)
        }

        func storePort(pid: Int32, port: Int?, now: Date) {
            portByPID[pid] = TimedValue(value: port, cachedAt: now)
        }
    }

    private static let runtimeCache = RuntimeCache()

    /// Find the TCP port that `pid` is listening on using `lsof`.
    ///
    /// Recognises the address patterns `*:PORT`, `[::]:PORT`, and
    /// `127.0.0.1:PORT` that lsof uses on macOS.
    private static func loadListeningPort(pid: Int32) -> Int? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
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
                   let port = Int(str[range]) {
                    return port
                }
            }
        }
        return nil
    }

    /// Fetch working directories for multiple PIDs in a single `lsof` call.
    ///
    /// Returns a mapping `pid → absolute cwd path`.
    /// Parses `-Fp -Fn` output where lines alternate between `p<pid>` and `n<path>`.
    private static func loadCwds(pids: [Int32]) -> [Int32: String] {
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

    /// Parses `ps etime` format into total elapsed seconds.
    /// Supported forms: `mm:ss`, `hh:mm:ss`, `dd-hh:mm:ss`.
    private static func parseElapsed(_ value: String) -> Int? {
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
