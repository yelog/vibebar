import Foundation
import Testing
@testable import VibeBarApp

final class CoordinatorSchedulerSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [(@MainActor @Sendable () -> Void)] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return recorded.count
    }

    func record(_ action: @escaping @MainActor @Sendable () -> Void) {
        lock.lock()
        recorded.append(action)
        lock.unlock()
    }

    @MainActor
    func fireAll() {
        lock.lock()
        let actions = recorded
        recorded.removeAll()
        lock.unlock()
        for action in actions {
            action()
        }
    }
}

@Test @MainActor func refreshTriggerCoordinatorCoalescesEventBurstIntoOneRefresh() {
    let scheduler = CoordinatorSchedulerSpy()
    var reasons: [MonitorRefreshReason] = []
    let coordinator = RefreshTriggerCoordinator(
        scheduler: { [scheduler] _, action in scheduler.record(action) },
        onRefresh: { reasons.append($0) }
    )

    for _ in 0..<10 {
        coordinator.requestEvent()
    }
    #expect(reasons.isEmpty)
    #expect(scheduler.count == 1)

    scheduler.fireAll()
    #expect(reasons == [.event])
}

@Test @MainActor func refreshTriggerCoordinatorEventsDuringRefreshProduceOnePendingRefresh() {
    let scheduler = CoordinatorSchedulerSpy()
    var reasons: [MonitorRefreshReason] = []
    let coordinator = RefreshTriggerCoordinator(
        scheduler: { [scheduler] _, action in scheduler.record(action) },
        onRefresh: { reasons.append($0) }
    )

    coordinator.requestEvent()
    scheduler.fireAll()
    #expect(reasons == [.event])

    for _ in 0..<5 {
        coordinator.requestEvent()
    }
    #expect(reasons.count == 1)
    scheduler.fireAll()
    #expect(reasons.count == 2)
}

@Test @MainActor func refreshTriggerCoordinatorManualRefreshIsNotDelayed() {
    let scheduler = CoordinatorSchedulerSpy()
    var reasons: [MonitorRefreshReason] = []
    let coordinator = RefreshTriggerCoordinator(
        scheduler: { [scheduler] _, action in scheduler.record(action) },
        onRefresh: { reasons.append($0) }
    )

    coordinator.requestEvent()
    coordinator.requestManual()

    #expect(reasons == [.manual])
    scheduler.fireAll()
    #expect(reasons == [.manual])
}

@Test @MainActor func refreshTriggerCoordinatorWakeCancelsPendingAndEmitsWake() {
    let scheduler = CoordinatorSchedulerSpy()
    var reasons: [MonitorRefreshReason] = []
    let coordinator = RefreshTriggerCoordinator(
        scheduler: { [scheduler] _, action in scheduler.record(action) },
        onRefresh: { reasons.append($0) }
    )

    coordinator.requestEvent()
    coordinator.requestWake()

    #expect(reasons == [.wake])
    scheduler.fireAll()
    #expect(reasons == [.wake])
}

@Test @MainActor func refreshTriggerCoordinatorStopPreventsFurtherCallbacks() {
    let scheduler = CoordinatorSchedulerSpy()
    var reasons: [MonitorRefreshReason] = []
    let coordinator = RefreshTriggerCoordinator(
        scheduler: { [scheduler] _, action in scheduler.record(action) },
        onRefresh: { reasons.append($0) }
    )

    coordinator.stop()
    coordinator.requestEvent()
    coordinator.requestManual()
    coordinator.requestWake()
    scheduler.fireAll()

    #expect(reasons.isEmpty)
    #expect(scheduler.count == 0)
}