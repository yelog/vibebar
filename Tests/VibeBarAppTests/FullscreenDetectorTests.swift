import AppKit
import Foundation
import Testing
@testable import VibeBarApp

@MainActor
final class DetectionSpy {
    var calls = 0
    var result = false
    func detect() -> Bool {
        calls += 1
        return result
    }
}

final class SchedulerSpy: @unchecked Sendable {
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

@MainActor
private func makeDetector(
    detection: DetectionSpy,
    scheduler: SchedulerSpy,
    center: NotificationCenter = NotificationCenter()
) -> FullscreenDetector {
    FullscreenDetector(
        detect: { [detection] in detection.detect() },
        notificationCenter: center,
        scheduler: { [scheduler] _, action in scheduler.record(action) }
    )
}

@Test @MainActor func fullscreenDetectorInitializationPerformsOneCheck() {
    let detection = DetectionSpy()
    let scheduler = SchedulerSpy()
    let detector = makeDetector(detection: detection, scheduler: scheduler)
    withExtendedLifetime(detector) {}

    #expect(detection.calls == 1)
    #expect(scheduler.count == 0)
}

@Test @MainActor func fullscreenDetectorSpaceChangePerformsImmediateAndDelayedCheck() {
    let detection = DetectionSpy()
    let scheduler = SchedulerSpy()
    let center = NotificationCenter()
    let detector = makeDetector(detection: detection, scheduler: scheduler, center: center)

    let before = detection.calls
    center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

    #expect(detection.calls == before + 1)
    #expect(scheduler.count == 1)

    scheduler.fireAll()
    #expect(detection.calls == before + 2)

    withExtendedLifetime(detector) {}
}

@Test @MainActor func fullscreenDetectorApplicationActivationPerformsOneCheck() {
    let detection = DetectionSpy()
    let scheduler = SchedulerSpy()
    let center = NotificationCenter()
    let detector = makeDetector(detection: detection, scheduler: scheduler, center: center)

    let before = detection.calls
    center.post(name: NSWorkspace.didActivateApplicationNotification, object: nil)

    #expect(detection.calls == before + 1)
    #expect(scheduler.count == 0)

    withExtendedLifetime(detector) {}
}

@Test @MainActor func fullscreenDetectorIdleWithoutNotificationsDoesNotPoll() {
    let detection = DetectionSpy()
    let scheduler = SchedulerSpy()
    let detector = makeDetector(detection: detection, scheduler: scheduler)

    #expect(detection.calls == 1)
    #expect(scheduler.count == 0)

    withExtendedLifetime(detector) {}
}

@Test @MainActor func fullscreenDetectorStopRemovesObserversAndCancelsPendingActions() {
    let detection = DetectionSpy()
    let scheduler = SchedulerSpy()
    let center = NotificationCenter()
    let detector = makeDetector(detection: detection, scheduler: scheduler, center: center)

    center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    let callsAfterSpace = detection.calls
    #expect(scheduler.count == 1)

    detector.stop()

    center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
    #expect(detection.calls == callsAfterSpace)

    scheduler.fireAll()
    #expect(detection.calls == callsAfterSpace)
}

@Test @MainActor func fullscreenDetectorDebouncesStateChangesBeforePublishing() {
    let detection = DetectionSpy()
    let scheduler = SchedulerSpy()
    let center = NotificationCenter()
    let detector = makeDetector(detection: detection, scheduler: scheduler, center: center)

    detection.result = true
    center.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

    #expect(detector.isAnyAppInFullscreen == false)
    #expect(scheduler.count == 2)

    scheduler.fireAll()
    #expect(detector.isAnyAppInFullscreen == true)
}