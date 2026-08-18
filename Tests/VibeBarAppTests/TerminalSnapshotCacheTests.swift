import Foundation
import Testing
import VibeBarCore
@testable import VibeBarApp

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var _now: Date

    init(_ now: Date = Date(timeIntervalSince1970: 1_700_000_000)) {
        self._now = now
    }

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        _now = _now.addingTimeInterval(seconds)
        lock.unlock()
    }
}

final class LoaderCounter: @unchecked Sendable {
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

@Test func terminalSnapshotCacheHitsWithinTTL() async {
    let clock = TestClock()
    let counter = LoaderCounter()
    let cache = TerminalSnapshotCache(clock: { clock.now })
    let key = TerminalSnapshotKey(kind: .kitty, address: "unix:/tmp/kitty")

    let first = await cache.value(for: key) {
        counter.increment()
        return "output-1"
    }
    let second = await cache.value(for: key) {
        counter.increment()
        return "output-2"
    }

    #expect(first == "output-1")
    #expect(second == "output-1")
    #expect(counter.count == 1)
}

@Test func terminalSnapshotCacheExpiresAfterPositiveTTL() async {
    let clock = TestClock()
    let counter = LoaderCounter()
    let cache = TerminalSnapshotCache(positiveTTL: 15, clock: { clock.now })
    let key = TerminalSnapshotKey(kind: .wezterm, address: "sock")

    _ = await cache.value(for: key) {
        counter.increment()
        return "a"
    }
    clock.advance(by: 16)
    let second = await cache.value(for: key) {
        counter.increment()
        return "b"
    }

    #expect(second == "b")
    #expect(counter.count == 2)
}

@Test func terminalSnapshotCacheNegativeCachingUsesShorterTTL() async {
    let clock = TestClock()
    let counter = LoaderCounter()
    let cache = TerminalSnapshotCache(positiveTTL: 15, negativeTTL: 5, clock: { clock.now })
    let key = TerminalSnapshotKey(kind: .iterm, address: "")

    let first = await cache.value(for: key) {
        counter.increment()
        return nil
    }
    #expect(first == nil)

    let second = await cache.value(for: key) {
        counter.increment()
        return "x"
    }
    #expect(second == nil)
    #expect(counter.count == 1)

    clock.advance(by: 6)
    let third = await cache.value(for: key) {
        counter.increment()
        return "y"
    }
    #expect(third == "y")
    #expect(counter.count == 2)
}

@Test func terminalSnapshotCacheClearInvalidatesEntries() async {
    let clock = TestClock()
    let counter = LoaderCounter()
    let cache = TerminalSnapshotCache(clock: { clock.now })
    let key = TerminalSnapshotKey(kind: .ghostty, address: "")

    _ = await cache.value(for: key) {
        counter.increment()
        return "a"
    }
    await cache.clear()
    let second = await cache.value(for: key) {
        counter.increment()
        return "b"
    }

    #expect(second == "b")
    #expect(counter.count == 2)
}

@Test func terminalSnapshotCacheCoalescesConcurrentRequests() async {
    let clock = TestClock()
    let counter = LoaderCounter()
    let cache = TerminalSnapshotCache(clock: { clock.now })
    let key = TerminalSnapshotKey(kind: .tmux, address: "/tmp/tmux|%0")

    async let a = cache.value(for: key) {
        counter.increment()
        return "a"
    }
    async let b = cache.value(for: key) {
        counter.increment()
        return "b"
    }
    let results = await [a, b]

    #expect(results.allSatisfy { $0 == "a" })
    #expect(counter.count == 1)
}

@Test func terminalSnapshotCacheBoundsEntryCount() async {
    let clock = TestClock()
    let counter = LoaderCounter()
    let cache = TerminalSnapshotCache(maxEntries: 3, clock: { clock.now })

    for i in 0..<5 {
        let key = TerminalSnapshotKey(kind: .kitty, address: "addr-\(i)")
        _ = await cache.value(for: key) {
            counter.increment()
            return "o-\(i)"
        }
    }

    #expect(await cache.count <= 3)
    #expect(counter.count == 5)
}