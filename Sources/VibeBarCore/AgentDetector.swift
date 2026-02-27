import Foundation

/// Protocol for agent-specific session detectors
public protocol AgentDetector: Sendable {
    /// Detect active sessions for specific tools
    func detectSessions() -> [SessionSnapshot]
}

/// Detection source with priority (higher = more reliable)
public enum DetectionSource: String, Codable, Sendable {
    case httpAPI = "http_api"      // Highest priority: real-time HTTP API
    case logFile = "log_file"      // High priority: parsed from logs
    case processScan = "process_scan" // Fallback: ps command
}

/// Priority order for deduplication (higher number = higher priority)
extension DetectionSource {
    var priority: Int {
        switch self {
        case .httpAPI: return 3
        case .logFile: return 2
        case .processScan: return 1
        }
    }
}
