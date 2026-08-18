import Darwin
import Foundation

/// Shared infrastructure for agent detectors.
///
/// Centralises OS-level operations that were previously duplicated across
/// individual detector implementations, including process listing, TCP port
/// discovery, bulk CWD lookup, and ISO-8601 date parsing.
public enum DetectorSupport {

    // MARK: - Process listing

    /// A single row from `ps -axo pid=,ppid=,tty=,state=,pcpu=,etime=,comm=,args=`
    public struct ProcEntry: Sendable {
        /// Process ID
        public let pid: Int32
        /// Parent process ID
        public let ppid: Int32
        /// Terminal associated with the process, if any
        public let tty: String?
        /// Process state (R=running, S=sleeping, T=stopped, Z=zombie, E=exiting, etc.)
        public let state: String
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

        /// Check if this is a zombie (defunct) process
        public var isZombie: Bool {
            state.uppercased().hasPrefix("Z")
        }

        /// Check if this is a stopped (suspended) process
        public var isStopped: Bool {
            state.uppercased().hasPrefix("T")
        }

        /// Check if this is an exiting process
        public var isExiting: Bool {
            state.uppercased().contains("E")
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

        public func parentChain(startingAt pid: Int32, limit: Int = 8) -> [ProcEntry] {
            guard limit > 0 else { return [] }

            var chain: [ProcEntry] = []
            var currentPID = pid
            var visited = Set<Int32>()

            while chain.count < limit, currentPID > 0, !visited.contains(currentPID),
                  let process = processesByPID[currentPID] {
                chain.append(process)
                visited.insert(currentPID)
                currentPID = process.ppid
            }

            return chain
        }
    }

    /// Run `ps -axo pid=,ppid=,tty=,state=,pcpu=,etime=,comm=,args=` and return one entry per process.
    ///
    /// Uses `.isoLatin1` as fallback encoding to tolerate truncated multi-byte
    /// sequences that `ps` can produce for non-ASCII process names.
    /// Filters out zombie, stopped, and exiting processes automatically.
    public static func listProcesses() -> [ProcEntry] {
        EnergyDiagnostics.shared.record(.processSnapshot)
        guard let data = runProcessOutput(
            executablePath: "/bin/ps",
            arguments: ["-axo", "pid=,ppid=,tty=,state=,pcpu=,etime=,comm=,args="]
        ) else { return [] }
        guard let text = String(data: data, encoding: .utf8)
                      ?? String(data: data, encoding: .isoLatin1) else { return [] }

        return text.split(separator: "\n").compactMap { line -> ProcEntry? in
            let parts = line.split(
                maxSplits: 7,
                omittingEmptySubsequences: true,
                whereSeparator: { $0 == " " || $0 == "\t" }
            )
            guard parts.count >= 7,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]) else {
                return nil
            }

            let tty = normalizeTTY(String(parts[2]))
            let state = String(parts[3])
            // Filter out zombie, stopped, and exiting processes
            let stateUpper = state.uppercased()
            if stateUpper.hasPrefix("Z") ||  // Zombie - process is dead
               stateUpper.hasPrefix("T") ||  // Stopped - process is suspended (Ctrl+Z)
               stateUpper.contains("E") {    // Exiting - process is terminating
                return nil
            }

            let cpu = Double(parts[4]) ?? 0
            let elapsedSeconds = parseElapsed(String(parts[5])) ?? 0
            let command = String(parts[6])
            let args = parts.count >= 8 ? String(parts[7]) : ""
            return ProcEntry(
                pid: pid,
                ppid: ppid,
                tty: tty,
                state: state,
                cpu: cpu,
                elapsedSeconds: elapsedSeconds,
                command: command,
                args: args
            )
        }
    }

    public static func makeContext(ttl: TimeInterval = 1) -> DetectionContext {
        processContextCache.context(ttl: ttl) {
            DetectionContext(processes: loadProcessEntries())
        }
    }

    /// Test-only hook to intercept process listing and count snapshot requests.
    /// Passing `nil` restores the real `/bin/ps` path and resets the cache.
    static func setProcessListProviderForTesting(_ provider: (() -> [ProcEntry])?) {
        processListProviderLock.lock()
        testProcessListProvider = provider
        processListProviderLock.unlock()
        processContextCache.reset()
    }

    private static let processListProviderLock = NSLock()
    nonisolated(unsafe) private static var testProcessListProvider: (() -> [ProcEntry])?

    private static func loadProcessEntries() -> [ProcEntry] {
        processListProviderLock.lock()
        let provider = testProcessListProvider
        processListProviderLock.unlock()
        if let provider {
            return provider()
        }
        return listProcesses()
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

    // MARK: - Environment lookup

    public static func getProcessEnvironment(
        pid: Int32,
        ttl: TimeInterval = 10
    ) async -> [String: String] {
        let now = Date()
        switch await runtimeCache.cachedEnvironment(pid: pid, now: now, ttl: ttl) {
        case .hit(let value):
            return value
        case .miss:
            let environment = loadProcessEnvironment(pid: pid)
            await runtimeCache.storeEnvironment(pid: pid, environment: environment, now: now)
            return environment
        }
    }

    static func normalizeTTY(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "??" else { return nil }
        return trimmed
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
        guard let data = runProcessOutput(
            executablePath: "/bin/ps",
            arguments: ["-p", "\(pid)", "-o", "pcpu="]
        ) else { return nil }
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

    // Pre-compiled regex patterns for port detection (avoid recompilation on each call)
    private static let portPatterns: [NSRegularExpression] = {
        [#"\*:(\d+)"#, #"\[::\]:(\d+)"#, #"127\.0\.0\.1:(\d+)"#]
            .compactMap { try? NSRegularExpression(pattern: $0) }
    }()

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
        private var environmentByPID: [Int32: TimedValue<[String: String]>] = [:]

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

        func cachedEnvironment(
            pid: Int32,
            now: Date,
            ttl: TimeInterval
        ) -> CacheLookup<[String: String]> {
            guard let entry = environmentByPID[pid], now.timeIntervalSince(entry.cachedAt) <= ttl else {
                return .miss
            }
            return .hit(entry.value)
        }

        func storeEnvironment(pid: Int32, environment: [String: String], now: Date) {
            environmentByPID[pid] = TimedValue(value: environment, cachedAt: now)
        }
    }

    private static let runtimeCache = RuntimeCache()
    private static let processContextCache = ProcessContextCache()

    private final class ProcessContextCache: @unchecked Sendable {
        private struct CachedContext {
            let context: DetectionContext
            let cachedAt: Date
        }

        private let condition = NSCondition()
        private var cached: CachedContext?
        private var isLoading = false

        func context(ttl: TimeInterval, loader: () -> DetectionContext) -> DetectionContext {
            guard ttl > 0 else { return loader() }

            condition.lock()
            while true {
                if let cached, Date().timeIntervalSince(cached.cachedAt) <= ttl {
                    condition.unlock()
                    return cached.context
                }

                if !isLoading {
                    isLoading = true
                    condition.unlock()

                    let loaded = loader()

                    condition.lock()
                    cached = CachedContext(context: loaded, cachedAt: Date())
                    isLoading = false
                    condition.broadcast()
                    condition.unlock()
                    return loaded
                }

                condition.wait()
            }
        }

        func reset() {
            condition.lock()
            cached = nil
            isLoading = false
            condition.broadcast()
            condition.unlock()
        }
    }

    private final class ProcessOutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Data?

        func set(_ data: Data) {
            lock.lock()
            value = data
            lock.unlock()
        }

        func get() -> Data? {
            lock.lock()
            let data = value
            lock.unlock()
            return data
        }
    }

    private final class ProcessExecution: @unchecked Sendable {
        private let process: Process
        private let stdoutPipe = Pipe()

        init(executablePath: String, arguments: [String]) {
            process = Process()
            process.executableURL = URL(fileURLWithPath: executablePath)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = Pipe()
        }

        func run() throws {
            try process.run()
        }

        func readAndWait(into output: ProcessOutputBox, signal semaphore: DispatchSemaphore) {
            let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            output.set(data)
            semaphore.signal()
        }

        func terminate() {
            guard process.isRunning else { return }
            process.terminate()
        }

        func kill() {
            guard process.isRunning else { return }
            Darwin.kill(process.processIdentifier, SIGKILL)
        }
    }

    private static func runProcessOutput(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval = 3.0
    ) -> Data? {
        let execution = ProcessExecution(executablePath: executablePath, arguments: arguments)
        guard (try? execution.run()) != nil else { return nil }

        let output = ProcessOutputBox()
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .utility).async {
            execution.readAndWait(into: output, signal: semaphore)
        }

        guard semaphore.wait(timeout: .now() + timeout) == .success else {
            execution.terminate()
            if semaphore.wait(timeout: .now() + 0.5) == .timedOut {
                execution.kill()
                _ = semaphore.wait(timeout: .now() + 0.5)
            }
            return nil
        }

        return output.get()
    }

    /// Find the TCP port that `pid` is listening on using `lsof`.
    ///
    /// Recognises the address patterns `*:PORT`, `[::]:PORT`, and
    /// `127.0.0.1:PORT` that lsof uses on macOS.
    private static func loadListeningPort(pid: Int32) -> Int? {
        guard let data = runProcessOutput(
            executablePath: "/usr/sbin/lsof",
            arguments: ["-a", "-p", "\(pid)", "-Pn", "-iTCP", "-sTCP:LISTEN"]
        ) else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n") {
            let str = String(line)
            for regex in portPatterns {
                if let match = regex.firstMatch(in: str, range: NSRange(str.startIndex..., in: str)),
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
        EnergyDiagnostics.shared.record(.cwdLookup)
        guard let data = runProcessOutput(
            executablePath: "/usr/sbin/lsof",
            arguments: ["-a", "-p", pids.map(String.init).joined(separator: ","),
                        "-d", "cwd", "-Fp", "-Fn"]
        ) else { return [:] }
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

    private static func loadProcessEnvironment(pid: Int32) -> [String: String] {
        EnergyDiagnostics.shared.record(.environmentLookup)
        guard let data = runProcessOutput(
            executablePath: "/bin/ps",
            arguments: ["eww", "-p", "\(pid)", "-o", "command="]
        ) else { return [:] }
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1) else {
            return [:]
        }

        return parseEnvironmentDump(text)
    }

    private static func parseEnvironmentDump(_ text: String) -> [String: String] {
        let interestingKeys = [
            "TERM_PROGRAM",
            "ITERM_SESSION_ID",
            "TERM_SESSION_ID",
            "TMUX",
            "TMUX_PANE",
            "KITTY_WINDOW_ID",
            "KITTY_LISTEN_ON",
            "GHOSTTY_SURFACE_ID",
            "WEZTERM_PANE",
            "WEZTERM_UNIX_SOCKET",
            "__CFBundleIdentifier",
            "ZELLIJ",
            "ZELLIJ_SESSION_NAME",
            "ZELLIJ_PANE_ID",
            "ZELLIJ_TAB_NAME",
            "ZELLIJ_TAB_INDEX",
            "CODEX_THREAD_ID",
            "CODEX_SHELL",
            "CODEX_INTERNAL_ORIGINATOR_OVERRIDE",
            "TERM",
        ]

        var result: [String: String] = [:]
        for key in interestingKeys {
            if let value = extractEnvironmentValue(named: key, in: text) {
                result[key] = value
            }
        }
        return result
    }

    private static func extractEnvironmentValue(named key: String, in text: String) -> String? {
        let pattern = "(?:^|\\s)\(NSRegularExpression.escapedPattern(for: key))=([^\\s]+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[valueRange])
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
