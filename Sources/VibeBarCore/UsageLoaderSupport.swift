import Foundation

enum UsageLoaderSupport {
    struct DiscoveredFile: Sendable {
        var url: URL
        var modificationTime: Date
        var fileSize: Int64
    }

    private final class LockedISO8601Parsers: @unchecked Sendable {
        private let lock = NSLock()
        private let fractionalSecondsFormatter: ISO8601DateFormatter
        private let regularFormatter: ISO8601DateFormatter

        init() {
            self.fractionalSecondsFormatter = Self.makeFormatter(fractionalSeconds: true)
            self.regularFormatter = Self.makeFormatter(fractionalSeconds: false)
        }

        func parse(_ value: String) -> Date? {
            lock.lock()
            defer { lock.unlock() }
            return fractionalSecondsFormatter.date(from: value) ?? regularFormatter.date(from: value)
        }

        private static func makeFormatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = fractionalSeconds
                ? [.withInternetDateTime, .withFractionalSeconds]
                : [.withInternetDateTime]
            return formatter
        }
    }

    private static let sharedDateParsers = LockedISO8601Parsers()

    static func makeISO8601Formatter(fractionalSeconds: Bool) -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractionalSeconds
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter
    }

    static func parseDate(_ value: String) -> Date? {
        sharedDateParsers.parse(value)
    }

    static func expandedPath(_ rawPath: String) -> String {
        (rawPath as NSString).expandingTildeInPath
    }

    static func directoryURLIfExists(at rawPath: String) -> URL? {
        let url = URL(fileURLWithPath: expandedPath(rawPath), isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return url
    }

    static func recursivelyEnumerateFiles(
        under root: URL,
        pathExtension: String,
        cutoffDate: Date? = nil
    ) -> [DiscoveredFile] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .contentModificationDateKey,
                .fileSizeKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let expectedExtension = pathExtension.lowercased()
        var files: [DiscoveredFile] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension.lowercased() == expectedExtension else { continue }
            let values = try? fileURL.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
            )
            guard values?.isRegularFile == true else { continue }

            let modificationTime = values?.contentModificationDate ?? .distantPast

            // 如果指定了cutoffDate，只加载修改时间 >= cutoffDate的文件
            if let cutoffDate {
                // 文件修改时间早于cutoffDate，可能不包含需要的数据，跳过
                // 添加小缓冲：修改时间 < cutoffDate - 1小时 的文件跳过
                let bufferCutoff = cutoffDate.addingTimeInterval(-3600)
                guard modificationTime >= bufferCutoff else { continue }
            }

            files.append(
                DiscoveredFile(
                    url: fileURL,
                    modificationTime: modificationTime,
                    fileSize: Int64(values?.fileSize ?? 0)
                )
            )
        }
        return files.sorted { $0.url.path < $1.url.path }
    }

    static func weekStart(for date: Date, calendar baseCalendar: Calendar) -> Date {
        var calendar = baseCalendar
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }

    static func eventIDPrefix(for source: UsageSource) -> String {
        switch source {
        case .claudeCode:
            return "claude:"
        case .codex:
            return "codex:"
        case .opencode:
            return "opencode:"
        case .gemini:
            return "gemini:"
        }
    }

    static func trackedFilePath(for event: UsageEvent) -> String? {
        trackedFilePath(fromEventID: event.id, source: event.source)
    }

    static func trackedFilePath(fromEventID eventID: String, source: UsageSource) -> String? {
        let prefix = eventIDPrefix(for: source)
        guard eventID.hasPrefix(prefix) else { return nil }

        let suffix = String(eventID.dropFirst(prefix.count))
        switch source {
        case .claudeCode, .codex, .gemini:
            guard let colonIndex = suffix.lastIndex(of: ":") else { return nil }
            let path = String(suffix[..<colonIndex])
            return path.isEmpty ? nil : path
        case .opencode:
            return suffix.hasPrefix("/") ? suffix : nil
        }
    }
}
