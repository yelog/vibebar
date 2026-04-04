import Foundation

/// Composite detector that merges results from multiple specialized detectors.
/// Priority: Plugin > HTTP API > Session File > Transcript > Process Scan.
public struct CompositeSessionDetector: AgentDetector {
    private let codexSessionEnabled: Bool
    private let openCodeHTTPEnabled: Bool
    private let geminiTranscriptEnabled: Bool
    private let processScanTools: Set<ToolKind>

    public init(
        codexSessionEnabled: Bool = true,
        openCodeHTTPEnabled: Bool = true,
        geminiTranscriptEnabled: Bool = true,
        processScanTools: Set<ToolKind> = Set(ToolKind.allCases)
    ) {
        self.codexSessionEnabled = codexSessionEnabled
        self.openCodeHTTPEnabled = openCodeHTTPEnabled
        self.geminiTranscriptEnabled = geminiTranscriptEnabled
        self.processScanTools = processScanTools
    }

    /// Creates a detector with configuration-aware detector chain.
    @MainActor
    public static func configured(excludingProcessScanTools excludedTools: Set<ToolKind> = []) -> CompositeSessionDetector {
        let manager = CLISettingsManager.shared

        let codexSessionEnabled: Bool = {
            guard manager.isEnabled(.codex) else { return false }
            let config = manager.configuration(for: .codex)
            return config.enabledDetectionMethods.contains(.sessionFile)
        }()

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
            codexSessionEnabled: codexSessionEnabled,
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

        if codexSessionEnabled {
            let sessions = await CodexSessionDetector().detectSessions(context: context)
            allSessions.append(contentsOf: sessions)
            if !sessions.isEmpty {
                fallbackTools.remove(.codex)
            }
        }

        if openCodeHTTPEnabled {
            let sessions = await OpenCodeHTTPDetector().detectSessions(context: context)
            allSessions.append(contentsOf: sessions)
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
            let key = session.pid > 0 ? "\(session.tool.rawValue)-\(session.pid)" : session.id
            grouped[key, default: []].append(session)
        }

        var result: [SessionSnapshot] = []

        for (_, group) in grouped {
            guard let best = mergeGroup(group) else { continue }
            result.append(best)
        }

        return result
    }

    func mergeGroup(_ sessions: [SessionSnapshot]) -> SessionSnapshot? {
        guard let best = selectBest(from: sessions) else { return nil }

        let richestContext = sessions.first { $0.terminalContext != nil }?.terminalContext
        let richestTitle = sessions.first { value in
            guard let title = value.title?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !title.isEmpty
        }?.title
        let richestTask = sessions.first { value in
            guard let task = value.currentTask?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !task.isEmpty
        }?.currentTask
        let richestNotes = sessions.first { value in
            guard let notes = value.notes?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !notes.isEmpty
        }?.notes

        var merged = best
        merged.terminalContext = TerminalContextResolver.merge(
            primary: best.terminalContext,
            fallback: richestContext
        )
        if merged.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            merged.title = richestTitle
        }
        if merged.currentTask?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            merged.currentTask = richestTask
        }
        if merged.notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            merged.notes = richestNotes
        }
        return merged
    }

    func selectBest(from sessions: [SessionSnapshot]) -> SessionSnapshot? {
        guard !sessions.isEmpty else { return nil }

        func priority(of session: SessionSnapshot) -> Int {
            if session.source == .plugin {
                return 6
            }
            if session.id.hasPrefix("opencode-http-") {
                return 5
            }
            if session.source == .sessionFile || session.id.hasPrefix("codex-session-") {
                return 4
            }
            if session.id.hasPrefix("claude-log-") {
                return 3
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

            let scoreA = richnessScore(for: a)
            let scoreB = richnessScore(for: b)
            return scoreA < scoreB
        }
    }

    func richnessScore(for session: SessionSnapshot) -> Int {
        let titleScore: Int = {
            guard let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else {
                return 0
            }
            return 1
        }()
        let taskScore: Int = {
            guard let task = session.currentTask?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !task.isEmpty else {
                return 0
            }
            return 1
        }()
        let terminalScore = session.terminalContext != nil ? 2 : 0
        let cwdScore = session.cwd != nil ? 1 : 0
        let outputScore = session.lastOutputAt != nil ? 1 : 0
        return terminalScore + titleScore + taskScore + cwdScore + outputScore
    }
}
