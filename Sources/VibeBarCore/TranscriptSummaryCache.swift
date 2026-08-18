import Foundation

/// Identity of a transcript file used to decide whether a cached summary is
/// still valid: canonical path, file size, and modification timestamp.
public struct TranscriptFileSignature: Hashable, Sendable {
    public var canonicalPath: String
    public var fileSize: Int64
    public var modificationDate: Date

    public init(canonicalPath: String, fileSize: Int64, modificationDate: Date) {
        self.canonicalPath = canonicalPath
        self.fileSize = fileSize
        self.modificationDate = modificationDate
    }
}

/// Reads the current file identity for a URL.
public enum TranscriptFileIdentity {
    public static func signature(for url: URL) -> TranscriptFileSignature? {
        let path = url.resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return nil }
        return TranscriptFileSignature(
            canonicalPath: path,
            fileSize: (attributes[.size] as? NSNumber)?.int64Value ?? -1,
            modificationDate: attributes[.modificationDate] as? Date ?? .distantPast
        )
    }
}

/// Bounded cache of parsed transcript summaries keyed by file identity.
///
/// The parser closure only runs when the signature or parser version changes.
/// Detector-specific summary types are stored via the generic `Value` parameter
/// so detector private types are never exposed.
actor TranscriptSummaryCache<Value: Sendable> {
    private struct Entry {
        let value: Value
        let signature: TranscriptFileSignature
        let parserVersion: Int
    }

    private let maxEntries: Int
    private var entries: [String: Entry] = [:]

    public init(maxEntries: Int = 256) {
        self.maxEntries = maxEntries
    }

    /// Returns the cached summary for `path` when its signature and parser
    /// version match, otherwise runs `parser`, caches its result, and returns it.
    func value(
        for path: String,
        signature: TranscriptFileSignature,
        parserVersion: Int,
        parser: @escaping @Sendable () -> Value
    ) -> Value {
        if let entry = entries[path],
           entry.signature == signature,
           entry.parserVersion == parserVersion {
            return entry.value
        }

        let value = parser()
        entries[path] = Entry(value: value, signature: signature, parserVersion: parserVersion)
        evictIfNeeded()
        return value
    }

    /// Like `value(for:signature:parserVersion:parser:)`, but passes the previous
    /// cached value to `parser` so detectors can fold appended lines
    /// incrementally instead of re-parsing the whole file.
    func valueWithPrevious(
        for path: String,
        signature: TranscriptFileSignature,
        parserVersion: Int,
        parser: @escaping @Sendable (Value?) -> Value
    ) -> Value {
        if let entry = entries[path],
           entry.signature == signature,
           entry.parserVersion == parserVersion {
            return entry.value
        }

        let value = parser(entries[path]?.value)
        entries[path] = Entry(value: value, signature: signature, parserVersion: parserVersion)
        evictIfNeeded()
        return value
    }

    /// Removes entries parsed with a different parser version (or all entries
    /// when no version is given).
    func invalidate(parserVersion: Int? = nil) {
        if let parserVersion {
            entries = entries.filter { $0.value.parserVersion == parserVersion }
        } else {
            entries.removeAll()
        }
    }

    func clear() {
        entries.removeAll()
    }

    var count: Int {
        entries.count
    }

    private func evictIfNeeded() {
        guard entries.count > maxEntries else { return }
        let excess = entries.count - maxEntries
        let oldestKeys = entries
            .sorted { $0.value.signature.modificationDate < $1.value.signature.modificationDate }
            .prefix(excess)
            .map(\.key)
        for key in oldestKeys {
            entries.removeValue(forKey: key)
        }
    }
}