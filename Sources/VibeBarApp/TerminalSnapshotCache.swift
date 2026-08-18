import Foundation
import VibeBarCore

/// Kind of terminal snapshot command being cached.
enum TerminalSnapshotKind: Hashable, Sendable {
    case kitty
    case wezterm
    case ghostty
    case iterm
    case tmux
    case zellij
}

/// Cache key identifying a terminal snapshot command by kind and connection
/// identity.
struct TerminalSnapshotKey: Hashable, Sendable {
    var kind: TerminalSnapshotKind
    var address: String
}

/// Cross-refresh cache for terminal snapshot commands.
///
/// Positive results are cached for a longer TTL; failed commands are cached for
/// a shorter negative TTL so transient failures do not trigger a command every
/// refresh. Concurrent requests for the same key are coalesced into one
/// command. The cache is bounded and evicts the oldest entries when full.
actor TerminalSnapshotCache {
    static let shared = TerminalSnapshotCache()

    private struct Entry {
        let value: String?
        let loadedAt: Date
        let isNegative: Bool
    }

    private let positiveTTL: TimeInterval
    private let negativeTTL: TimeInterval
    private let maxEntries: Int
    private let clock: @Sendable () -> Date
    private var entries: [TerminalSnapshotKey: Entry] = [:]
    private var inFlight: [TerminalSnapshotKey: Task<String?, Never>] = [:]

    init(
        positiveTTL: TimeInterval = 15,
        negativeTTL: TimeInterval = 5,
        maxEntries: Int = 64,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.positiveTTL = positiveTTL
        self.negativeTTL = negativeTTL
        self.maxEntries = maxEntries
        self.clock = clock
    }

    /// Returns a cached snapshot for `key` when fresh, otherwise runs `loader`
    /// once (coalescing concurrent callers) and caches the result.
    func value(
        for key: TerminalSnapshotKey,
        loader: @escaping @Sendable () async -> String?
    ) async -> String? {
        let now = clock()
        if let entry = entries[key] {
            let ttl = entry.isNegative ? negativeTTL : positiveTTL
            if now.timeIntervalSince(entry.loadedAt) <= ttl {
                return entry.value
            }
        }

        if let inFlightTask = inFlight[key] {
            return await inFlightTask.value
        }

        let task = Task { await loader() }
        inFlight[key] = task
        defer { inFlight[key] = nil }

        let result = await task.value
        store(key: key, value: result, isNegative: result == nil, now: clock())
        return result
    }

    /// Invalidates every entry and cancels in-flight work.
    func clear() {
        for task in inFlight.values {
            task.cancel()
        }
        inFlight.removeAll()
        entries.removeAll()
    }

    var count: Int {
        entries.count
    }

    private func store(key: TerminalSnapshotKey, value: String?, isNegative: Bool, now: Date) {
        entries[key] = Entry(value: value, loadedAt: now, isNegative: isNegative)
        if entries.count > maxEntries {
            let excess = entries.count - maxEntries
            let oldestKeys = entries
                .sorted { $0.value.loadedAt < $1.value.loadedAt }
                .prefix(excess)
                .map(\.key)
            for key in oldestKeys {
                entries.removeValue(forKey: key)
            }
        }
    }
}