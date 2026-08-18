import Foundation
import os

/// Named energy-relevant operations that can be counted for diagnostics.
public enum EnergyOperation: String, Sendable {
    case modelRefresh
    case processSnapshot
    case cwdLookup
    case environmentLookup
    case terminalSnapshot
    case transcriptParse
    case fullscreenCheck
}

/// Lock-protected in-memory counters for energy-relevant operations.
///
/// The production `shared` instance only records counts and OSLog signposts
/// when `VIBEBAR_ENERGY_DIAGNOSTICS=1`. Tests inject isolated instances that
/// are always active, so they do not depend on process environment variables.
public final class EnergyDiagnostics: @unchecked Sendable {
    public static let shared = EnergyDiagnostics(
        enabled: ProcessInfo.processInfo.environment["VIBEBAR_ENERGY_DIAGNOSTICS"] == "1"
    )

    private let lock = NSLock()
    private var counts: [EnergyOperation: Int] = [:]
    private let enabled: Bool
    private let log = OSLog(subsystem: "com.vibebar.VibeBar", category: "EnergyDiagnostics")

    public init(enabled: Bool = true) {
        self.enabled = enabled
    }

    public func record(_ operation: EnergyOperation) {
        guard enabled else { return }

        lock.lock()
        counts[operation, default: 0] += 1
        lock.unlock()

        os_signpost(.event, log: log, name: Self.signpostName(for: operation))
    }

    private static func signpostName(for operation: EnergyOperation) -> StaticString {
        switch operation {
        case .modelRefresh: return "modelRefresh"
        case .processSnapshot: return "processSnapshot"
        case .cwdLookup: return "cwdLookup"
        case .environmentLookup: return "environmentLookup"
        case .terminalSnapshot: return "terminalSnapshot"
        case .transcriptParse: return "transcriptParse"
        case .fullscreenCheck: return "fullscreenCheck"
        }
    }

    public func count(for operation: EnergyOperation) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return counts[operation] ?? 0
    }

    public func reset() {
        lock.lock()
        counts.removeAll()
        lock.unlock()
    }
}