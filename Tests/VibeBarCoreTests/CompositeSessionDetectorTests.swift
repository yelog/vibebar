import Foundation
import Testing
@testable import VibeBarCore

@Test func mergeGroupRetainsTerminalContextFromLowerPriorityCandidate() {
    let detector = CompositeSessionDetector()
    let httpSession = SessionSnapshot(
        id: "opencode-http-abc",
        tool: .opencode,
        pid: 25022,
        status: .idle,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_100),
        cwd: "/Users/test/project",
        command: ["opencode"],
        title: "HTTP Session"
    )
    let processSession = SessionSnapshot(
        id: "ps-25022",
        tool: .opencode,
        pid: 25022,
        status: .idle,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_090),
        cwd: "/Users/test/project",
        command: ["opencode"],
        terminalContext: TerminalContext(
            clientKind: .kitty,
            bundleIdentifier: "net.kovidgoyal.kitty",
            tty: "ttys014",
            sessionManagerKind: .none,
            origin: .cli
        )
    )

    let merged = detector.mergeGroup([httpSession, processSession])

    #expect(merged?.id == "opencode-http-abc")
    #expect(merged?.title == "HTTP Session")
    #expect(merged?.terminalContext?.clientKind == .kitty)
    #expect(merged?.terminalContext?.bundleIdentifier == "net.kovidgoyal.kitty")
}

@Test func selectBestPrefersRicherSessionWhenPriorityMatches() {
    let detector = CompositeSessionDetector()
    let plain = SessionSnapshot(
        id: "ps-1",
        tool: .claudeCode,
        pid: 1,
        status: .idle,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_010),
        cwd: "/Users/test/project",
        command: ["claude"]
    )
    let rich = SessionSnapshot(
        id: "ps-1-rich",
        tool: .claudeCode,
        pid: 1,
        status: .idle,
        source: .processScan,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_010),
        cwd: "/Users/test/project",
        command: ["claude"],
        title: "修复问题",
        terminalContext: TerminalContext(
            clientKind: .ghostty,
            bundleIdentifier: "com.mitchellh.ghostty",
            tty: "ttys006",
            sessionManagerKind: .zellij,
            sessionManagerSessionID: "dev",
            sessionManagerPaneID: "3",
            origin: .cli
        )
    )

    let best = detector.selectBest(from: [plain, rich])

    #expect(best?.id == "ps-1-rich")
    #expect(detector.richnessScore(for: rich) > detector.richnessScore(for: plain))
}
