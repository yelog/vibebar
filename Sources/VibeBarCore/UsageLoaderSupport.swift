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
        pathExtension: String
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
            if values?.isRegularFile == true {
                files.append(
                    DiscoveredFile(
                        url: fileURL,
                        modificationTime: values?.contentModificationDate ?? .distantPast,
                        fileSize: Int64(values?.fileSize ?? 0)
                    )
                )
            }
        }
        return files.sorted { $0.url.path < $1.url.path }
    }

    static func weekStart(for date: Date, calendar baseCalendar: Calendar) -> Date {
        var calendar = baseCalendar
        calendar.firstWeekday = 2
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? calendar.startOfDay(for: date)
    }
}
