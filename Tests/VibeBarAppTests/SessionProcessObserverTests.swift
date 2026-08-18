import Foundation
import Testing
@testable import VibeBarApp

final class ExitRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var pids: [Int32] = []

    func record(_ pid: Int32) {
        lock.lock()
        pids.append(pid)
        lock.unlock()
    }

    func waitForCount(_ target: Int, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if recordedPIDs.count >= target { return true }
            if Date() >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    var recordedPIDs: [Int32] {
        lock.lock()
        defer { lock.unlock() }
        return pids
    }
}

@Test @MainActor func processObserverReportsSingleExit() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["0.2"]
    try process.run()
    let pid = process.processIdentifier

    let recorder = ExitRecorder()
    let observer = SessionProcessObserver { pid in
        recorder.record(pid)
    }
    await observer.register(pids: [pid])

    #expect(await observer.registeredPIDCount == 1)
    let received = await recorder.waitForCount(1, timeout: 5)
    #expect(received)
    #expect(recorder.recordedPIDs == [pid])

    await observer.stop()
}

@Test @MainActor func processObserverDuplicateRegistrationCreatesOneSource() async {
    let observer = SessionProcessObserver { _ in }

    await observer.register(pids: [42, 42])
    await observer.register(pids: [42])

    #expect(await observer.registeredPIDCount == 1)
    await observer.stop()
}

@Test @MainActor func processObserverIgnoresZeroPID() async {
    let observer = SessionProcessObserver { _ in }

    await observer.register(pids: [0, -1])
    await observer.register(pids: [0])

    #expect(await observer.registeredPIDCount == 0)
    await observer.stop()
}

@Test @MainActor func processObserverUnregisterCancelsSource() async {
    let observer = SessionProcessObserver { _ in }

    await observer.register(pids: [42, 43])
    #expect(await observer.registeredPIDCount == 2)

    await observer.unregister(pids: [42])
    #expect(await observer.registeredPIDCount == 1)

    await observer.stop()
    #expect(await observer.registeredPIDCount == 0)
}