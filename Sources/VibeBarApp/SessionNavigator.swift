import AppKit
import Foundation
import VibeBarCore

struct SessionJumpPlan: Equatable, Sendable {
    var strategies: [SessionJumpStrategy]

    var isEmpty: Bool {
        strategies.isEmpty
    }
}

enum SessionJumpStrategy: Equatable, Sendable {
    case activateBundle(String)
    case focusTmuxPane(socketPath: String, paneID: String)
    case focusZellijSession(name: String, paneID: String?, tabName: String?, cwd: String?, commandName: String?)
}

@MainActor
final class SessionNavigator {
    static let shared = SessionNavigator()

    func open(_ session: SessionSnapshot) {
        let plan = Self.plan(for: session)
        guard !plan.isEmpty else {
            NSSound.beep()
            return
        }

        Task.detached(priority: .userInitiated) {
            let succeeded = await Self.execute(plan)
            if !succeeded {
                await MainActor.run {
                    NSSound.beep()
                }
            }
        }
    }

    nonisolated static func plan(for session: SessionSnapshot) -> SessionJumpPlan {
        guard let context = session.terminalContext else {
            return fallbackPlan(for: session)
        }

        var strategies: [SessionJumpStrategy] = []

        if context.origin == .desktop,
           let bundle = activationBundle(for: session, context: context) {
            strategies.append(.activateBundle(bundle))
            return SessionJumpPlan(strategies: strategies)
        }

        switch context.sessionManagerKind {
        case .tmux:
            if let socketPath = tmuxSocketPath(from: context.sessionManagerSessionID),
               let paneID = normalized(context.sessionManagerPaneID) {
                strategies.append(.focusTmuxPane(socketPath: socketPath, paneID: paneID))
            }
        case .zellij:
            if let sessionName = normalized(context.sessionManagerSessionID) {
                strategies.append(
                    .focusZellijSession(
                        name: sessionName,
                        paneID: normalized(context.sessionManagerPaneID),
                        tabName: normalized(context.sessionManagerTabName),
                        cwd: normalized(session.cwd),
                        commandName: zellijCommandName(for: session)
                    )
                )
            }
        case .none, .unknown:
            break
        }

        if let bundle = activationBundle(for: session, context: context) {
            strategies.append(.activateBundle(bundle))
        }

        return SessionJumpPlan(strategies: deduplicated(strategies))
    }

    nonisolated static func tmuxSocketPath(from rawValue: String?) -> String? {
        guard let rawValue = normalized(rawValue) else { return nil }
        return normalized(rawValue.split(separator: ",", maxSplits: 1).first.map(String.init))
    }

    nonisolated private static func fallbackPlan(for session: SessionSnapshot) -> SessionJumpPlan {
        if session.tool == .codex {
            return SessionJumpPlan(strategies: [.activateBundle("com.openai.codex")])
        }
        return SessionJumpPlan(strategies: [])
    }

    nonisolated private static func activationBundle(
        for session: SessionSnapshot,
        context: TerminalContext
    ) -> String? {
        if let bundle = normalized(context.bundleIdentifier) {
            return bundle
        }

        switch context.clientKind {
        case .kitty:
            return "net.kovidgoyal.kitty"
        case .ghostty:
            return "com.mitchellh.ghostty"
        case .iterm:
            return "com.googlecode.iterm2"
        case .warp:
            return "dev.warp.Warp-Stable"
        case .terminal:
            return "com.apple.Terminal"
        case .unknown:
            if session.tool == .codex && context.origin == .desktop {
                return "com.openai.codex"
            }
            return nil
        }
    }

    nonisolated private static func deduplicated(_ strategies: [SessionJumpStrategy]) -> [SessionJumpStrategy] {
        var seen = Set<String>()
        return strategies.filter { strategy in
            let key = strategy.dedupKey
            return seen.insert(key).inserted
        }
    }

    nonisolated private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func zellijCommandName(for session: SessionSnapshot) -> String? {
        if let command = normalized(session.command.first) {
            let name = (command as NSString).lastPathComponent
            return normalized(name)
        }
        return normalized(session.tool.executable)
    }

    private static func execute(_ plan: SessionJumpPlan) async -> Bool {
        var anySuccess = false

        for strategy in plan.strategies {
            let succeeded: Bool
            switch strategy {
            case .activateBundle(let bundleIdentifier):
                succeeded = await activateApplication(bundleIdentifier: bundleIdentifier)
            case .focusTmuxPane(let socketPath, let paneID):
                succeeded = await focusTmuxPane(socketPath: socketPath, paneID: paneID)
            case .focusZellijSession(let name, let paneID, let tabName, let cwd, let commandName):
                succeeded = await focusZellijSession(
                    name: name,
                    paneID: paneID,
                    tabName: tabName,
                    cwd: cwd,
                    commandName: commandName
                )
            }
            anySuccess = anySuccess || succeeded
        }

        return anySuccess
    }

    @MainActor
    private static func activateApplication(bundleIdentifier: String) async -> Bool {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            return running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }

        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        return await withCheckedContinuation { continuation in
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    private static func focusTmuxPane(socketPath: String, paneID: String) async -> Bool {
        let target = await readTmuxTarget(socketPath: socketPath, paneID: paneID)
        var anySuccess = false

        if let sessionID = target?.sessionID {
            let clients = await tmuxClients(socketPath: socketPath, sessionID: sessionID)
            if clients.count == 1, let client = clients.first {
                anySuccess = await runCommand(
                    executable: "tmux",
                    arguments: ["-S", socketPath, "switch-client", "-c", client, "-t", sessionID]
                ).isSuccess || anySuccess
            }
        }

        if let windowID = target?.windowID {
            anySuccess = await runCommand(
                executable: "tmux",
                arguments: ["-S", socketPath, "select-window", "-t", windowID]
            ).isSuccess || anySuccess
        }

        anySuccess = await runCommand(
            executable: "tmux",
            arguments: ["-S", socketPath, "select-pane", "-t", paneID]
        ).isSuccess || anySuccess

        return anySuccess
    }

    nonisolated static func parseZellijLayout(_ output: String) -> [ZellijLayoutTab] {
        var tabs: [ZellijLayoutTab] = []
        var rootCwd: String?
        var currentName: String?
        var currentFocused = false
        var currentCwds: [String] = []
        var currentTabDepth: Int?
        var braceDepth = 0

        for rawLine in output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if currentTabDepth == nil, rootCwd == nil, let cwd = parseLayoutCwd(from: line) {
                rootCwd = cwd
            } else if currentTabDepth != nil, let cwd = parseLayoutCwd(from: line) {
                currentCwds.append(cwd)
            }

            if line.hasPrefix("tab "), let name = parseTabName(from: line) {
                if let currentName, currentTabDepth != nil {
                    tabs.append(
                        ZellijLayoutTab(
                            name: currentName,
                            isFocused: currentFocused,
                            cwdCandidates: deduplicatedPaths(currentCwds)
                        )
                    )
                }

                currentName = name
                currentFocused = line.contains("focus=true")
                currentCwds = []
                currentTabDepth = braceDepth + line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
            }

            braceDepth += line.filter { $0 == "{" }.count
            braceDepth -= line.filter { $0 == "}" }.count

            if currentName != nil, let tabDepth = currentTabDepth, braceDepth < tabDepth {
                tabs.append(
                    ZellijLayoutTab(
                        name: currentName ?? "",
                        isFocused: currentFocused,
                        cwdCandidates: deduplicatedPaths(currentCwds)
                    )
                )
                currentName = nil
                currentFocused = false
                currentCwds = []
                currentTabDepth = nil
            }
        }

        if let currentName {
            tabs.append(
                ZellijLayoutTab(
                    name: currentName,
                    isFocused: currentFocused,
                    cwdCandidates: deduplicatedPaths(currentCwds)
                )
            )
        }

        if let rootCwd {
            if tabs.count == 1, tabs[0].cwdCandidates.isEmpty {
                tabs[0].cwdCandidates = [rootCwd]
            } else if let focusedIndex = tabs.firstIndex(where: \.isFocused), tabs[focusedIndex].cwdCandidates.isEmpty {
                tabs[focusedIndex].cwdCandidates = [rootCwd]
            }
        }

        return tabs
    }

    nonisolated static func inferZellijTabName(from layoutOutput: String, cwd: String?) -> String? {
        let tabs = parseZellijLayout(layoutOutput)
        guard !tabs.isEmpty else { return nil }

        if tabs.count == 1 {
            return tabs[0].name
        }

        guard let cwd = normalized(cwd) else { return nil }
        let target = normalizedPath(cwd)

        let exactMatches = tabs.filter { tab in
            tab.cwdCandidates.contains { normalizedPath($0) == target }
        }
        if exactMatches.count == 1 {
            return exactMatches[0].name
        }
        if exactMatches.count > 1 {
            let focusedMatches = exactMatches.filter(\.isFocused)
            if focusedMatches.count == 1 {
                return focusedMatches[0].name
            }
            return nil
        }

        let scored = tabs.map { tab in
            (
                tab: tab,
                score: tab.cwdCandidates
                    .map { commonPathComponentCount(normalizedPath($0), target) }
                    .max() ?? 0
            )
        }
        guard let bestScore = scored.map(\.score).max(), bestScore >= 2 else {
            return nil
        }

        let bestMatches = scored.filter { $0.score == bestScore }
        if bestMatches.count == 1 {
            return bestMatches[0].tab.name
        }

        let focusedMatches = bestMatches.filter { $0.tab.isFocused }
        if focusedMatches.count == 1 {
            return focusedMatches[0].tab.name
        }

        return nil
    }

    private static func focusZellijSession(
        name: String,
        paneID: String?,
        tabName: String?,
        cwd: String?,
        commandName: String?
    ) async -> Bool {
        let resolvedTabName: String?
        if let tabName = normalized(tabName) {
            resolvedTabName = tabName
        } else {
            resolvedTabName = await inferZellijTabName(sessionName: name, cwd: cwd)
        }
        guard let resolvedTabName else {
            _ = paneID
            return false
        }

        let switchedTab = await runCommand(
            executable: "zellij",
            arguments: ["--session", name, "action", "go-to-tab-name", resolvedTabName]
        ).isSuccess
        guard switchedTab else { return false }

        let focusedPane = await focusZellijPane(
            sessionName: name,
            paneID: paneID,
            commandName: commandName,
            cwd: cwd
        )
        return switchedTab || focusedPane
    }

    private static func readTmuxTarget(socketPath: String, paneID: String) async -> TmuxTarget? {
        let result = await runCommand(
            executable: "tmux",
            arguments: [
                "-S", socketPath,
                "display-message",
                "-p",
                "-t", paneID,
                "#{session_id}\t#{window_id}",
            ]
        )
        guard result.isSuccess else { return nil }

        let components = result.output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\t", omittingEmptySubsequences: false)
            .map(String.init)

        guard components.count == 2 else { return nil }
        return TmuxTarget(
            sessionID: normalized(components[0]),
            windowID: normalized(components[1])
        )
    }

    private static func tmuxClients(socketPath: String, sessionID: String) async -> [String] {
        let result = await runCommand(
            executable: "tmux",
            arguments: [
                "-S", socketPath,
                "list-clients",
                "-t", sessionID,
                "-F", "#{client_name}",
            ]
        )
        guard result.isSuccess else { return [] }

        return result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .compactMap(normalized)
    }

    private static func inferZellijTabName(sessionName: String, cwd: String?) async -> String? {
        let result = await runCommand(
            executable: "zellij",
            arguments: ["--session", sessionName, "action", "dump-layout"]
        )
        guard result.isSuccess else { return nil }
        return inferZellijTabName(from: result.output, cwd: cwd)
    }

    private static func focusZellijPane(
        sessionName: String,
        paneID: String?,
        commandName: String?,
        cwd: String?
    ) async -> Bool {
        _ = paneID
        var anySuccess = false

        for _ in 0..<6 {
            let result = await runCommand(
                executable: "zellij",
                arguments: ["--session", sessionName, "action", "dump-layout"]
            )
            guard result.isSuccess else { return anySuccess }

            let nextMove = nextZellijMove(
                from: result.output,
                commandName: commandName,
                cwd: cwd
            )
            switch nextMove {
            case .alreadyFocused:
                return true
            case .move(let direction):
                let moved = await runCommand(
                    executable: "zellij",
                    arguments: ["--session", sessionName, "action", "move-focus", direction.rawValue]
                ).isSuccess
                if !moved {
                    return anySuccess
                }
                anySuccess = true
            case .unresolved:
                return anySuccess
            }
        }

        return anySuccess
    }

    nonisolated static func nextZellijMove(
        from layoutOutput: String,
        commandName: String?,
        cwd: String?
    ) -> ZellijFocusMove {
        guard let activeTab = activeZellijTab(from: layoutOutput) else {
            return .unresolved
        }
        guard let targetPane = targetZellijPane(
            in: activeTab,
            commandName: commandName,
            cwd: cwd
        ) else {
            return .unresolved
        }
        guard let focusedPane = activeTab.panes.first(where: \.isFocused) else {
            return .unresolved
        }
        if focusedPane.path == targetPane.path {
            return .alreadyFocused
        }
        guard let direction = nextZellijDirection(from: focusedPane.path, to: targetPane.path) else {
            return .unresolved
        }
        return .move(direction)
    }

    nonisolated private static func parseTabName(from line: String) -> String? {
        guard let range = line.range(of: "name=\"") else {
            return nil
        }
        let remainder = line[range.upperBound...]
        guard let endIndex = remainder.firstIndex(of: "\"") else {
            return nil
        }
        let name = String(remainder[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    nonisolated private static func parseLayoutCwd(from line: String) -> String? {
        guard line.hasPrefix("cwd ") else {
            return nil
        }
        guard let firstQuote = line.firstIndex(of: "\"") else {
            return nil
        }
        let remainder = line[line.index(after: firstQuote)...]
        guard let endQuote = remainder.firstIndex(of: "\"") else {
            return nil
        }
        let cwd = String(remainder[..<endQuote]).trimmingCharacters(in: .whitespacesAndNewlines)
        return cwd.isEmpty ? nil : cwd
    }

    nonisolated private static func parseAttributeValue(named name: String, from line: String) -> String? {
        guard let range = line.range(of: "\(name)=\"") else {
            return nil
        }
        let remainder = line[range.upperBound...]
        guard let endIndex = remainder.firstIndex(of: "\"") else {
            return nil
        }
        let value = String(remainder[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    nonisolated private static func parseBooleanAttribute(named name: String, from line: String) -> Bool {
        line.contains("\(name)=true")
    }

    nonisolated static func activeZellijTab(from layoutOutput: String) -> ZellijActiveTab? {
        guard let root = parseZellijNodeTree(from: layoutOutput) else {
            return nil
        }
        let tabs = root.children.filter { $0.kind == .tab }
        guard let tabNode = tabs.first(where: \.isFocused) ?? tabs.first else {
            return nil
        }

        var panes: [ZellijPaneDescriptor] = []
        collectZellijPanes(
            from: tabNode,
            inheritedCwd: root.cwd,
            path: [],
            panes: &panes
        )
        return ZellijActiveTab(
            name: tabNode.name ?? "",
            panes: panes
        )
    }

    nonisolated private static func parseZellijNodeTree(from output: String) -> ZellijLayoutNode? {
        var stack: [ZellijLayoutNodeBuilder] = []
        var root: ZellijLayoutNode?

        func append(_ node: ZellijLayoutNode) {
            if stack.isEmpty {
                root = node
            } else {
                stack[stack.count - 1].children.append(node)
            }
        }

        func popNode() {
            guard let builder = stack.popLast() else { return }
            append(builder.build())
        }

        for rawLine in output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line == "}" {
                popNode()
                continue
            }

            if line == "layout {" {
                stack.append(ZellijLayoutNodeBuilder(kind: .layout))
                continue
            }

            if line.hasPrefix("tab "), line.hasSuffix("{") {
                stack.append(
                    ZellijLayoutNodeBuilder(
                        kind: .tab,
                        name: parseTabName(from: line),
                        isFocused: parseBooleanAttribute(named: "focus", from: line)
                    )
                )
                continue
            }

            if line.hasPrefix("pane") {
                let builder = ZellijLayoutNodeBuilder(
                    kind: .pane,
                    isFocused: parseBooleanAttribute(named: "focus", from: line),
                    splitDirection: ZellijSplitDirection(rawValue: parseAttributeValue(named: "split_direction", from: line) ?? ""),
                    command: parseAttributeValue(named: "command", from: line),
                    cwd: parseAttributeValue(named: "cwd", from: line),
                    isBorderless: parseBooleanAttribute(named: "borderless", from: line)
                )
                if line.hasSuffix("{") {
                    stack.append(builder)
                } else {
                    append(builder.build())
                }
                continue
            }

            if line.hasPrefix("plugin ") {
                let builder = ZellijLayoutNodeBuilder(kind: .plugin)
                if line.hasSuffix("{") {
                    stack.append(builder)
                } else {
                    append(builder.build())
                }
                continue
            }

            if let cwd = parseLayoutCwd(from: line), !stack.isEmpty {
                stack[stack.count - 1].cwd = cwd
            }
        }

        while !stack.isEmpty {
            popNode()
        }
        return root
    }

    nonisolated private static func collectZellijPanes(
        from node: ZellijLayoutNode,
        inheritedCwd: String?,
        path: [ZellijPathSegment],
        panes: inout [ZellijPaneDescriptor]
    ) {
        let effectiveCwd = normalized(node.cwd) ?? normalized(inheritedCwd)

        switch node.kind {
        case .layout:
            for child in node.children {
                collectZellijPanes(from: child, inheritedCwd: effectiveCwd, path: path, panes: &panes)
            }
        case .tab:
            let paneChildren = node.children.filter { $0.kind == .pane }
            let direction = inferredSplitDirection(for: node)
            for (index, child) in paneChildren.enumerated() {
                let nextPath = direction.map { path + [ZellijPathSegment(direction: $0, childIndex: index)] } ?? path
                collectZellijPanes(from: child, inheritedCwd: effectiveCwd, path: nextPath, panes: &panes)
            }
        case .pane:
            let paneChildren = node.children.filter { $0.kind == .pane }
            if paneChildren.isEmpty {
                let hasPluginChild = node.children.contains { $0.kind == .plugin }
                if !hasPluginChild {
                    panes.append(
                        ZellijPaneDescriptor(
                            commandName: normalized(node.command).map { ($0 as NSString).lastPathComponent },
                            cwd: effectiveCwd,
                            isFocused: node.isFocused,
                            path: path
                        )
                    )
                }
                return
            }

            let direction = inferredSplitDirection(for: node)
            for (index, child) in paneChildren.enumerated() {
                let nextPath = direction.map { path + [ZellijPathSegment(direction: $0, childIndex: index)] } ?? path
                collectZellijPanes(from: child, inheritedCwd: effectiveCwd, path: nextPath, panes: &panes)
            }
        case .plugin:
            return
        }
    }

    nonisolated private static func inferredSplitDirection(for node: ZellijLayoutNode) -> ZellijSplitDirection? {
        if let splitDirection = node.splitDirection {
            return splitDirection
        }
        if node.kind == .tab {
            return .horizontal
        }
        if node.kind == .pane && node.children.filter({ $0.kind == .pane }).count > 1 {
            return .vertical
        }
        return nil
    }

    nonisolated private static func targetZellijPane(
        in tab: ZellijActiveTab,
        commandName: String?,
        cwd: String?
    ) -> ZellijPaneDescriptor? {
        let normalizedCommand = normalized(commandName)?.lowercased()
        let normalizedCwd = normalized(cwd).map(normalizedPath)

        let scored = tab.panes.map { pane in
            (pane: pane, score: scoreZellijPane(pane, commandName: normalizedCommand, cwd: normalizedCwd))
        }.filter { $0.score > 0 }

        guard let bestScore = scored.map(\.score).max() else {
            return nil
        }
        let bestMatches = scored.filter { $0.score == bestScore }
        guard bestMatches.count == 1 else {
            return bestMatches.first(where: { $0.pane.isFocused })?.pane
        }
        return bestMatches[0].pane
    }

    nonisolated private static func scoreZellijPane(
        _ pane: ZellijPaneDescriptor,
        commandName: String?,
        cwd: String?
    ) -> Int {
        var score = 0

        if let commandName, let paneCommand = pane.commandName?.lowercased(), paneCommand == commandName {
            score += 100
        }

        if let cwd, let paneCwd = pane.cwd.map(normalizedPath) {
            if paneCwd == cwd {
                score += 50
            } else {
                score += commonPathComponentCount(paneCwd, cwd)
            }
        }

        return score
    }

    nonisolated private static func nextZellijDirection(
        from currentPath: [ZellijPathSegment],
        to targetPath: [ZellijPathSegment]
    ) -> ZellijMoveDirection? {
        let count = min(currentPath.count, targetPath.count)
        var divergenceIndex: Int?

        for index in 0..<count {
            if currentPath[index] != targetPath[index] {
                divergenceIndex = index
                break
            }
        }

        guard let divergenceIndex else {
            return nil
        }

        let currentStep = currentPath[divergenceIndex]
        let targetStep = targetPath[divergenceIndex]
        guard currentStep.direction == targetStep.direction else {
            return nil
        }

        switch currentStep.direction {
        case .vertical:
            return targetStep.childIndex > currentStep.childIndex ? .right : .left
        case .horizontal:
            return targetStep.childIndex > currentStep.childIndex ? .down : .up
        }
    }

    nonisolated private static func deduplicatedPaths(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for value in values {
            let normalized = normalizedPath(value)
            if seen.insert(normalized).inserted {
                result.append(value)
            }
        }

        return result
    }

    nonisolated private static func normalizedPath(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard trimmed.hasPrefix("/") else { return trimmed }
        return URL(fileURLWithPath: trimmed).standardizedFileURL.path
    }

    nonisolated private static func commonPathComponentCount(_ lhs: String, _ rhs: String) -> Int {
        let lhsComponents = (lhs as NSString).pathComponents
        let rhsComponents = (rhs as NSString).pathComponents
        let count = min(lhsComponents.count, rhsComponents.count)

        var matched = 0
        for index in 0..<count {
            guard lhsComponents[index] == rhsComponents[index] else {
                break
            }
            matched += 1
        }
        return matched
    }

    private static func runCommand(executable: String, arguments: [String]) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
            process.terminationHandler = { process in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self)
                continuation.resume(
                    returning: CommandResult(
                        status: process.terminationStatus,
                        output: text
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(
                    returning: CommandResult(status: 1, output: error.localizedDescription)
                )
            }
        }
    }
}

private struct CommandResult: Sendable {
    let status: Int32
    let output: String

    var isSuccess: Bool {
        status == 0
    }
}

private struct TmuxTarget: Sendable {
    let sessionID: String?
    let windowID: String?
}

struct ZellijLayoutTab: Equatable, Sendable {
    var name: String
    var isFocused: Bool
    var cwdCandidates: [String]
}

private extension SessionJumpStrategy {
    var dedupKey: String {
        switch self {
        case .activateBundle(let bundleIdentifier):
            return "bundle:\(bundleIdentifier)"
        case .focusTmuxPane(let socketPath, let paneID):
            return "tmux:\(socketPath):\(paneID)"
        case .focusZellijSession(let name, let paneID, let tabName, let cwd, let commandName):
            return "zellij:\(name):\(paneID ?? ""):\(tabName ?? ""):\(cwd ?? ""):\(commandName ?? "")"
        }
    }
}

private enum ZellijLayoutNodeKind: Sendable {
    case layout
    case tab
    case pane
    case plugin
}

enum ZellijSplitDirection: String, Equatable, Sendable {
    case vertical
    case horizontal
}

struct ZellijPathSegment: Equatable, Sendable {
    var direction: ZellijSplitDirection
    var childIndex: Int
}

struct ZellijPaneDescriptor: Equatable, Sendable {
    var commandName: String?
    var cwd: String?
    var isFocused: Bool
    var path: [ZellijPathSegment]
}

struct ZellijActiveTab: Equatable, Sendable {
    var name: String
    var panes: [ZellijPaneDescriptor]
}

enum ZellijMoveDirection: String, Equatable, Sendable {
    case left
    case right
    case up
    case down
}

enum ZellijFocusMove: Equatable, Sendable {
    case alreadyFocused
    case move(ZellijMoveDirection)
    case unresolved
}

private struct ZellijLayoutNode: Sendable {
    var kind: ZellijLayoutNodeKind
    var name: String?
    var isFocused: Bool
    var splitDirection: ZellijSplitDirection?
    var command: String?
    var cwd: String?
    var isBorderless: Bool
    var children: [ZellijLayoutNode]
}

private struct ZellijLayoutNodeBuilder {
    var kind: ZellijLayoutNodeKind
    var name: String? = nil
    var isFocused = false
    var splitDirection: ZellijSplitDirection? = nil
    var command: String? = nil
    var cwd: String? = nil
    var isBorderless = false
    var children: [ZellijLayoutNode] = []

    func build() -> ZellijLayoutNode {
        ZellijLayoutNode(
            kind: kind,
            name: name,
            isFocused: isFocused,
            splitDirection: splitDirection,
            command: command,
            cwd: cwd,
            isBorderless: isBorderless,
            children: children
        )
    }
}
