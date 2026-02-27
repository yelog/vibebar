import Foundation

/// Composite detector that merges results from multiple specialized detectors
/// Priority: HTTP API > Log File > Process Scan
public struct CompositeSessionDetector: AgentDetector {
    private let detectors: [AgentDetector]

    public init(detectors: [AgentDetector]? = nil) {
        self.detectors = detectors ?? CompositeSessionDetector.defaultDetectors()
    }

    /// Default detector chain with all available detectors
    public static func defaultDetectors() -> [AgentDetector] {
        [
            OpenCodeHTTPDetector(),    // Highest accuracy for OpenCode
            ClaudeLogDetector(),       // High accuracy for Claude
            CopilotServerDetector(),   // JSON-RPC server for GitHub Copilot (best accuracy)
            CopilotHookDetector(),     // Hook files for GitHub Copilot (good accuracy)
            GeminiTranscriptDetector(),
            ProcessScanner(),          // Fallback for all tools
        ]
    }

    /// Detect sessions using all detectors and merge results
    public func detectSessions() -> [SessionSnapshot] {
        var allSessions: [SessionSnapshot] = []

        // Collect sessions from all detectors
        for detector in detectors {
            let sessions = detector.detectSessions()
            allSessions.append(contentsOf: sessions)
        }

        // Deduplicate and merge: prefer higher priority sources
        return mergeAndDeduplicate(sessions: allSessions)
    }

    // MARK: - Private

    /// Merge sessions from multiple sources, keeping the most accurate one per process
    private func mergeAndDeduplicate(sessions: [SessionSnapshot]) -> [SessionSnapshot] {
        // Group by (tool, pid) pair
        var grouped: [String: [SessionSnapshot]] = [:]

        for session in sessions {
            let key = "\(session.tool.rawValue)-\(session.pid)"
            grouped[key, default: []].append(session)
        }

        // For each group, select the best session
        var result: [SessionSnapshot] = []

        for (_, group) in grouped {
            guard let best = selectBest(from: group) else { continue }
            result.append(best)
        }

        return result
    }

    /// Select the best session from a group (same tool + pid)
    /// Priority order: HTTP API > Log File > Process Scan
    private func selectBest(from sessions: [SessionSnapshot]) -> SessionSnapshot? {
        guard !sessions.isEmpty else { return nil }

        // Priority mapping based on session ID prefix and notes
        func priority(of session: SessionSnapshot) -> Int {
            // HTTP API sources have highest priority
            if session.id.hasPrefix("opencode-http-") {
                return 5
            }
            if session.id.hasPrefix("claude-log-") {
                return 4
            }
            if session.id.hasPrefix("copilot-server-") {
                return 3
            }
            if session.id.hasPrefix("copilot-hook-") {
                return 2
            }
            if session.id.hasPrefix("gemini-transcript-") {
                return 2
            }
            // Process scan fallback
            if session.id.hasPrefix("ps-") {
                return 1
            }
            return 0
        }

        // Select session with highest priority
        // If tie, prefer the one with more detailed info (cwd, etc.)
        return sessions.max { a, b in
            let prioA = priority(of: a)
            let prioB = priority(of: b)

            if prioA != prioB {
                return prioA < prioB
            }

            // Same priority: prefer more complete metadata
            let scoreA = (a.cwd != nil ? 1 : 0) + (a.lastOutputAt != nil ? 1 : 0)
            let scoreB = (b.cwd != nil ? 1 : 0) + (b.lastOutputAt != nil ? 1 : 0)
            return scoreA < scoreB
        }
    }
}
