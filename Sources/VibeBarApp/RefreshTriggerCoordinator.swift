import Foundation

/// Coalesces refresh triggers into a single debounced refresh request.
///
/// File-system and notification events are batched through one debounce task;
/// only one `.event` refresh is emitted per burst. Manual and wake refreshes
/// bypass the debounce and are emitted immediately, cancelling any pending
/// event refresh. Filesystem watchers must not call the model directly —
/// they go through this coordinator.
@MainActor
final class RefreshTriggerCoordinator {
    typealias Scheduler = @Sendable (
        Duration,
        @escaping @MainActor @Sendable () -> Void
    ) -> Void

    private let debounceInterval: Duration
    private let scheduler: Scheduler
    private let onRefresh: @MainActor (MonitorRefreshReason) -> Void

    /// Monotonic generation used to invalidate stale scheduled actions after a
    /// cancel or `stop()`.
    private var generation = 0
    private var pendingEvent = false
    private var debounceScheduled = false
    private var isStopped = false

    init(
        debounceInterval: Duration = .milliseconds(250),
        scheduler: @escaping Scheduler = RefreshTriggerCoordinator.defaultScheduler,
        onRefresh: @escaping @MainActor (MonitorRefreshReason) -> Void
    ) {
        self.debounceInterval = debounceInterval
        self.scheduler = scheduler
        self.onRefresh = onRefresh
    }

    /// Requests an event-driven refresh (file/setting changes). Bursts are
    /// coalesced into one refresh after the debounce window.
    func requestEvent() {
        guard !isStopped else { return }
        pendingEvent = true
        guard !debounceScheduled else { return }
        debounceScheduled = true
        scheduleDebounce()
    }

    /// Periodic reconciliation ticks are already throttled by the timer.
    func requestPeriodic() {
        guard !isStopped else { return }
        cancelPendingEvent()
        onRefresh(.periodic)
    }

    /// User-initiated refresh, never delayed by the debounce.
    func requestManual() {
        guard !isStopped else { return }
        cancelPendingEvent()
        onRefresh(.manual)
    }

    /// Wake reconciliation, never delayed; cancels any pending event refresh.
    func requestWake() {
        guard !isStopped else { return }
        cancelPendingEvent()
        onRefresh(.wake)
    }

    /// Prevents further callbacks and cancels any pending debounce.
    func stop() {
        isStopped = true
        cancelPendingEvent()
    }

    private func scheduleDebounce() {
        generation += 1
        let currentGeneration = generation
        scheduler(debounceInterval) { [weak self] in
            guard let self else { return }
            self.debounceScheduled = false
            guard !self.isStopped,
                  currentGeneration == self.generation else {
                return
            }
            guard self.pendingEvent else { return }
            self.pendingEvent = false
            self.onRefresh(.event)
        }
    }

    private func cancelPendingEvent() {
        generation += 1
        pendingEvent = false
        debounceScheduled = false
    }

    private nonisolated static func defaultScheduler(
        _ duration: Duration,
        _ action: @escaping @MainActor @Sendable () -> Void
    ) {
        Task { @MainActor in
            do {
                try await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                action()
            } catch {
                // Cancelled or interrupted.
            }
        }
    }
}