import Foundation
import Testing
@testable import VibeBarApp

@Test func notchAutoExpandHoldWindowRemainsActiveBeforeDeadline() {
    var holdWindow = NotchAutoExpandHoldWindow(duration: 3)
    let start = Date(timeIntervalSince1970: 100)

    let holdUntil = holdWindow.begin(now: start)

    #expect(holdUntil == start.addingTimeInterval(3))
    #expect(holdWindow.isActive(now: start.addingTimeInterval(2.9)))
}

@Test func notchAutoExpandHoldWindowExpiresAtDeadline() {
    var holdWindow = NotchAutoExpandHoldWindow(duration: 3)
    let start = Date(timeIntervalSince1970: 100)
    _ = holdWindow.begin(now: start)

    #expect(holdWindow.isActive(now: start.addingTimeInterval(3)) == false)
    #expect(holdWindow.isActive(now: start.addingTimeInterval(4)) == false)
}
