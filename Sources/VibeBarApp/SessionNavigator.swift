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
    case focusGhosttyTerminal(windowID: String?, tabID: String?, terminalID: String?, cwd: String?)
    case focusKittyWindow(controlAddress: String, windowID: String?, pid: Int32, cwd: String?)
    case focusITermSession(windowID: String?, tabIndex: Int?, tty: String?, uniqueID: String?)
    case focusWezTermPane(controlAddress: String?, paneID: String)
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

        if context.clientKind == .kitty,
           let controlAddress = normalized(context.clientControlAddress) {
            strategies.append(
                .focusKittyWindow(
                    controlAddress: controlAddress,
                    windowID: normalized(context.clientWindowID ?? context.clientSessionID),
                    pid: session.pid,
                    cwd: normalized(session.cwd)
                )
            )
        }

        if context.clientKind == .ghostty,
           normalized(context.clientWindowID) != nil ||
            normalized(context.clientTabID) != nil ||
            normalized(context.clientNativeSessionID) != nil ||
            normalized(session.cwd) != nil {
            strategies.append(
                .focusGhosttyTerminal(
                    windowID: normalized(context.clientWindowID),
                    tabID: normalized(context.clientTabID),
                    terminalID: normalized(context.clientNativeSessionID),
                    cwd: normalized(session.cwd)
                )
            )
        }

        if context.clientKind == .iterm,
           normalized(context.clientWindowID) != nil ||
            context.clientTabIndex != nil ||
            normalized(context.tty) != nil ||
            normalized(context.clientNativeSessionID ?? context.clientSessionID) != nil {
            strategies.append(
                .focusITermSession(
                    windowID: normalized(context.clientWindowID),
                    tabIndex: context.clientTabIndex,
                    tty: normalized(context.tty),
                    uniqueID: normalized(context.clientNativeSessionID ?? context.clientSessionID)
                )
            )
        }

        if context.clientKind == .wezterm,
           let paneID = normalized(context.clientSessionID) {
            strategies.append(
                .focusWezTermPane(
                    controlAddress: normalized(context.clientControlAddress),
                    paneID: paneID
                )
            )
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
        case .wezterm:
            return "com.github.wez.wezterm"
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
            case .focusGhosttyTerminal(let windowID, let tabID, let terminalID, let cwd):
                succeeded = await focusGhosttyTerminal(
                    windowID: windowID,
                    tabID: tabID,
                    terminalID: terminalID,
                    cwd: cwd
                )
            case .focusKittyWindow(let controlAddress, let windowID, let pid, let cwd):
                succeeded = await focusKittyWindow(
                    controlAddress: controlAddress,
                    windowID: windowID,
                    pid: pid,
                    cwd: cwd
                )
            case .focusITermSession(let windowID, let tabIndex, let tty, let uniqueID):
                succeeded = await focusITermSession(
                    windowID: windowID,
                    tabIndex: tabIndex,
                    tty: tty,
                    uniqueID: uniqueID
                )
            case .focusWezTermPane(let controlAddress, let paneID):
                succeeded = await focusWezTermPane(
                    controlAddress: controlAddress,
                    paneID: paneID
                )
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

    private static func focusKittyWindow(
        controlAddress: String,
        windowID: String?,
        pid: Int32,
        cwd: String?
    ) async -> Bool {
        let executable = kittyExecutablePath()
        let resolvedWindowID = await resolveKittyWindowID(
            executable: executable,
            controlAddress: controlAddress,
            requestedWindowID: windowID,
            pid: pid,
            cwd: cwd
        )
        guard let resolvedWindowID else { return false }

        var anySuccess = false
        anySuccess = await runCommand(
            executable: executable,
            arguments: ["@", "--to", controlAddress, "focus-tab", "--match", "window_id:\(resolvedWindowID)"]
        ).isSuccess || anySuccess
        anySuccess = await runCommand(
            executable: executable,
            arguments: ["@", "--to", controlAddress, "focus-window", "--match", "id:\(resolvedWindowID)"]
        ).isSuccess || anySuccess
        return anySuccess
    }

    private static func focusGhosttyTerminal(
        windowID: String?,
        tabID: String?,
        terminalID: String?,
        cwd: String?
    ) async -> Bool {
        let script = ghosttyFocusScript(
            windowID: windowID,
            tabID: tabID,
            terminalID: terminalID,
            cwd: cwd
        )
        let result = await runCommand(executable: "osascript", arguments: ["-e", script])
        return result.isSuccess && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private static func focusITermSession(
        windowID: String?,
        tabIndex: Int?,
        tty: String?,
        uniqueID: String?
    ) async -> Bool {
        let script = iTermFocusScript(
            windowID: windowID,
            tabIndex: tabIndex,
            tty: tty,
            uniqueID: uniqueID
        )
        let result = await runCommand(executable: "osascript", arguments: ["-e", script])
        return result.isSuccess && result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
    }

    private static func focusWezTermPane(
        controlAddress: String?,
        paneID: String
    ) async -> Bool {
        let result = await runCommand(
            executable: "wezterm",
            arguments: ["cli", "activate-pane", "--pane-id", paneID],
            environment: weztermEnvironment(controlAddress: controlAddress)
        )
        return result.isSuccess
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

    nonisolated static func inferZellijTabIndex(
        from layoutOutput: String,
        tabName: String?,
        cwd: String?
    ) -> Int? {
        let tabs = parseZellijLayout(layoutOutput)
        return matchedZellijTab(in: tabs, preferredName: tabName, cwd: cwd)?.index
    }

    nonisolated static func inferZellijTabName(from layoutOutput: String, cwd: String?) -> String? {
        let tabs = parseZellijLayout(layoutOutput)
        return matchedZellijTab(in: tabs, preferredName: nil, cwd: cwd)?.tab.name
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
        guard let output = await zellijLayoutOutput(sessionName: sessionName) else { return nil }
        return inferZellijTabName(from: output, cwd: cwd)
    }

    nonisolated static func zellijLayoutOutput(sessionName: String) async -> String? {
        let result = await runCommand(
            executable: "zellij",
            arguments: ["--session", sessionName, "action", "dump-layout"]
        )
        guard result.isSuccess else { return nil }
        return result.output
    }

    nonisolated static func tmuxWindowIndex(socketPath: String, paneID: String) async -> Int? {
        let result = await runCommand(
            executable: "tmux",
            arguments: [
                "-S", socketPath,
                "display-message",
                "-p",
                "-t", paneID,
                "#{window_index}",
            ]
        )
        guard result.isSuccess else { return nil }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(output)
    }

    private static func resolveKittyWindowID(
        executable: String,
        controlAddress: String,
        requestedWindowID: String?,
        pid: Int32,
        cwd: String?
    ) async -> String? {
        if let requestedWindowID = normalized(requestedWindowID) {
            let exactFocus = await runCommand(
                executable: executable,
                arguments: ["@", "--to", controlAddress, "focus-window", "--match", "id:\(requestedWindowID)"]
            ).isSuccess
            if exactFocus {
                return requestedWindowID
            }
        }

        let result = await runCommand(
            executable: executable,
            arguments: ["@", "--to", controlAddress, "ls"]
        )
        guard result.isSuccess else { return normalized(requestedWindowID) }

        return resolveKittyTarget(
            from: result.output,
            requestedWindowID: requestedWindowID,
            pid: pid,
            cwd: cwd
        )?.windowID
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

    nonisolated private static func matchedZellijTab(
        in tabs: [ZellijLayoutTab],
        preferredName: String?,
        cwd: String?
    ) -> (index: Int, tab: ZellijLayoutTab)? {
        guard !tabs.isEmpty else { return nil }

        if tabs.count == 1 {
            return (1, tabs[0])
        }

        if let preferredName = normalized(preferredName) {
            let exactMatches = tabs.enumerated().filter { _, tab in
                normalized(tab.name) == preferredName
            }
            if exactMatches.count == 1, let match = exactMatches.first {
                return (match.offset + 1, match.element)
            }
            if exactMatches.count > 1 {
                let focusedMatches = exactMatches.filter(\.element.isFocused)
                if focusedMatches.count == 1, let match = focusedMatches.first {
                    return (match.offset + 1, match.element)
                }
            }
        }

        guard let cwd = normalized(cwd) else { return nil }
        let target = normalizedPath(cwd)

        let exactMatches = tabs.enumerated().filter { _, tab in
            tab.cwdCandidates.contains { normalizedPath($0) == target }
        }
        if exactMatches.count == 1, let match = exactMatches.first {
            return (match.offset + 1, match.element)
        }
        if exactMatches.count > 1 {
            let focusedMatches = exactMatches.filter(\.element.isFocused)
            if focusedMatches.count == 1, let match = focusedMatches.first {
                return (match.offset + 1, match.element)
            }
            return nil
        }

        let scored = tabs.enumerated().map { offset, tab in
            (
                index: offset + 1,
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
        if bestMatches.count == 1, let match = bestMatches.first {
            return (match.index, match.tab)
        }

        let focusedMatches = bestMatches.filter { $0.tab.isFocused }
        if focusedMatches.count == 1, let match = focusedMatches.first {
            return (match.index, match.tab)
        }

        return nil
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

    nonisolated static func resolveKittyTarget(
        from output: String,
        requestedWindowID: String?,
        pid: Int32,
        cwd: String?
    ) -> KittyRemoteTarget? {
        let decoder = JSONDecoder()
        guard let data = output.data(using: .utf8),
              let osWindows = try? decoder.decode([KittyRemoteOSWindow].self, from: data) else {
            return nil
        }

        let flattened = osWindows.flatMap { osWindow in
            osWindow.tabs.enumerated().flatMap { index, tab in
                tab.windows.map { window in
                    KittyRemoteTargetCandidate(
                        osWindowID: osWindow.id,
                        tabID: tab.id,
                        tabTitle: tab.title,
                        tabIndex: index + 1,
                        window: window
                    )
                }
            }
        }

        if let requestedWindowID = normalized(requestedWindowID),
           let exact = flattened.first(where: { String($0.window.id) == requestedWindowID }) {
            return exact.target
        }

        let normalizedCwd = normalized(cwd).map(normalizedPath)
        let scored = flattened.map { candidate in
            (
                candidate: candidate,
                score: scoreKittyCandidate(candidate, pid: pid, cwd: normalizedCwd)
            )
        }.filter { $0.score > 0 }

        guard let bestScore = scored.map(\.score).max() else {
            return nil
        }
        let bestCandidates = scored.filter { $0.score == bestScore }
        if bestCandidates.count == 1 {
            return bestCandidates[0].candidate.target
        }
        if let active = bestCandidates.first(where: { $0.candidate.window.isActive }) {
            return active.candidate.target
        }
        return bestCandidates.first?.candidate.target
    }

    nonisolated private static func scoreKittyCandidate(
        _ candidate: KittyRemoteTargetCandidate,
        pid: Int32,
        cwd: String?
    ) -> Int {
        var score = 0

        if candidate.window.id == Int(pid) {
            score += 10
        }
        if candidate.window.pid == pid {
            score += 30
        }
        if candidate.window.foregroundProcesses.contains(where: { $0.pid == pid }) {
            score += 100
        }

        if let cwd {
            if let windowCwd = candidate.window.cwd.map(normalizedPath) {
                if windowCwd == cwd {
                    score += 40
                } else {
                    score += commonPathComponentCount(windowCwd, cwd)
                }
            }
            if let bestForegroundScore = candidate.window.foregroundProcesses
                .compactMap(\.cwd)
                .map(normalizedPath)
                .map({ processCwd in
                    processCwd == cwd ? 50 : commonPathComponentCount(processCwd, cwd)
                })
                .max() {
                score += bestForegroundScore
            }
        }

        return score
    }

    nonisolated private static func kittyExecutablePath() -> String {
        let fileManager = FileManager.default
        let applicationBinary = "/Applications/kitty.app/Contents/MacOS/kitty"
        if fileManager.isExecutableFile(atPath: applicationBinary) {
            return applicationBinary
        }
        return "kitty"
    }

    nonisolated static func kittyRemoteOutput(controlAddress: String) async -> String? {
        let executable = kittyExecutablePath()
        let result = await runCommand(
            executable: executable,
            arguments: ["@", "--to", controlAddress, "ls"]
        )
        guard result.isSuccess else { return nil }
        return result.output
    }

    nonisolated static func resolveWezTermTarget(
        from output: String,
        requestedPaneID: String?,
        cwd: String?
    ) -> WezTermRemoteTarget? {
        guard let entries = parseWezTermEntries(from: output), !entries.isEmpty else {
            return nil
        }

        if let requestedPaneID = normalized(requestedPaneID),
           let exact = entries.first(where: { $0.paneID == requestedPaneID }) {
            return weztermTarget(for: exact, allEntries: entries)
        }

        guard let cwd = normalized(cwd).map(normalizedPath) else {
            return nil
        }

        let exactMatches = entries.filter { entry in
            guard let entryCwd = entry.cwd.map(normalizedPath) else { return false }
            return entryCwd == cwd
        }
        if exactMatches.count == 1, let match = exactMatches.first {
            return weztermTarget(for: match, allEntries: entries)
        }

        let scored = entries.map { entry in
            (
                entry: entry,
                score: scoreWezTermEntry(entry, cwd: cwd)
            )
        }.filter { $0.score > 0 }

        guard let bestScore = scored.map(\.score).max() else {
            return nil
        }
        let bestMatches = scored.filter { $0.score == bestScore }
        if bestMatches.count == 1, let match = bestMatches.first {
            return weztermTarget(for: match.entry, allEntries: entries)
        }

        return nil
    }

    nonisolated static func weztermListOutput(controlAddress: String?) async -> String? {
        let result = await runCommand(
            executable: "wezterm",
            arguments: ["cli", "list", "--format", "json"],
            environment: weztermEnvironment(controlAddress: controlAddress)
        )
        guard result.isSuccess else { return nil }
        return result.output
    }

    nonisolated static func ghosttySnapshotOutput() async -> String? {
        let result = await runCommand(
            executable: "osascript",
            arguments: ["-e", ghosttySnapshotScript()]
        )
        guard result.isSuccess else { return nil }
        return result.output
    }

    nonisolated static func resolveGhosttyTarget(
        from output: String,
        cwd: String?,
        titleHints: [String]
    ) -> GhosttyRemoteTarget? {
        let tabs = parseGhosttySnapshotTabs(from: output)
        guard !tabs.isEmpty else { return nil }

        let normalizedCwd = normalized(cwd).map(normalizedPath)
        let normalizedTitleHints = deduplicatedGhosttyHints(titleHints)

        if tabs.count == 1, let tab = tabs.first {
            return GhosttyRemoteTarget(
                windowID: tab.windowID,
                tabID: tab.tabID,
                tabTitle: tab.tabTitle,
                tabIndex: tab.tabIndex,
                terminalID: resolveGhosttyTerminalID(in: tab, cwd: normalizedCwd, titleHints: normalizedTitleHints)
            )
        }

        let scored = tabs.map { tab in
            (
                tab: tab,
                score: scoreGhosttyTab(tab, cwd: normalizedCwd, titleHints: normalizedTitleHints)
            )
        }.filter { $0.score > 0 }

        guard let bestScore = scored.map(\.score).max() else { return nil }
        let bestMatches = scored.filter { $0.score == bestScore }

        let chosenTab: GhosttySnapshotTab?
        if bestMatches.count == 1 {
            chosenTab = bestMatches[0].tab
        } else if let selected = bestMatches.first(where: { $0.tab.isSelected }), bestMatches.filter({ $0.tab.isSelected }).count == 1 {
            chosenTab = selected.tab
        } else {
            chosenTab = nil
        }

        guard let chosenTab else { return nil }
        return GhosttyRemoteTarget(
            windowID: chosenTab.windowID,
            tabID: chosenTab.tabID,
            tabTitle: chosenTab.tabTitle,
            tabIndex: chosenTab.tabIndex,
            terminalID: resolveGhosttyTerminalID(in: chosenTab, cwd: normalizedCwd, titleHints: normalizedTitleHints)
        )
    }

    nonisolated static func iTermSnapshotOutput() async -> String? {
        let result = await runCommand(
            executable: "osascript",
            arguments: ["-e", iTermSnapshotScript()]
        )
        guard result.isSuccess else { return nil }
        return result.output
    }

    nonisolated static func resolveITermTarget(
        from output: String,
        tty: String?,
        sessionID: String?
    ) -> ITermRemoteTarget? {
        let sessions = parseITermSnapshotSessions(from: output)
        guard !sessions.isEmpty else { return nil }

        if let tty = normalized(tty) {
            let matches = sessions.filter { $0.tty == tty }
            if matches.count == 1, let match = matches.first {
                return match.target
            }
        }

        if let sessionID = normalized(sessionID) {
            let matches = sessions.filter {
                $0.uniqueID == sessionID || $0.sessionID == sessionID
            }
            if matches.count == 1, let match = matches.first {
                return match.target
            }
        }

        if sessions.count == 1, let match = sessions.first {
            return match.target
        }

        return nil
    }

    nonisolated private static func ghosttySnapshotScript() -> String {
        """
        set tabChar to ASCII character 9
        set oldTIDs to AppleScript's text item delimiters
        set AppleScript's text item delimiters to linefeed
        tell application "Ghostty"
            set linesOut to {}
            repeat with w in windows
                set wid to id of w as text
                set end of linesOut to "window" & tabChar & wid
                repeat with t in tabs of w
                    set tid to id of t as text
                    set selectedFlag to "0"
                    if selected of t then set selectedFlag to "1"
                    set end of linesOut to "tab" & tabChar & wid & tabChar & tid & tabChar & (index of t as text) & tabChar & selectedFlag & tabChar & (name of t as text)
                    set focusedID to ""
                    try
                        set focusedID to id of focused terminal of t as text
                    end try
                    repeat with term in terminals of t
                        set termID to id of term as text
                        set focusedFlag to "0"
                        if focusedID is termID then set focusedFlag to "1"
                        set end of linesOut to "terminal" & tabChar & wid & tabChar & tid & tabChar & termID & tabChar & focusedFlag & tabChar & (name of term as text) & tabChar & (working directory of term as text)
                    end repeat
                end repeat
            end repeat
            set payload to linesOut as string
        end tell
        set AppleScript's text item delimiters to oldTIDs
        return payload
        """
    }

    nonisolated private static func iTermSnapshotScript() -> String {
        """
        set tabChar to ASCII character 9
        set oldTIDs to AppleScript's text item delimiters
        set AppleScript's text item delimiters to linefeed
        tell application id "com.googlecode.iterm2"
            set linesOut to {}
            repeat with w in windows
                set wid to id of w as text
                set end of linesOut to "window" & tabChar & wid
                repeat with aTab in tabs of w
                    set idx to index of aTab as integer
                    set end of linesOut to "tab" & tabChar & wid & tabChar & (idx as text)
                    repeat with aSession in sessions of aTab
                        set sid to ""
                        set uid to ""
                        set ttyValue to ""
                        set sessionName to ""
                        try
                            set sid to id of aSession as text
                        end try
                        try
                            set uid to unique id of aSession as text
                        end try
                        try
                            set ttyValue to tty of aSession as text
                        end try
                        try
                            set sessionName to name of aSession as text
                        end try
                        set end of linesOut to "session" & tabChar & wid & tabChar & (idx as text) & tabChar & sid & tabChar & uid & tabChar & ttyValue & tabChar & sessionName
                    end repeat
                end repeat
            end repeat
            set payload to linesOut as string
        end tell
        set AppleScript's text item delimiters to oldTIDs
        return payload
        """
    }

    nonisolated private static func ghosttyFocusScript(
        windowID: String?,
        tabID: String?,
        terminalID: String?,
        cwd: String?
    ) -> String {
        let windowLiteral = appleScriptStringLiteral(windowID)
        let tabLiteral = appleScriptStringLiteral(tabID)
        let terminalLiteral = appleScriptStringLiteral(terminalID)
        let cwdLiteral = appleScriptStringLiteral(cwd)

        return """
        set targetWindowID to \(windowLiteral)
        set targetTabID to \(tabLiteral)
        set targetTerminalID to \(terminalLiteral)
        set targetCwd to \(cwdLiteral)
        tell application "Ghostty"
            if targetTerminalID is not "" then
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with term in terminals of t
                            if (id of term as text) is targetTerminalID then
                                focus term
                                return "1"
                            end if
                        end repeat
                    end repeat
                end repeat
            end if

            if targetTabID is not "" then
                repeat with w in windows
                    if targetWindowID is "" or (id of w as text) is targetWindowID then
                        repeat with t in tabs of w
                            if (id of t as text) is targetTabID then
                                select tab t
                                return "1"
                            end if
                        end repeat
                    end if
                end repeat
            end if

            if targetWindowID is not "" then
                repeat with w in windows
                    if (id of w as text) is targetWindowID then
                        activate window w
                        return "1"
                    end if
                end repeat
            end if

            if targetCwd is not "" then
                set matches to every terminal whose working directory is targetCwd
                if (count of matches) is 1 then
                    focus (item 1 of matches)
                    return "1"
                end if
            end if
        end tell
        return "0"
        """
    }

    nonisolated private static func iTermFocusScript(
        windowID: String?,
        tabIndex: Int?,
        tty: String?,
        uniqueID: String?
    ) -> String {
        let windowLiteral = appleScriptStringLiteral(windowID)
        let tabLiteral = appleScriptStringLiteral(tabIndex.map(String.init))
        let ttyLiteral = appleScriptStringLiteral(tty)
        let uniqueLiteral = appleScriptStringLiteral(uniqueID)

        return """
        set targetWindowID to \(windowLiteral)
        set targetDisplayTabIndex to \(tabLiteral)
        set targetTTY to \(ttyLiteral)
        set targetUniqueID to \(uniqueLiteral)
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                if targetWindowID is "" or (id of w as text) is targetWindowID then
                    repeat with aTab in tabs of w
                        set tabMatches to true
                        if targetDisplayTabIndex is not "" then
                            set tabMatches to ((index of aTab as integer) is ((targetDisplayTabIndex as integer) - 1))
                        end if
                        if tabMatches then
                            repeat with aSession in sessions of aTab
                                set sessionMatches to false
                                try
                                    if targetUniqueID is not "" and (unique id of aSession as text) is targetUniqueID then
                                        set sessionMatches to true
                                    end if
                                end try
                                if sessionMatches is false then
                                    try
                                        if targetTTY is not "" and (tty of aSession as text) is targetTTY then
                                            set sessionMatches to true
                                        end if
                                    end try
                                end if
                                if sessionMatches then
                                    tell w to select
                                    tell aTab to select
                                    tell aSession to select
                                    return "1"
                                end if
                            end repeat
                            if targetDisplayTabIndex is not "" then
                                tell w to select
                                tell aTab to select
                                return "1"
                            end if
                        end if
                    end repeat
                    if targetWindowID is not "" then
                        tell w to select
                        return "1"
                    end if
                end if
            end repeat
        end tell
        return "0"
        """
    }

    nonisolated private static func parseGhosttySnapshotTabs(from output: String) -> [GhosttySnapshotTab] {
        var tabsByKey: [String: GhosttySnapshotTab] = [:]
        var orderedKeys: [String] = []

        for fields in tabSeparatedLines(from: output) {
            guard let kind = fields.first else { continue }
            switch kind {
            case "tab":
                guard fields.count >= 6,
                      let tabIndex = Int(fields[3]) else { continue }
                let key = "\(fields[1])|\(fields[2])"
                if tabsByKey[key] == nil {
                    orderedKeys.append(key)
                }
                tabsByKey[key] = GhosttySnapshotTab(
                    windowID: fields[1],
                    tabID: fields[2],
                    tabIndex: tabIndex,
                    tabTitle: sanitizedSnapshotField(fields[5]),
                    isSelected: snapshotBool(fields[4]),
                    terminals: tabsByKey[key]?.terminals ?? []
                )
            case "terminal":
                guard fields.count >= 7 else { continue }
                let key = "\(fields[1])|\(fields[2])"
                guard var tab = tabsByKey[key] else { continue }
                tab.terminals.append(
                    GhosttySnapshotTerminal(
                        id: fields[3],
                        isFocused: snapshotBool(fields[4]),
                        name: sanitizedSnapshotField(fields[5]),
                        cwd: sanitizedSnapshotField(fields[6])
                    )
                )
                tabsByKey[key] = tab
            default:
                continue
            }
        }

        return orderedKeys.compactMap { tabsByKey[$0] }
    }

    nonisolated private static func parseITermSnapshotSessions(from output: String) -> [ITermSnapshotSession] {
        var sessions: [ITermSnapshotSession] = []

        for fields in tabSeparatedLines(from: output) {
            guard let kind = fields.first, kind == "session", fields.count >= 7,
                  let rawTabIndex = Int(fields[2]) else { continue }
            sessions.append(
                ITermSnapshotSession(
                    windowID: fields[1],
                    rawTabIndex: rawTabIndex,
                    displayTabIndex: rawTabIndex + 1,
                    sessionID: sanitizedSnapshotField(fields[3]),
                    uniqueID: sanitizedSnapshotField(fields[4]),
                    tty: sanitizedSnapshotField(fields[5]),
                    name: sanitizedSnapshotField(fields[6])
                )
            )
        }

        return sessions
    }

    nonisolated private static func tabSeparatedLines(from output: String) -> [[String]] {
        output
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            }
    }

    nonisolated private static func sanitizedSnapshotField(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.lowercased() != "missing value" else { return nil }
        return trimmed
    }

    nonisolated private static func snapshotBool(_ value: String?) -> Bool {
        guard let value = sanitizedSnapshotField(value)?.lowercased() else { return false }
        return value == "1" || value == "true" || value == "yes"
    }

    nonisolated private static func scoreGhosttyTab(
        _ tab: GhosttySnapshotTab,
        cwd: String?,
        titleHints: [String]
    ) -> Int {
        let terminalScore = tab.terminals.map { terminal in
            scoreGhosttyTerminal(terminal, tabTitle: tab.tabTitle, cwd: cwd, titleHints: titleHints)
        }.max() ?? 0
        return terminalScore + (tab.isSelected ? 1 : 0)
    }

    nonisolated private static func scoreGhosttyTerminal(
        _ terminal: GhosttySnapshotTerminal,
        tabTitle: String?,
        cwd: String?,
        titleHints: [String]
    ) -> Int {
        var score = 0

        if let cwd, let terminalCwd = terminal.cwd.map(normalizedPath) {
            if terminalCwd == cwd {
                score += 100
            } else {
                score += commonPathComponentCount(terminalCwd, cwd)
            }
        }

        if !titleHints.isEmpty {
            let candidates = [terminal.name, tabTitle]
                .compactMap { sanitizedSnapshotField($0)?.lowercased() }
            for hint in titleHints {
                if candidates.contains(hint) {
                    score += 40
                } else if candidates.contains(where: { $0.contains(hint) || hint.contains($0) }) {
                    score += 20
                }
            }
        }

        if terminal.isFocused {
            score += 1
        }

        return score
    }

    nonisolated private static func resolveGhosttyTerminalID(
        in tab: GhosttySnapshotTab,
        cwd: String?,
        titleHints: [String]
    ) -> String? {
        guard !tab.terminals.isEmpty else { return nil }

        let scored = tab.terminals.map { terminal in
            (
                terminal: terminal,
                score: scoreGhosttyTerminal(terminal, tabTitle: tab.tabTitle, cwd: cwd, titleHints: titleHints)
            )
        }

        if let bestScore = scored.map(\.score).max(), bestScore > 0 {
            let bestMatches = scored.filter { $0.score == bestScore }
            if bestMatches.count == 1, let match = bestMatches.first {
                return match.terminal.id
            }
            let focusedMatches = bestMatches.filter(\.terminal.isFocused)
            if focusedMatches.count == 1, let match = focusedMatches.first {
                return match.terminal.id
            }
            return nil
        }

        if tab.terminals.count == 1, let terminal = tab.terminals.first {
            return terminal.id
        }

        return tab.terminals.first(where: \.isFocused)?.id
    }

    nonisolated private static func appleScriptStringLiteral(_ value: String?) -> String {
        guard let value = normalized(value) else { return "\"\"" }
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    nonisolated private static func deduplicatedGhosttyHints(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            guard let normalized = normalized(value)?.lowercased() else { continue }
            if seen.insert(normalized).inserted {
                result.append(normalized)
            }
        }
        return result
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

    nonisolated private static func parseWezTermEntries(from output: String) -> [WezTermListEntry]? {
        guard let data = output.data(using: .utf8),
              let rawEntries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        return rawEntries.compactMap { rawEntry in
            guard let paneID = stringValue(from: rawEntry["pane_id"]),
                  let tabID = stringValue(from: rawEntry["tab_id"]),
                  let windowID = stringValue(from: rawEntry["window_id"]) else {
                return nil
            }

            return WezTermListEntry(
                windowID: windowID,
                tabID: tabID,
                paneID: paneID,
                title: stringValue(from: rawEntry["title"]),
                cwd: normalizedWezTermPath(rawEntry["cwd"])
            )
        }
    }

    nonisolated private static func weztermTarget(
        for entry: WezTermListEntry,
        allEntries: [WezTermListEntry]
    ) -> WezTermRemoteTarget {
        var orderedTabIDs: [String] = []
        var seen = Set<String>()

        for candidate in allEntries where candidate.windowID == entry.windowID {
            if seen.insert(candidate.tabID).inserted {
                orderedTabIDs.append(candidate.tabID)
            }
        }

        let tabIndex = orderedTabIDs.firstIndex(of: entry.tabID).map { $0 + 1 }
        return WezTermRemoteTarget(
            windowID: entry.windowID,
            tabID: entry.tabID,
            paneID: entry.paneID,
            tabTitle: entry.title,
            tabIndex: tabIndex
        )
    }

    nonisolated private static func scoreWezTermEntry(
        _ entry: WezTermListEntry,
        cwd: String
    ) -> Int {
        guard let entryCwd = entry.cwd.map(normalizedPath) else { return 0 }
        if entryCwd == cwd {
            return 100
        }
        return commonPathComponentCount(entryCwd, cwd)
    }

    nonisolated private static func normalizedWezTermPath(_ rawValue: Any?) -> String? {
        guard let raw = stringValue(from: rawValue) else { return nil }
        if let url = URL(string: raw), url.isFileURL {
            let path = url.path.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated private static func stringValue(from rawValue: Any?) -> String? {
        switch rawValue {
        case let value as String:
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    nonisolated private static func weztermEnvironment(controlAddress: String?) -> [String: String]? {
        guard let controlAddress = normalized(controlAddress) else {
            return nil
        }
        return ["WEZTERM_UNIX_SOCKET": controlAddress]
    }

    private static func runCommand(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) async -> CommandResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [executable] + arguments
            if let environment {
                var merged = ProcessInfo.processInfo.environment
                for (key, value) in environment {
                    merged[key] = value
                }
                process.environment = merged
            }
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
        case .focusGhosttyTerminal(let windowID, let tabID, let terminalID, let cwd):
            return "ghostty:\(windowID ?? ""):\(tabID ?? ""):\(terminalID ?? ""):\(cwd ?? "")"
        case .focusKittyWindow(let controlAddress, let windowID, let pid, let cwd):
            return "kitty:\(controlAddress):\(windowID ?? ""):\(pid):\(cwd ?? "")"
        case .focusITermSession(let windowID, let tabIndex, let tty, let uniqueID):
            return "iterm:\(windowID ?? ""):\(tabIndex.map(String.init) ?? ""):\(tty ?? ""):\(uniqueID ?? "")"
        case .focusWezTermPane(let controlAddress, let paneID):
            return "wezterm:\(controlAddress ?? ""):\(paneID)"
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

struct KittyRemoteTarget: Equatable, Sendable {
    var osWindowID: Int
    var tabID: Int
    var tabTitle: String
    var tabIndex: Int
    var windowID: String
}

struct GhosttyRemoteTarget: Equatable, Sendable {
    var windowID: String
    var tabID: String
    var tabTitle: String?
    var tabIndex: Int
    var terminalID: String?
}

struct WezTermRemoteTarget: Equatable, Sendable {
    var windowID: String
    var tabID: String
    var paneID: String
    var tabTitle: String?
    var tabIndex: Int?
}

private struct WezTermListEntry: Sendable {
    var windowID: String
    var tabID: String
    var paneID: String
    var title: String?
    var cwd: String?
}

struct ITermRemoteTarget: Equatable, Sendable {
    var windowID: String
    var rawTabIndex: Int
    var displayTabIndex: Int
    var sessionID: String?
    var uniqueID: String?
}

private struct GhosttySnapshotTab: Sendable {
    var windowID: String
    var tabID: String
    var tabIndex: Int
    var tabTitle: String?
    var isSelected: Bool
    var terminals: [GhosttySnapshotTerminal]
}

private struct GhosttySnapshotTerminal: Sendable {
    var id: String
    var isFocused: Bool
    var name: String?
    var cwd: String?
}

private struct ITermSnapshotSession: Sendable {
    var windowID: String
    var rawTabIndex: Int
    var displayTabIndex: Int
    var sessionID: String?
    var uniqueID: String?
    var tty: String?
    var name: String?

    var target: ITermRemoteTarget {
        ITermRemoteTarget(
            windowID: windowID,
            rawTabIndex: rawTabIndex,
            displayTabIndex: displayTabIndex,
            sessionID: sessionID,
            uniqueID: uniqueID
        )
    }
}

private struct KittyRemoteTargetCandidate {
    var osWindowID: Int
    var tabID: Int
    var tabTitle: String
    var tabIndex: Int
    var window: KittyRemoteWindow

    var target: KittyRemoteTarget {
        KittyRemoteTarget(
            osWindowID: osWindowID,
            tabID: tabID,
            tabTitle: tabTitle,
            tabIndex: tabIndex,
            windowID: String(window.id)
        )
    }
}

private struct KittyRemoteOSWindow: Decodable {
    var id: Int
    var tabs: [KittyRemoteTab]
}

private struct KittyRemoteTab: Decodable {
    var id: Int
    var title: String
    var windows: [KittyRemoteWindow]
}

private struct KittyRemoteWindow: Decodable {
    var id: Int
    var cwd: String?
    var pid: Int32
    var isActive: Bool
    var foregroundProcesses: [KittyRemoteForegroundProcess]

    private enum CodingKeys: String, CodingKey {
        case id
        case cwd
        case pid
        case isActive = "is_active"
        case foregroundProcesses = "foreground_processes"
    }
}

private struct KittyRemoteForegroundProcess: Decodable {
    var cwd: String?
    var pid: Int32
}
