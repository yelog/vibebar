import Foundation

/// Composite detector that merges results from multiple specialized detectors.
/// Priority: Plugin > HTTP API > Transcript > Process Scan.
public struct CompositeSessionDetector: AgentDetector {
    private let openCodeHTTPEnabled: Bool
    private let geminiTranscriptEnabled: Bool
    private let processScanTools: Set<ToolKind>

    public init(
        openCodeHTTPEnabled: Bool = true,
        geminiTranscriptEnabled: Bool = true,
        processScanTools: Set<ToolKind> = Set(ToolKind.allCases)
    ) {
        self.openCodeHTTPEnabled = openCodeHTTPEnabled
        self.geminiTranscriptEnabled = geminiTranscriptEnabled
        self.processScanTools = processScanTools
    }

    /// Creates a detector with configuration-aware detector chain.
    @MainActor
    public static func configured(excludingProcessScanTools excludedTools: Set<ToolKind> = []) -> CompositeSessionDetector {
        let manager = CLISettingsManager.shared

        let openCodeHTTPEnabled: Bool = {
            guard manager.isEnabled(.opencode) else { return false }
            let config = manager.configuration(for: .opencode)
            return config.enabledDetectionMethods.contains(.httpAPI)
        }()

        let geminiTranscriptEnabled: Bool = {
            guard manager.isEnabled(.gemini) else { return false }
            let config = manager.configuration(for: .gemini)
            return config.enabledDetectionMethods.contains(.transcriptFile)
        }()

        var processScanTools: Set<ToolKind> = []
        for tool in ToolKind.allCases where manager.isEnabled(tool) {
            let config = manager.configuration(for: tool)
            if config.enabledDetectionMethods.contains(.processScan) {
                processScanTools.insert(tool)
            }
        }
        processScanTools.subtract(excludedTools)

        return CompositeSessionDetector(
            openCodeHTTPEnabled: openCodeHTTPEnabled,
            geminiTranscriptEnabled: geminiTranscriptEnabled,
            processScanTools: processScanTools
        )
    }

    public func detectSessions() async -> [SessionSnapshot] {
        let context = DetectorSupport.makeContext()
        return await detectSessions(context: context)
    }

    func detectSessions(context: DetectorSupport.DetectionContext) async -> [SessionSnapshot] {
        var allSessions: [SessionSnapshot] = []
        var fallbackTools = processScanTools

        if openCodeHTTPEnabled {
            let sessions = await OpenCodeHTTPDetector().detectSessions(context: context)
            allSessions.append(contentsOf: sessions)
            if !sessions.isEmpty {
                fallbackTools.remove(.opencode)
            }
        }

        if geminiTranscriptEnabled {
            let sessions = await GeminiTranscriptDetector().detectSessions(context: context)
            allSessions.append(contentsOf: sessions)
            if !sessions.isEmpty {
                fallbackTools.remove(.gemini)
            }
        }

        if !fallbackTools.isEmpty {
            let sessions = await ProcessScanner(allowedTools: fallbackTools).scan(now: Date(), context: context)
            allSessions.append(contentsOf: sessions)
        }

        return mergeAndDeduplicate(sessions: allSessions)
    }

    // MARK: - Private

    /// Merge sessions from multiple sources, keeping the most accurate one per process.
    private func mergeAndDeduplicate(sessions: [SessionSnapshot]) -> [SessionSnapshot] {
        var grouped: [String: [SessionSnapshot]] = [:]

        for session in sessions {
            let key = "\(session.tool.rawValue)-\(session.pid)"
            grouped[key, default: []].append(session)
        }

        var result: [SessionSnapshot] = []

        for (_, group) in grouped {
            guard let best = selectBest(from: group) else { continue }
            result.append(best)
        }

        return result
    }

    private func selectBest(from sessions: [SessionSnapshot]) -> SessionSnapshot? {
        guard !sessions.isEmpty else { return nil }

        func priority(of session: SessionSnapshot) -> Int {
            if session.source == .plugin {
                return 6
            }
            if session.id.hasPrefix("opencode-http-") {
                return 5
            }
            if session.id.hasPrefix("claude-log-") {
                return 4
            }
            if session.id.hasPrefix("gemini-transcript-") {
                return 2
            }
            if session.id.hasPrefix("ps-") {
                return 1
            }
            return 0
        }

        return sessions.max { a, b in
            let prioA = priority(of: a)
            let prioB = priority(of: b)

            if prioA != prioB {
                return prioA < prioB
            }

            let scoreA = (a.cwd != nil ? 1 : 0) + (a.lastOutputAt != nil ? 1 : 0)
            let scoreB = (b.cwd != nil ? 1 : 0) + (b.lastOutputAt != nil ? 1 : 0)
            return scoreA < scoreB
        }
    }
}
