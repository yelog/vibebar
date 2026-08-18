import Foundation
import Testing
@testable import VibeBarCore

@Test func recursiveWatcherReportsCreateAndNestedPaths() throws {
    let root = try makeWatchRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let collector = PathBatchCollector()
    let watcher = RecursiveFileEventWatcher { batch in
        collector.append(batch)
    }
    watcher.start(paths: [root.path])
    Thread.sleep(forTimeInterval: 0.3)

    let nested = root.appendingPathComponent("a", isDirectory: true)
        .appendingPathComponent("b", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    let file = nested.appendingPathComponent("file.jsonl", isDirectory: false)
    try Data("x".utf8).write(to: file)

    #expect(collector.waitForPath(containing: "file.jsonl", timeout: 5))
    watcher.stop()
}

@Test func recursiveWatcherReportsAppend() throws {
    let root = try makeWatchRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let collector = PathBatchCollector()
    let watcher = RecursiveFileEventWatcher { batch in
        collector.append(batch)
    }
    watcher.start(paths: [root.path])
    Thread.sleep(forTimeInterval: 0.3)

    let file = root.appendingPathComponent("log.jsonl", isDirectory: false)
    try Data("line one\n".utf8).write(to: file)
    #expect(collector.waitForPath(containing: "log.jsonl", timeout: 5))

    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data("line two\n".utf8))
    try handle.close()
    #expect(collector.waitForPath(containing: "log.jsonl", timeout: 5, distinctFrom: 1))

    watcher.stop()
}

@Test func recursiveWatcherReportsDelete() throws {
    let root = try makeWatchRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let collector = PathBatchCollector()
    let watcher = RecursiveFileEventWatcher { batch in
        collector.append(batch)
    }
    watcher.start(paths: [root.path])
    Thread.sleep(forTimeInterval: 0.3)

    let file = root.appendingPathComponent("to-delete.jsonl", isDirectory: false)
    try Data("x".utf8).write(to: file)
    #expect(collector.waitForPath(containing: "to-delete.jsonl", timeout: 5))

    try FileManager.default.removeItem(at: file)
    #expect(collector.waitForPath(containing: "to-delete.jsonl", timeout: 5, distinctFrom: 1))

    watcher.stop()
}

@Test func recursiveWatcherReportsRename() throws {
    let root = try makeWatchRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let collector = PathBatchCollector()
    let watcher = RecursiveFileEventWatcher { batch in
        collector.append(batch)
    }
    watcher.start(paths: [root.path])
    Thread.sleep(forTimeInterval: 0.3)

    let file = root.appendingPathComponent("old.jsonl", isDirectory: false)
    try Data("x".utf8).write(to: file)
    #expect(collector.waitForPath(containing: "old.jsonl", timeout: 5))

    try FileManager.default.moveItem(
        at: file,
        to: root.appendingPathComponent("new.jsonl", isDirectory: false)
    )
    #expect(collector.waitForPath(containing: "new.jsonl", timeout: 5))

    watcher.stop()
}

@Test func recursiveWatcherBatchesMultipleWrites() throws {
    let root = try makeWatchRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let collector = PathBatchCollector()
    let watcher = RecursiveFileEventWatcher { batch in
        collector.append(batch)
    }
    watcher.start(paths: [root.path])
    Thread.sleep(forTimeInterval: 0.3)

    for i in 0..<3 {
        try Data("\(i)".utf8).write(to: root.appendingPathComponent("f\(i).jsonl", isDirectory: false))
    }

    #expect(collector.waitForFilenames(["f0.jsonl", "f1.jsonl", "f2.jsonl"], timeout: 5))
    watcher.stop()
}

@Test func recursiveWatcherStopEmitsNoMoreEvents() throws {
    let root = try makeWatchRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let collector = PathBatchCollector()
    let watcher = RecursiveFileEventWatcher { batch in
        collector.append(batch)
    }
    watcher.start(paths: [root.path])
    Thread.sleep(forTimeInterval: 0.3)

    try Data("x".utf8).write(to: root.appendingPathComponent("a.jsonl", isDirectory: false))
    #expect(collector.waitForPath(containing: "a.jsonl", timeout: 5))

    watcher.stop()
    let countBefore = collector.batchCount

    try Data("y".utf8).write(to: root.appendingPathComponent("b.jsonl", isDirectory: false))
    #expect(collector.waitForBatchCountGreater(than: countBefore, timeout: 0.8) == false)

    watcher.stop()
}

@Test func recursiveWatcherStartsWithMissingRootsAndRecovers() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let collector = PathBatchCollector()
    let watcher = RecursiveFileEventWatcher { batch in
        collector.append(batch)
    }
    watcher.start(paths: [root.path])
    #expect(watcher.isActive == false)

    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    #expect(waitForTrue({ watcher.isActive }, timeout: 5))

    let file = root.appendingPathComponent("recovered.jsonl", isDirectory: false)
    try Data("x".utf8).write(to: file)
    #expect(collector.waitForPath(containing: "recovered.jsonl", timeout: 5))

    watcher.stop()
}

private func makeWatchRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func waitForTrue(_ condition: @escaping () -> Bool, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if condition() { return true }
        if Date() >= deadline { return false }
        Thread.sleep(forTimeInterval: 0.05)
    }
}

final class PathBatchCollector: @unchecked Sendable {
    private let lock = NSLock()
    private let condition = NSCondition()
    private var batches: [[String]] = []
    private var allPaths: Set<String> = []

    func append(_ paths: [String]) {
        lock.lock()
        batches.append(paths)
        allPaths.formUnion(paths)
        lock.unlock()
        condition.lock()
        condition.broadcast()
        condition.unlock()
    }

    var batchCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return batches.count
    }

    private func snapshotAllPaths() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return allPaths
    }

    func waitForPath(containing fragment: String, timeout: TimeInterval, distinctFrom minBatchCount: Int = 0) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let paths = snapshotAllPaths()
            let found = paths.contains { $0.contains(fragment) }
            if found, batchCount > minBatchCount {
                return true
            }
            if Date() >= deadline { return false }
            condition.lock()
            condition.wait(until: Date().addingTimeInterval(0.05))
            condition.unlock()
        }
    }

    func waitForAllPaths(_ expected: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        let expectedSet = Set(expected)
        while true {
            if expectedSet.isSubset(of: snapshotAllPaths()) {
                return true
            }
            if Date() >= deadline { return false }
            condition.lock()
            condition.wait(until: Date().addingTimeInterval(0.05))
            condition.unlock()
        }
    }

    func waitForFilenames(_ filenames: [String], timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let paths = snapshotAllPaths()
            let matched = filenames.allSatisfy { name in
                paths.contains { $0.hasSuffix("/\(name)") }
            }
            if matched { return true }
            if Date() >= deadline { return false }
            condition.lock()
            condition.wait(until: Date().addingTimeInterval(0.05))
            condition.unlock()
        }
    }

    func waitForBatchCountGreater(than count: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if batchCount > count { return true }
            if Date() >= deadline { return false }
            condition.lock()
            condition.wait(until: Date().addingTimeInterval(0.05))
            condition.unlock()
        }
    }
}