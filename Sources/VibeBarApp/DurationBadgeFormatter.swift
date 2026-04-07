import Foundation
import VibeBarCore

enum DurationBadgeFormatter {
    static func string(for session: SessionSnapshot, now: Date) -> String {
        let seconds = Int(now.timeIntervalSince(session.currentStatusSince))

        if seconds < 60 {
            return "\(seconds)s"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours < 24 {
            if remainingMinutes > 0 {
                return "\(hours)h\(remainingMinutes)m"
            }
            return "\(hours)h"
        }

        let days = hours / 24
        let remainingHours = hours % 24
        if remainingHours > 0 {
            return "\(days)d\(remainingHours)h"
        }
        return "\(days)d"
    }
}