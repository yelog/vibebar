import Foundation
import Testing
@testable import VibeBarCore

@Test func directoryChangeWatcherEmitsOnFileCreate() throws {
    let directory = try makeWatchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let signal = SignalCounter()
    let watcher = DirectoryChangeWatcher {
        signal.bump()
    }
    watcher.start(path: directory.path)

    try Data("x".utf8).write(to: directory.appendingPathComponent("a.json"))
    #expect(signal.waitForCount(1, timeout: 5))

    watcher.stop()
}

@Test func directoryChangeWatcherEmitsOnAtomicReplacement() throws {
    let directory = try makeWatchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let signal = SignalCounter()
    let watcher = DirectoryChangeWatcher {
        signal.bump()
    }
    watcher.start(path: directory.path)

    let temp = directory.appendingPathComponent("session.tmp")
    let destination = directory.appendingPathComponent("session.json")
    try Data("payload".utf8).write(to: temp)
    try FileManager.default.moveItem(at: temp, to: destination)
    #expect(signal.waitForCount(1, timeout: 5))

    watcher.stop()
}

@Test func directoryChangeWatcherEmitsOnRenameIntoDirectory() throws {
    let directory = try makeWatchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let signal = SignalCounter()
    let watcher = DirectoryChangeWatcher {
        signal.bump()
    }
    watcher.start(path: directory.path)

    let outside = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: false)
    try Data("payload".utf8).write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }

    try FileManager.default.moveItem(
        at: outside,
        to: directory.appendingPathComponent("renamed.json")
    )
    #expect(signal.waitForCount(1, timeout: 5))

    watcher.stop()
}

@Test func directoryChangeWatcherEmitsOnDelete() throws {
    let directory = try makeWatchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let signal = SignalCounter()
    let watcher = DirectoryChangeWatcher {
        signal.bump()
    }
    watcher.start(path: directory.path)

    let fileURL = directory.appendingPathComponent("to-delete.json")
    try Data("x".utf8).write(to: fileURL)
    #expect(signal.waitForCount(1, timeout: 5))

    try FileManager.default.removeItem(at: fileURL)
    #expect(signal.waitForCount(2, timeout: 5))

    watcher.stop()
}

@Test func directoryChangeWatcherStopEmitsNoMoreEvents() throws {
    let directory = try makeWatchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let signal = SignalCounter()
    let watcher = DirectoryChangeWatcher {
        signal.bump()
    }
    watcher.start(path: directory.path)

    try Data("x".utf8).write(to: directory.appendingPathComponent("a.json"))
    #expect(signal.waitForCount(1, timeout: 5))

    watcher.stop()

    try Data("y".utf8).write(to: directory.appendingPathComponent("b.json"))
    #expect(signal.waitForCount(2, timeout: 0.6) == false)
}

@Test func directoryChangeWatcherRequestsReconciliationOnDeletionAndRecovers() throws {
    let directory = try makeWatchDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }

    let signal = SignalCounter()
    let watcher = DirectoryChangeWatcher {
        signal.bump()
    }
    watcher.start(path: directory.path)
    #expect(watcher.isActive)

    try FileManager.default.removeItem(at: directory)
    #expect(signal.waitForCount(1, timeout: 5))
    #expect(watcher.isActive == false)

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    #expect(waitForTrue({ watcher.isActive }, timeout: 5))

    try Data("x".utf8).write(to: directory.appendingPathComponent("recovered.json"))
    #expect(signal.waitForCount(2, timeout: 5))

    watcher.stop()
}

@Test func directoryChangeWatcherStartsWithMissingDirectoryAndRecovers() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let signal = SignalCounter()
    let watcher = DirectoryChangeWatcher {
        signal.bump()
    }
    watcher.start(path: directory.path)
    #expect(watcher.isActive == false)

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    #expect(waitForTrue({ watcher.isActive }, timeout: 5))

    try Data("x".utf8).write(to: directory.appendingPathComponent("a.json"))
    #expect(signal.waitForCount(1, timeout: 5))

    watcher.stop()
}

private func waitForTrue(_ condition: @escaping () -> Bool, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if condition() { return true }
        if Date() >= deadline { return false }
        Thread.sleep(forTimeInterval: 0.05)
    }
}

private func makeWatchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

final class SignalCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let condition = NSCondition()

    func bump() {
        lock.lock()
        count += 1
        lock.unlock()
        condition.lock()
        condition.broadcast()
        condition.unlock()
    }

    var currentCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    /// Returns true when the observed count reaches `target` within `timeout`
    /// seconds. Drains all signals observed up to that point.
    func waitForCount(_ target: Int, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while currentCount < target {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { return false }
            condition.lock()
            condition.wait(until: Date().addingTimeInterval(min(remaining, 0.05)))
            condition.unlock()
        }
        return currentCount >= target
    }
}