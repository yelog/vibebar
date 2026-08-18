import CoreServices
import Foundation

/// Recursive filesystem watcher backed by FSEvents.
///
/// Watches a set of roots recursively and reports batches of affected paths on
/// a dedicated serial queue. Only a signal is forwarded — callers decide what
/// to do with the paths. Lifecycle is explicit: `start(paths:)`, `stop()`, and
/// deinit cleanup.
///
/// When the watched roots are missing or the event stream fails to start, the
/// watcher retries with bounded exponential backoff (1 s initial, capped at
/// 60 s). A successful start resets the backoff.
public final class RecursiveFileEventWatcher: @unchecked Sendable {
    private let queue: DispatchQueue
    private let onChange: @Sendable ([String]) -> Void
    private let lock = NSLock()
    private var stream: FSEventStreamRef?
    private var retryTimer: DispatchSourceTimer?
    private var watchedPaths: [String] = []
    private var retryDelay: TimeInterval = 1
    private var isWatching = false

    public init(
        queue: DispatchQueue = DispatchQueue(label: "com.vibebar.recursive-watcher"),
        onChange: @escaping @Sendable ([String]) -> Void
    ) {
        self.queue = queue
        self.onChange = onChange
    }

    /// Starts watching `paths` (only existing roots are watched). Restarting
    /// with new paths replaces the previous stream.
    public func start(paths: [String]) {
        lock.lock()
        watchedPaths = paths
        stopLocked()
        lock.unlock()

        let existingPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existingPaths.isEmpty else {
            scheduleRetry()
            return
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            RecursiveFileEventWatcher.callback,
            &context,
            existingPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )

        lock.lock()
        self.stream = stream
        lock.unlock()

        guard let stream else {
            scheduleRetry()
            return
        }
        FSEventStreamSetDispatchQueue(stream, queue)
        if FSEventStreamStart(stream) {
            lock.lock()
            retryDelay = 1
            isWatching = true
            lock.unlock()
        } else {
            lock.lock()
            self.stream = nil
            lock.unlock()
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            scheduleRetry()
        }
    }

    public func stop() {
        lock.lock()
        stopLocked()
        lock.unlock()
    }

    /// True when the watcher currently holds a running event stream.
    public var isActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isWatching
    }

    deinit {
        lock.lock()
        stopLocked()
        lock.unlock()
    }

    private func stopLocked() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
        retryTimer?.cancel()
        retryTimer = nil
        isWatching = false
    }

    /// Retries starting the stream after the current backoff delay. Repeated
    /// failures double the delay up to a 60-second cap.
    private func scheduleRetry() {
        lock.lock()
        let paths = watchedPaths
        let delay = retryDelay
        retryDelay = min(retryDelay * 2, 60)
        retryTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + delay)
        timer.setEventHandler { [weak self] in
            self?.retryNow()
        }
        retryTimer = timer
        lock.unlock()

        guard !paths.isEmpty else { return }
        timer.resume()
    }

    private func retryNow() {
        lock.lock()
        let paths = watchedPaths
        lock.unlock()
        guard !paths.isEmpty else { return }
        start(paths: paths)
    }

    /// C callback invoked by FSEvents on the dispatch queue. Uses the context
    /// `info` pointer to reach the watcher instance, then converts the raw
    /// path pointers into a `Sendable` `[String]` batch before dispatching.
    private static let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
        guard let info, numEvents > 0 else { return }
        let watcher = Unmanaged<RecursiveFileEventWatcher>.fromOpaque(info).takeUnretainedValue()

        var batch: [String] = []
        batch.reserveCapacity(numEvents)
        let pathsPointer = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>?.self)
        for index in 0..<numEvents {
            guard let cString = pathsPointer[index] else { continue }
            batch.append(String(cString: cString))
        }
        watcher.dispatch(paths: batch)
    }

    private func dispatch(paths: [String]) {
        onChange(paths)
    }
}