import Foundation

public enum TerminalContextResolver {
    public static func resolve(
        metadata: [String: String],
        processChain: [DetectorSupport.ProcEntry] = [],
        originHint: SessionOriginKind? = nil
    ) -> TerminalContext? {
        let environment = normalizedEnvironment(from: metadata)
        let tty = DetectorSupport.normalizeTTY(metadata["_tty"] ?? metadata["tty"]) ?? firstTTY(in: processChain)
        return resolve(
            environment: environment,
            tty: tty,
            processChain: processChain,
            originHint: originHint
        )
    }

    public static func resolve(
        process: DetectorSupport.ProcEntry,
        context: DetectorSupport.DetectionContext,
        originHint: SessionOriginKind? = nil
    ) async -> TerminalContext? {
        let environment = await DetectorSupport.getProcessEnvironment(pid: process.pid)
        return resolve(
            environment: environment,
            tty: firstTTY(in: context.parentChain(startingAt: process.pid)),
            processChain: context.parentChain(startingAt: process.pid),
            originHint: originHint
        )
    }

    public static func merge(primary: TerminalContext?, fallback: TerminalContext?) -> TerminalContext? {
        switch (primary, fallback) {
        case let (primary?, fallback?):
            return TerminalContext(
                clientKind: primary.clientKind != .unknown ? primary.clientKind : fallback.clientKind,
                bundleIdentifier: primary.bundleIdentifier ?? fallback.bundleIdentifier,
                clientControlAddress: primary.clientControlAddress ?? fallback.clientControlAddress,
                tty: primary.tty ?? fallback.tty,
                clientSessionID: primary.clientSessionID ?? fallback.clientSessionID,
                clientWindowID: primary.clientWindowID ?? fallback.clientWindowID,
                clientTabTitle: primary.clientTabTitle ?? fallback.clientTabTitle,
                clientTabIndex: primary.clientTabIndex ?? fallback.clientTabIndex,
                sessionManagerKind: primary.sessionManagerKind != .unknown ? primary.sessionManagerKind : fallback.sessionManagerKind,
                sessionManagerSessionID: primary.sessionManagerSessionID ?? fallback.sessionManagerSessionID,
                sessionManagerPaneID: primary.sessionManagerPaneID ?? fallback.sessionManagerPaneID,
                sessionManagerTabName: primary.sessionManagerTabName ?? fallback.sessionManagerTabName,
                sessionManagerTabIndex: primary.sessionManagerTabIndex ?? fallback.sessionManagerTabIndex,
                origin: primary.origin != .unknown ? primary.origin : fallback.origin
            )
        case let (primary?, nil):
            return primary
        case let (nil, fallback?):
            return fallback
        case (nil, nil):
            return nil
        }
    }

    private static func resolve(
        environment: [String: String],
        tty: String?,
        processChain: [DetectorSupport.ProcEntry],
        originHint: SessionOriginKind?
    ) -> TerminalContext? {
        let bundleIdentifier = resolveBundleIdentifier(environment: environment, processChain: processChain)
        let clientKind = resolveClientKind(
            environment: environment,
            bundleIdentifier: bundleIdentifier,
            processChain: processChain
        )
        let sessionManagerKind = resolveSessionManagerKind(environment: environment, processChain: processChain)
        let origin = resolveOrigin(
            environment: environment,
            bundleIdentifier: bundleIdentifier,
            tty: tty,
            originHint: originHint
        )

        if clientKind == .unknown &&
            sessionManagerKind == .unknown &&
            bundleIdentifier == nil &&
            tty == nil &&
            origin == .unknown {
            return nil
        }

        return TerminalContext(
            clientKind: clientKind,
            bundleIdentifier: bundleIdentifier,
            clientControlAddress: resolveClientControlAddress(environment: environment, clientKind: clientKind),
            tty: tty,
            clientSessionID: resolveClientSessionID(environment: environment, clientKind: clientKind),
            clientWindowID: resolveClientWindowID(environment: environment, clientKind: clientKind),
            clientTabTitle: nil,
            clientTabIndex: nil,
            sessionManagerKind: sessionManagerKind,
            sessionManagerSessionID: resolveSessionManagerSessionID(environment: environment, kind: sessionManagerKind),
            sessionManagerPaneID: resolveSessionManagerPaneID(environment: environment, kind: sessionManagerKind),
            sessionManagerTabName: resolveSessionManagerTabName(environment: environment, kind: sessionManagerKind),
            sessionManagerTabIndex: resolveSessionManagerTabIndex(environment: environment, kind: sessionManagerKind),
            origin: origin
        )
    }

    private static func normalizedEnvironment(from metadata: [String: String]) -> [String: String] {
        var environment: [String: String] = [:]
        for (key, value) in metadata where !value.isEmpty {
            environment[key] = value
            if key.hasPrefix("_env_") {
                environment[String(key.dropFirst(5))] = value
            } else if key.hasPrefix("env.") {
                environment[String(key.dropFirst(4))] = value
            }
        }
        return environment
    }

    private static func firstTTY(in processChain: [DetectorSupport.ProcEntry]) -> String? {
        for process in processChain {
            if let tty = DetectorSupport.normalizeTTY(process.tty) {
                return tty
            }
        }
        return nil
    }

    private static func resolveBundleIdentifier(
        environment: [String: String],
        processChain: [DetectorSupport.ProcEntry]
    ) -> String? {
        if let value = environment["__CFBundleIdentifier"], !value.isEmpty {
            return value
        }
        if let value = environment["bundleIdentifier"] ?? environment["bundle_identifier"], !value.isEmpty {
            return value
        }

        let names = processChain.map(\.commandName)
        let arguments = processChain.map { $0.args.lowercased() }
        if names.contains("kitty") {
            return "net.kovidgoyal.kitty"
        }
        if arguments.contains(where: { $0.contains("/applications/kitty.app/") || $0.contains("/macos/kitten") }) {
            return "net.kovidgoyal.kitty"
        }
        if names.contains("ghostty") {
            return "com.mitchellh.ghostty"
        }
        if arguments.contains(where: { $0.contains("/applications/ghostty.app/") }) {
            return "com.mitchellh.ghostty"
        }
        if names.contains("iterm2") || names.contains("iterm2-server") {
            return "com.googlecode.iterm2"
        }
        if arguments.contains(where: { $0.contains("/applications/iterm.app/") || $0.contains("/applications/iterm2.app/") }) {
            return "com.googlecode.iterm2"
        }
        if names.contains("warp") {
            return "dev.warp.Warp-Stable"
        }
        if arguments.contains(where: { $0.contains("/applications/warp.app/") }) {
            return "dev.warp.Warp-Stable"
        }
        if names.contains("terminal") || names.contains("terminal.app") {
            return "com.apple.Terminal"
        }
        if arguments.contains(where: { $0.contains("/applications/terminal.app/") }) {
            return "com.apple.Terminal"
        }
        return nil
    }

    private static func resolveClientKind(
        environment: [String: String],
        bundleIdentifier: String?,
        processChain: [DetectorSupport.ProcEntry]
    ) -> TerminalClientKind {
        let termProgram = environment["TERM_PROGRAM"]?.lowercased()
        let bundle = bundleIdentifier?.lowercased()

        if bundle?.contains("kitty") == true || environment["KITTY_WINDOW_ID"] != nil {
            return .kitty
        }
        if bundle?.contains("ghostty") == true || termProgram == "ghostty" {
            return .ghostty
        }
        if bundle?.contains("iterm") == true || environment["ITERM_SESSION_ID"] != nil {
            return .iterm
        }
        if bundle?.contains("warp") == true || termProgram == "warpterminal" {
            return .warp
        }
        if bundle == "com.apple.terminal" || termProgram == "apple_terminal" || environment["TERM_SESSION_ID"] != nil {
            return .terminal
        }

        let names = Set(processChain.map(\.commandName))
        if names.contains("kitty") {
            return .kitty
        }
        if names.contains("ghostty") {
            return .ghostty
        }
        if names.contains("iterm2") || names.contains("iterm2-server") {
            return .iterm
        }
        if names.contains("warp") {
            return .warp
        }
        if names.contains("terminal") || names.contains("terminal.app") {
            return .terminal
        }

        return .unknown
    }

    private static func resolveSessionManagerKind(
        environment: [String: String],
        processChain: [DetectorSupport.ProcEntry]
    ) -> SessionManagerKind {
        if environment["TMUX"] != nil || environment["TMUX_PANE"] != nil {
            return .tmux
        }
        if environment["ZELLIJ"] != nil || environment["ZELLIJ_SESSION_NAME"] != nil {
            return .zellij
        }

        let names = Set(processChain.map(\.commandName))
        if names.contains("tmux") || names.contains("tmux: server") || names.contains("tmux:server") {
            return .tmux
        }
        if names.contains("zellij") {
            return .zellij
        }

        return (environment.isEmpty && processChain.isEmpty) ? .unknown : .none
    }

    private static func resolveOrigin(
        environment: [String: String],
        bundleIdentifier: String?,
        tty: String?,
        originHint: SessionOriginKind?
    ) -> SessionOriginKind {
        if let originHint, originHint != .unknown {
            return originHint
        }

        if let bundleIdentifier, bundleIdentifier == "com.openai.codex" {
            return .desktop
        }
        if let override = environment["CODEX_INTERNAL_ORIGINATOR_OVERRIDE"]?.lowercased(),
           override.contains("desktop") {
            return .desktop
        }
        if environment["CODEX_SHELL"] != nil || tty != nil || environment["TERM_PROGRAM"] != nil {
            return .cli
        }
        return .unknown
    }

    private static func resolveClientSessionID(
        environment: [String: String],
        clientKind: TerminalClientKind
    ) -> String? {
        switch clientKind {
        case .ghostty:
            return firstValue(in: environment, keys: ["GHOSTTY_SURFACE_ID", "ghostty_surface_id"])
        case .iterm:
            return environment["ITERM_SESSION_ID"]
        case .terminal:
            return environment["TERM_SESSION_ID"]
        case .kitty:
            return environment["KITTY_WINDOW_ID"]
        default:
            return environment["TERM_SESSION_ID"] ?? environment["ITERM_SESSION_ID"]
        }
    }

    private static func resolveClientControlAddress(
        environment: [String: String],
        clientKind: TerminalClientKind
    ) -> String? {
        switch clientKind {
        case .kitty:
            return environment["KITTY_LISTEN_ON"]
        default:
            return nil
        }
    }

    private static func resolveClientWindowID(
        environment: [String: String],
        clientKind: TerminalClientKind
    ) -> String? {
        switch clientKind {
        case .kitty:
            return environment["KITTY_WINDOW_ID"]
        default:
            return nil
        }
    }

    private static func resolveSessionManagerSessionID(
        environment: [String: String],
        kind: SessionManagerKind
    ) -> String? {
        switch kind {
        case .tmux:
            return environment["TMUX"]
        case .zellij:
            return firstValue(in: environment, keys: ["ZELLIJ_SESSION_NAME", "zellij_session_name"])
        default:
            return nil
        }
    }

    private static func resolveSessionManagerPaneID(
        environment: [String: String],
        kind: SessionManagerKind
    ) -> String? {
        switch kind {
        case .tmux:
            return environment["TMUX_PANE"]
        case .zellij:
            return firstValue(in: environment, keys: ["ZELLIJ_PANE_ID", "zellij_pane_id"])
        default:
            return nil
        }
    }

    private static func resolveSessionManagerTabName(
        environment: [String: String],
        kind: SessionManagerKind
    ) -> String? {
        switch kind {
        case .zellij:
            return firstValue(in: environment, keys: ["ZELLIJ_TAB_NAME", "zellij_tab_name"])
        default:
            return nil
        }
    }

    private static func resolveSessionManagerTabIndex(
        environment: [String: String],
        kind: SessionManagerKind
    ) -> Int? {
        switch kind {
        case .zellij:
            guard let value = firstValue(in: environment, keys: ["ZELLIJ_TAB_INDEX", "zellij_tab_index"]) else {
                return nil
            }
            return Int(value)
        default:
            return nil
        }
    }

    private static func firstValue(in environment: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = environment[key], !value.isEmpty {
                return value
            }
        }
        return nil
    }
}
