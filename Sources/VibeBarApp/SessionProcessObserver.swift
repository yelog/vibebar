import Foundation

/// Observes exit of known session processes so state can refresh promptly
/// without waiting for the reconciliation timer.
///
/// `DispatchSourceProcess` fires once when a watched PID exits. Exit events
/// only request a refresh — they never mutate sessions directly. PID zero and
/// negative PIDs are ignored.
actor SessionProcessObserver {
    private let onExit: @MainActor (Int32) -> Void
    private let queue = DispatchQueue(label: "com.vibebar.process-observer")
    private var sourcesByPID: [Int32: DispatchSourceProcess] = [:]

    init(onExit: @escaping @MainActor (Int32) -> Void) {
        self.onExit = onExit
    }

    /// Registers a process source for each positive PID not already watched.
    func register(pids: Set<Int32>) {
        for pid in pids where pid > 0 && sourcesByPID[pid] == nil {
            let source = DispatchSource.makeProcessSource(
                identifier: pid,
                eventMask: [.exit],
                queue: queue
            )
            source.setEventHandler { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.handleExit(pid: pid)
                }
            }
            sourcesByPID[pid] = source
            source.resume()
        }
    }

    /// Removes process sources for the given PIDs.
    func unregister(pids: Set<Int32>) {
        for pid in pids {
            sourcesByPID.removeValue(forKey: pid)?.cancel()
        }
    }

    /// Cancels all process sources.
    func stop() {
        for source in sourcesByPID.values {
            source.cancel()
        }
        sourcesByPID.removeAll()
    }

    /// Number of currently registered process sources (test observation).
    var registeredPIDCount: Int {
        sourcesByPID.count
    }

    private func handleExit(pid: Int32) async {
        sourcesByPID.removeValue(forKey: pid)?.cancel()
        await MainActor.run {
            self.onExit(pid)
        }
    }
}