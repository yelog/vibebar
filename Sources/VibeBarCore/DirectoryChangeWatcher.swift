import Foundation

/// Watches a single directory for content changes using a kqueue-backed
/// `DispatchSourceFileSystemObject`.
///
/// The watcher emits only a change signal — it never reads or decodes files.
/// When the watched directory is missing or is replaced (deleted/renamed), the
/// watcher requests a reconciliation and retries with bounded exponential
/// backoff (1 s initial, capped at 60 s). A successful start resets the backoff.
public final class DirectoryChangeWatcher: @unchecked Sendable {
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private let lock = NSLock()
    private var source: DispatchSourceFileSystemObject?
    private var retryTimer: DispatchSourceTimer?
    private var directoryFD: Int32 = -1
    private var watchedPath: String?
    private var retryDelay: TimeInterval = 1
    private var isWatching = false

    public init(
        queue: DispatchQueue = DispatchQueue(label: "com.vibebar.directory-watcher"),
        onChange: @escaping @Sendable () -> Void
    ) {
        self.queue = queue
        self.onChange = onChange
    }

    public func start(path: String) {
        lock.lock()
        stopLocked()
        watchedPath = path
        directoryFD = open(path, O_EVTONLY)
        guard directoryFD >= 0 else {
            isWatching = false
            lock.unlock()
            scheduleRetry()
            return
        }
        retryDelay = 1
        isWatching = true

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFD,
            eventMask: [.write, .delete, .rename, .attrib],
            queue: queue
        )
        source.setEventHandler { [weak self] in
            let mask = DispatchSource.FileSystemEvent(rawValue: source.data)
            self?.handleEvent(mask: mask)
        }
        source.setCancelHandler { [weak self] in
            self?.closeDescriptor()
        }
        self.source = source
        lock.unlock()
        source.resume()
    }

    public func stop() {
        lock.lock()
        stopLocked()
        lock.unlock()
    }

    /// True when the watcher currently holds an open directory descriptor.
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
        source?.cancel()
        source = nil
        retryTimer?.cancel()
        retryTimer = nil
        watchedPath = nil
        isWatching = false
    }

    private func closeDescriptor() {
        lock.lock()
        if directoryFD >= 0 {
            close(directoryFD)
            directoryFD = -1
        }
        lock.unlock()
    }

    private func handleEvent(mask: DispatchSource.FileSystemEvent) {
        // The watched directory itself was replaced; try to reopen. If it is
        // still missing, the retry path keeps trying with backoff.
        if mask.contains(.delete) || mask.contains(.rename) {
            lock.lock()
            let path = watchedPath
            lock.unlock()
            if let path {
                start(path: path)
            }
        }
        onChange()
    }

    /// Retries opening the watched directory after the current backoff delay.
    /// Repeated failures double the delay up to a 60-second cap.
    private func scheduleRetry() {
        lock.lock()
        let path = watchedPath
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

        guard path != nil else { return }
        timer.resume()
    }

    private func retryNow() {
        lock.lock()
        let path = watchedPath
        lock.unlock()
        guard let path else { return }
        start(path: path)
    }
}