import AppKit
import Foundation
import VibeBarCore

@MainActor
final class MonitorViewModel: ObservableObject {
    static let shared = MonitorViewModel()

    @Published private(set) var sessions: [SessionSnapshot] = []
    @Published private(set) var summary: GlobalSummary = MonitorViewModel.makeEmptySummary()
    @Published private(set) var pluginStatus = PluginStatusReport()

    /// Number of sessions in running or awaitingInput state
    var runningCount: Int {
        sessions.filter { $0.status == .running || $0.status == .awaitingInput }.count
    }

    private let store = SessionFileStore()
    private let detector = CompositeSessionDetector()
    private let pluginDetector = PluginDetector()

    private var timer: Timer?
    private var lastPluginCheck: Date = .distantPast
    private let pluginCheckTTL: TimeInterval = 180
    private let defaults = UserDefaults.standard

    init() {
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshNow()
            }
        }
        if AppSettings.shared.autoCheckUpdates {
            checkPluginStatusNow()
        }
    }

    func pluginStatus(for tool: ToolKind) -> PluginInstallStatus {
        switch tool {
        case .claudeCode:
            return pluginStatus.claudeCode
        case .opencode:
            return pluginStatus.opencode
        default:
            return .cliNotFound
        }
    }

    func refreshNow() {
        let now = Date()
        store.cleanupStaleSessions(now: now, idleTTL: 30 * 60)

        let fileSessions = store.loadAll()
        let detectedSessions = detector.detectSessions()

        let merged = merge(fileSessions: fileSessions, processSessions: detectedSessions, now: now)
        sessions = merged.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.pid < rhs.pid
            }
            return lhs.updatedAt > rhs.updatedAt
        }

        summary = SummaryBuilder.build(sessions: sessions, now: now)
    }

    func openSessionsFolder() {
        do {
            try VibeBarPaths.ensureDirectories()
            NSWorkspace.shared.open(VibeBarPaths.sessionsDirectory)
        } catch {
            NSSound.beep()
        }
    }

    func purgeStaleNow() {
        store.cleanupStaleSessions(now: Date(), idleTTL: 1)
        refreshNow()
    }

    // MARK: - Plugin Status

    func checkPluginStatusIfNeeded() {
        guard Date().timeIntervalSince(lastPluginCheck) > pluginCheckTTL else { return }
        checkPluginStatusNow()
    }

    func checkPluginStatusNow() {
        lastPluginCheck = Date()
        let detector = pluginDetector
        Task {
            let report = await Task.detached { await detector.detectAll() }.value
            self.pluginStatus = report
        }
    }

    func installPlugin(tool: ToolKind) {
        switch tool {
        case .claudeCode:
            pluginStatus.claudeCode = .installing
        case .opencode:
            pluginStatus.opencode = .installing
        default:
            return
        }

        let detector = pluginDetector
        Task {
            do {
                try await Task.detached {
                    switch tool {
                    case .claudeCode:
                        try await detector.installClaudePlugin()
                    case .opencode:
                        try await detector.installOpenCodePlugin()
                    default:
                        break
                    }
                }.value
            } catch {
                let message = error.localizedDescription
                switch tool {
                case .claudeCode:
                    self.pluginStatus.claudeCode = .installFailed(message)
                case .opencode:
                    self.pluginStatus.opencode = .installFailed(message)
                default:
                    break
                }
                return
            }
            // Re-detect after successful install
            self.markPluginUpdatedNow(tool: tool)
            self.clearSkippedPluginVersion(for: tool)
            self.clearPromptedPluginVersion(for: tool)
            let report = await Task.detached { await detector.detectAll() }.value
            self.pluginStatus = report
            self.lastPluginCheck = Date()
        }
    }

    func uninstallPlugin(tool: ToolKind) {
        switch tool {
        case .claudeCode:
            pluginStatus.claudeCode = .uninstalling
        case .opencode:
            pluginStatus.opencode = .uninstalling
        default:
            return
        }

        let detector = pluginDetector
        Task {
            do {
                try await Task.detached {
                    switch tool {
                    case .claudeCode:
                        try await detector.uninstallClaudePlugin()
                    case .opencode:
                        try await detector.uninstallOpenCodePlugin()
                    default:
                        break
                    }
                }.value
            } catch {
                let message = error.localizedDescription
                switch tool {
                case .claudeCode:
                    self.pluginStatus.claudeCode = .uninstallFailed(message)
                case .opencode:
                    self.pluginStatus.opencode = .uninstallFailed(message)
                default:
                    break
                }
                return
            }
            let report = await Task.detached { await detector.detectAll() }.value
            self.pluginStatus = report
            self.lastPluginCheck = Date()
            self.clearSkippedPluginVersion(for: tool)
            self.clearPromptedPluginVersion(for: tool)
        }
    }

    func bundledPluginVersion(for tool: ToolKind) -> String? {
        pluginDetector.readBundledVersion(tool: tool)
    }

    func updatePlugin(tool: ToolKind) {
        switch tool {
        case .claudeCode:
            pluginStatus.claudeCode = .updating
        case .opencode:
            pluginStatus.opencode = .updating
        default:
            return
        }

        let detector = pluginDetector
        Task {
            do {
                try await Task.detached {
                    switch tool {
                    case .claudeCode:
                        try await detector.updateClaudePlugin()
                    case .opencode:
                        try await detector.updateOpenCodePlugin()
                    default:
                        break
                    }
                }.value
            } catch {
                let message = error.localizedDescription
                switch tool {
                case .claudeCode:
                    self.pluginStatus.claudeCode = .updateFailed(message)
                case .opencode:
                    self.pluginStatus.opencode = .updateFailed(message)
                default:
                    break
                }
                return
            }
            self.markPluginUpdatedNow(tool: tool)
            self.clearSkippedPluginVersion(for: tool)
            self.clearPromptedPluginVersion(for: tool)
            let report = await Task.detached { await detector.detectAll() }.value
            self.pluginStatus = report
            self.lastPluginCheck = Date()
        }
    }

    func lastPluginUpdatedAt(for tool: ToolKind) -> Date? {
        guard let seconds = defaults.object(forKey: pluginLastUpdatedKey(for: tool)) as? Double else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    func skipPluginVersion(tool: ToolKind, version: String) {
        defaults.set(version, forKey: skippedPluginVersionKey(for: tool))
    }

    func markPluginUpdatePrompted(tool: ToolKind, version: String) {
        defaults.set(version, forKey: promptedPluginVersionKey(for: tool))
    }

    func skippedPluginVersion(for tool: ToolKind) -> String? {
        defaults.string(forKey: skippedPluginVersionKey(for: tool))
    }

    func shouldPromptForPluginUpdate(tool: ToolKind, version: String) -> Bool {
        guard skippedPluginVersion(for: tool) != version else { return false }
        return promptedPluginVersion(for: tool) != version
    }

    private func merge(
        fileSessions: [SessionSnapshot],
        processSessions: [SessionSnapshot],
        now: Date
    ) -> [SessionSnapshot] {
        let activePIDs = Set(processSessions.map { $0.pid })
        let wrapperStaleTTL: TimeInterval = 10.0
        let pluginStaleTTL: TimeInterval = 45.0

        var normalized: [SessionSnapshot] = fileSessions.compactMap { session in
            if session.source == .wrapper {
                // wrapper 会话以状态心跳为准，不依赖 ps 命中，避免误删运行中的会话。
                if now.timeIntervalSince(session.updatedAt) > wrapperStaleTTL {
                    store.delete(sessionID: session.id)
                    return nil
                }
                return session
            }

            if session.source == .plugin {
                let hasPID = session.pid > 0
                let pidAlive = hasPID && kill(session.pid, 0) == 0

                // PID 已知且进程存活 → 保留（即使心跳过期，如 Claude 无心跳）
                if pidAlive {
                    return session
                }
                // PID 已知但进程已死 → 立即清理
                if hasPID {
                    store.delete(sessionID: session.id)
                    return nil
                }
                // PID 未知 → 按心跳超时兜底
                if now.timeIntervalSince(session.updatedAt) > pluginStaleTTL {
                    store.delete(sessionID: session.id)
                    return nil
                }
                return session
            }

            // 非 wrapper 的落盘会话属于旧数据，按进程存活判断后清理。
            if !activePIDs.contains(session.pid), now.timeIntervalSince(session.updatedAt) > 2.0 {
                store.delete(sessionID: session.id)
                return nil
            }
            return session
        }

        // 同一 PID 可能因插件生成不同 sessionID 而出现多条记录，按 PID 去重，
        // 保留 updatedAt 最新的会话，清理旧文件。
        var bestByPID: [Int32: Int] = [:]  // pid → index in normalized
        var duplicateIndices = Set<Int>()
        for (index, session) in normalized.enumerated() {
            guard session.pid > 0 else { continue }
            if let existingIndex = bestByPID[session.pid] {
                let existing = normalized[existingIndex]
                if session.updatedAt > existing.updatedAt {
                    // 新记录更新，淘汰旧记录
                    duplicateIndices.insert(existingIndex)
                    store.delete(sessionID: existing.id)
                    bestByPID[session.pid] = index
                } else {
                    // 旧记录更新，淘汰当前记录
                    duplicateIndices.insert(index)
                    store.delete(sessionID: session.id)
                }
            } else {
                bestByPID[session.pid] = index
            }
        }
        if !duplicateIndices.isEmpty {
            normalized = normalized.enumerated()
                .filter { !duplicateIndices.contains($0.offset) }
                .map { $0.element }
        }

        let wrapperPIDs = Set(normalized.map { $0.pid })
        for processSession in processSessions where !wrapperPIDs.contains(processSession.pid) {
            normalized.append(processSession)
        }

        return normalized
    }

    private static func makeEmptySummary() -> GlobalSummary {
        var byTool: [ToolKind: ToolSummary] = [:]
        for tool in ToolKind.allCases {
            byTool[tool] = ToolSummary(tool: tool, total: 0, counts: [:], overall: .stopped)
        }
        return GlobalSummary(total: 0, counts: [:], byTool: byTool, updatedAt: Date())
    }

    private func pluginLastUpdatedKey(for tool: ToolKind) -> String {
        "plugin.lastUpdatedAt.\(tool.rawValue)"
    }

    private func skippedPluginVersionKey(for tool: ToolKind) -> String {
        "plugin.skippedVersion.\(tool.rawValue)"
    }

    private func promptedPluginVersionKey(for tool: ToolKind) -> String {
        "plugin.promptedVersion.\(tool.rawValue)"
    }

    private func markPluginUpdatedNow(tool: ToolKind) {
        defaults.set(Date().timeIntervalSince1970, forKey: pluginLastUpdatedKey(for: tool))
    }

    private func promptedPluginVersion(for tool: ToolKind) -> String? {
        defaults.string(forKey: promptedPluginVersionKey(for: tool))
    }

    private func clearSkippedPluginVersion(for tool: ToolKind) {
        defaults.removeObject(forKey: skippedPluginVersionKey(for: tool))
    }

    private func clearPromptedPluginVersion(for tool: ToolKind) {
        defaults.removeObject(forKey: promptedPluginVersionKey(for: tool))
    }
}
