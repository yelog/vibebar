import Foundation
import VibeBarCore

enum SessionDurationFormatter {
    static func string(startedAt: Date, now: Date) -> String {
        let elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
        let day = elapsed / 86_400
        let hour = (elapsed % 86_400) / 3_600
        let minute = (elapsed % 3_600) / 60
        let second = elapsed % 60

        if day > 0 {
            return "\(day)d \(hour)h"
        }
        if elapsed >= 3_600 {
            return String(format: "%d:%02d:%02d", hour, minute, second)
        }
        return String(format: "%02d:%02d", minute, second)
    }

    static func string(for session: SessionSnapshot, now: Date) -> String {
        string(startedAt: session.currentStatusSince, now: now)
    }
}
