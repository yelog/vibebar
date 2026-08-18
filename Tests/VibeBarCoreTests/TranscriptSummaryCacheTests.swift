import Foundation
import Testing
@testable import VibeBarCore

final class ParserCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _count
    }

    func increment() {
        lock.lock()
        _count += 1
        lock.unlock()
    }
}

@Test func transcriptSummaryCacheReturnsCachedValueWhenUnchanged() async {
    let counter = ParserCounter()
    let cache = TranscriptSummaryCache<Int>()
    let signature = TranscriptFileSignature(
        canonicalPath: "/x/1.jsonl",
        fileSize: 10,
        modificationDate: Date(timeIntervalSince1970: 100)
    )

    let first = await cache.value(for: "/x/1.jsonl", signature: signature, parserVersion: 1) {
        counter.increment()
        return 42
    }
    let second = await cache.value(for: "/x/1.jsonl", signature: signature, parserVersion: 1) {
        counter.increment()
        return 99
    }

    #expect(first == 42)
    #expect(second == 42)
    #expect(counter.count == 1)
}

@Test func transcriptSummaryCacheReParsesWhenSizeOrModificationChanges() async {
    let counter = ParserCounter()
    let cache = TranscriptSummaryCache<Int>()

    let original = TranscriptFileSignature(
        canonicalPath: "/x/1.jsonl",
        fileSize: 10,
        modificationDate: Date(timeIntervalSince1970: 100)
    )
    _ = await cache.value(for: "/x/1.jsonl", signature: original, parserVersion: 1) {
        counter.increment()
        return 1
    }

    let sizeChanged = TranscriptFileSignature(
        canonicalPath: "/x/1.jsonl",
        fileSize: 11,
        modificationDate: Date(timeIntervalSince1970: 100)
    )
    _ = await cache.value(for: "/x/1.jsonl", signature: sizeChanged, parserVersion: 1) {
        counter.increment()
        return 2
    }
    #expect(counter.count == 2)

    let modified = TranscriptFileSignature(
        canonicalPath: "/x/1.jsonl",
        fileSize: 10,
        modificationDate: Date(timeIntervalSince1970: 101)
    )
    _ = await cache.value(for: "/x/1.jsonl", signature: modified, parserVersion: 1) {
        counter.increment()
        return 3
    }
    #expect(counter.count == 3)
}

@Test func transcriptSummaryCacheFileReplacementInvalidatesEntry() async {
    let counter = ParserCounter()
    let cache = TranscriptSummaryCache<Int>()

    let old = TranscriptFileSignature(
        canonicalPath: "/x/1.jsonl",
        fileSize: 10,
        modificationDate: Date(timeIntervalSince1970: 100)
    )
    _ = await cache.value(for: "/x/1.jsonl", signature: old, parserVersion: 1) {
        counter.increment()
        return 1
    }

    let replaced = TranscriptFileSignature(
        canonicalPath: "/x/1.jsonl",
        fileSize: 12,
        modificationDate: Date(timeIntervalSince1970: 100)
    )
    let value = await cache.value(for: "/x/1.jsonl", signature: replaced, parserVersion: 1) {
        counter.increment()
        return 2
    }

    #expect(value == 2)
    #expect(counter.count == 2)
}

@Test func transcriptSummaryCacheParserVersionChangeInvalidatesEntries() async {
    let counter = ParserCounter()
    let cache = TranscriptSummaryCache<Int>()

    let signature = TranscriptFileSignature(
        canonicalPath: "/x/1.jsonl",
        fileSize: 10,
        modificationDate: Date(timeIntervalSince1970: 100)
    )
    _ = await cache.value(for: "/x/1.jsonl", signature: signature, parserVersion: 1) {
        counter.increment()
        return 1
    }
    let value = await cache.value(for: "/x/1.jsonl", signature: signature, parserVersion: 2) {
        counter.increment()
        return 2
    }

    #expect(value == 2)
    #expect(counter.count == 2)
}

@Test func transcriptSummaryCacheBoundsEntryCount() async {
    let counter = ParserCounter()
    let cache = TranscriptSummaryCache<Int>(maxEntries: 3)

    for i in 0..<6 {
        let signature = TranscriptFileSignature(
            canonicalPath: "/x/\(i).jsonl",
            fileSize: Int64(i),
            modificationDate: Date(timeIntervalSince1970: Double(100 + i))
        )
        _ = await cache.value(for: "/x/\(i).jsonl", signature: signature, parserVersion: 1) {
            counter.increment()
            return i
        }
    }

    #expect(await cache.count <= 3)
    #expect(counter.count == 6)
}

@Test func transcriptSummaryCacheWorksWithRealFileStat() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let url = directory.appendingPathComponent("transcript.jsonl")
    try Data("line one\n".utf8).write(to: url)

    let counter = ParserCounter()
    let cache = TranscriptSummaryCache<Int>()
    let signature = try #require(TranscriptFileIdentity.signature(for: url))

    _ = await cache.value(for: url.path, signature: signature, parserVersion: 1) {
        counter.increment()
        return 1
    }
    _ = await cache.value(for: url.path, signature: signature, parserVersion: 1) {
        counter.increment()
        return 2
    }
    #expect(counter.count == 1)

    try Data("line one\nline two\n".utf8).write(to: url)
    let newSignature = try #require(TranscriptFileIdentity.signature(for: url))
    let value = await cache.value(for: url.path, signature: newSignature, parserVersion: 1) {
        counter.increment()
        return 3
    }
    #expect(value == 3)
    #expect(counter.count == 2)
}