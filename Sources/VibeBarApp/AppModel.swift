import AppKit
import Foundation
import VibeBarCore

@MainActor
final class MonitorViewModel: ObservableObject {
    @Published private(set) var sessions: [SessionSnapshot] = []
    @Published private(set) var summary: GlobalSummary = MonitorViewModel.makeEmptySummary()
    @Published private(set) var pluginStatus = PluginStatusReport()

    private let store = SessionFileStore()
    private let scanner = ProcessScanner()
    private let pluginDetector = PluginDetector()

    private var timer: Timer?
    private var lastPluginCheck: Date = .distantPast
    private let pluginCheckTTL: TimeInterval = 60

    init() {
        refreshNow()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshNow()
            }
        }
        checkPluginStatusNow()
    }

    func refreshNow() {
        let now = Date()
        store.cleanupStaleSessions(now: now, idleTTL: 30 * 60)

        let fileSessions = store.loadAll()
        let processSessions = scanner.scan(now: now)

        let merged = merge(fileSessions: fileSessions, processSessions: processSessions, now: now)
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
        }
    }

    func updatePlugin(tool: ToolKind) {
        switch tool {
        case .claudeCode:
            pluginStatus.claudeCode = .updating
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
                    default:
                        break
                    }
                }.value
            } catch {
                let message = error.localizedDescription
                switch tool {
                case .claudeCode:
                    self.pluginStatus.claudeCode = .updateFailed(message)
                default:
                    break
                }
                return
            }
            let report = await Task.detached { await detector.detectAll() }.value
            self.pluginStatus = report
            self.lastPluginCheck = Date()
        }
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
}
