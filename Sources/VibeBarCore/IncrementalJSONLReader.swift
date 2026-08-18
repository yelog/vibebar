import Foundation

/// Persisted read position for incrementally parsing a JSONL file.
///
/// `byteOffset` points just past the last delivered line; `partialLine` holds
/// the trailing bytes that have not yet formed a complete line. `inode`
/// identifies the underlying file so replacement (atomic rename) is detected.
public struct IncrementalJSONLReaderState: Sendable, Equatable {
    public var canonicalPath: String
    public var inode: UInt64
    public var byteOffset: Int
    public var partialLine: Data

    public init(canonicalPath: String, inode: UInt64, byteOffset: Int, partialLine: Data) {
        self.canonicalPath = canonicalPath
        self.inode = inode
        self.byteOffset = byteOffset
        self.partialLine = partialLine
    }
}

/// Incrementally reads appended lines from a JSONL file.
///
/// The reader tracks the file identity (inode), byte offset, and trailing
/// partial bytes. On truncation or identity change it resets to offset zero and
/// returns the whole (new) file content. Only complete lines are delivered;
/// invalid UTF-8 lines are skipped, and the returned state persists the offset
/// only up to the last successfully delivered line.
public enum IncrementalJSONLReader {
    public struct ReadResult: Sendable {
        public var lines: [String]
        public var state: IncrementalJSONLReaderState
    }

    /// Reads newly appended complete lines from `url`, resuming from `state`.
    /// Returns nil when the file cannot be statted or opened.
    public static func readLines(
        from url: URL,
        state: IncrementalJSONLReaderState?
    ) -> ReadResult? {
        guard let identity = statIdentity(for: url) else { return nil }

        var byteOffset = 0
        var reset = state == nil || state?.inode != identity.inode

        if let state, !reset {
            if state.byteOffset > identity.fileSize {
                reset = true  // truncated
            } else {
                byteOffset = state.byteOffset
            }
        }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var newData: Data
        if reset {
            byteOffset = 0
            newData = (try? handle.readToEnd()) ?? Data()
        } else {
            try? handle.seek(toOffset: UInt64(byteOffset))
            newData = (try? handle.readToEnd()) ?? Data()
        }

        var lines: [String] = []
        var searchStart = newData.startIndex
        while let newline = newData[searchStart...].firstIndex(of: 0x0A) {
            let lineData = newData[searchStart..<newline]
            if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
            searchStart = newData.index(after: newline)
        }
        let trailing = newData[searchStart...]
        let newByteOffset = byteOffset + newData.count - trailing.count

        return ReadResult(
            lines: lines,
            state: IncrementalJSONLReaderState(
                canonicalPath: identity.canonicalPath,
                inode: identity.inode,
                byteOffset: newByteOffset,
                partialLine: Data(trailing)
            )
        )
    }

    private struct FileIdentity {
        var canonicalPath: String
        var inode: UInt64
        var fileSize: Int
    }

    private static func statIdentity(for url: URL) -> FileIdentity? {
        let path = url.resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
            return nil
        }
        let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        return FileIdentity(canonicalPath: path, inode: inode, fileSize: size)
    }
}