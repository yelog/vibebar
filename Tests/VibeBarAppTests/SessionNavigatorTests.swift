import Foundation
import Testing
import VibeBarCore
@testable import VibeBarApp

@Test func codexDesktopJumpPlanActivatesDesktopApp() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .unknown,
            bundleIdentifier: "com.openai.codex",
            sessionManagerKind: .unknown,
            origin: .desktop
        )
    )

    #expect(SessionNavigator.plan(for: session).strategies == [.activateBundle("com.openai.codex")])
}

@Test func tmuxJumpPlanUsesSocketAndPaneThenActivatesClientApp() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .kitty,
            bundleIdentifier: "net.kovidgoyal.kitty",
            clientControlAddress: "unix:/tmp/kitty-7033",
            tty: "ttys014",
            clientWindowID: "22",
            sessionManagerKind: .tmux,
            sessionManagerSessionID: "/tmp/tmux-501/default,123,0",
            sessionManagerPaneID: "%11",
            origin: .cli
        )
    )

    #expect(
        SessionNavigator.plan(for: session).strategies == [
            .focusTmuxPane(socketPath: "/tmp/tmux-501/default", paneID: "%11"),
            .focusKittyWindow(
                controlAddress: "unix:/tmp/kitty-7033",
                windowID: "22",
                pid: 123,
                cwd: "/tmp/project"
            ),
            .activateBundle("net.kovidgoyal.kitty"),
        ]
    )
}

@Test func kittyJumpPlanUsesControlAddressAndWindowID() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .kitty,
            bundleIdentifier: "net.kovidgoyal.kitty",
            clientControlAddress: "unix:/tmp/kitty-7033",
            tty: "ttys014",
            clientSessionID: "30",
            clientWindowID: "30",
            sessionManagerKind: .none,
            origin: .cli
        )
    )

    #expect(
        SessionNavigator.plan(for: session).strategies == [
            .focusKittyWindow(
                controlAddress: "unix:/tmp/kitty-7033",
                windowID: "30",
                pid: 123,
                cwd: "/tmp/project"
            ),
            .activateBundle("net.kovidgoyal.kitty"),
        ]
    )
}

@Test func zellijJumpPlanKeepsSessionContextAndClientFallback() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .ghostty,
            bundleIdentifier: "com.mitchellh.ghostty",
            tty: "ttys006",
            sessionManagerKind: .zellij,
            sessionManagerSessionID: "dev",
            sessionManagerPaneID: "3",
            sessionManagerTabName: "后端",
            origin: .cli
        )
    )

    #expect(
        SessionNavigator.plan(for: session).strategies == [
            .focusZellijSession(name: "dev", paneID: "3", tabName: "后端", cwd: "/tmp/project", commandName: "codex"),
            .activateBundle("com.mitchellh.ghostty"),
        ]
    )
}

@Test func tmuxSocketPathParsesRawEnvironmentValue() {
    #expect(SessionNavigator.tmuxSocketPath(from: "/tmp/tmux-501/default,123,0") == "/tmp/tmux-501/default")
    #expect(SessionNavigator.tmuxSocketPath(from: nil) == nil)
}

@Test func parseZellijLayoutCapturesTabNamesAndCwds() {
    let layout = """
    layout {
        cwd "/Users/yelog/workspace/swift/SnapTra Translator"
        tab name="SnapTra Translator" focus=true {
            pane
        }
        tab name="VibeBar" {
            pane {
                cwd "/Users/yelog/workspace/swift/VibeBar"
            }
        }
    }
    """

    #expect(
        SessionNavigator.parseZellijLayout(layout) == [
            ZellijLayoutTab(
                name: "SnapTra Translator",
                isFocused: true,
                cwdCandidates: ["/Users/yelog/workspace/swift/SnapTra Translator"]
            ),
            ZellijLayoutTab(
                name: "VibeBar",
                isFocused: false,
                cwdCandidates: ["/Users/yelog/workspace/swift/VibeBar"]
            ),
        ]
    )
}

@Test func inferZellijTabNameMatchesTabByCwd() {
    let layout = """
    layout {
        cwd "/Users/yelog/workspace/swift/SnapTra Translator"
        tab name="SnapTra Translator" focus=true {
            pane
        }
        tab name="VibeBar" {
            pane {
                cwd "/Users/yelog/workspace/swift/VibeBar"
            }
        }
    }
    """

    #expect(
        SessionNavigator.inferZellijTabName(
            from: layout,
            cwd: "/Users/yelog/workspace/swift/VibeBar"
        ) == "VibeBar"
    )
}

@Test func inferZellijTabNameFallsBackToSingleTab() {
    let layout = """
    layout {
        cwd "/Users/yelog/workspace/swift/SnapTra Translator"
        tab name="SnapTra Translator" focus=true {
            pane
        }
    }
    """

    #expect(
        SessionNavigator.inferZellijTabName(
            from: layout,
            cwd: "/Users/yelog/workspace/swift/AnotherProject"
        ) == "SnapTra Translator"
    )
}

@Test func resolveKittyTargetPrefersExactWindowID() {
    let output = """
    [
      {
        "id": 1,
        "tabs": [
          {
            "id": 9,
            "title": "NVIM:VibeBar",
            "windows": [
              {
                "id": 18,
                "cwd": "/Users/yelog/workspace/swift/VibeBar",
                "pid": 15780,
                "is_active": false,
                "foreground_processes": [
                  { "pid": 91639, "cwd": "/Users/yelog/workspace/swift/VibeBar" }
                ]
              },
              {
                "id": 30,
                "cwd": "/Users/yelog/workspace/swift/VibeBar",
                "pid": 93240,
                "is_active": false,
                "foreground_processes": [
                  { "pid": 70451, "cwd": "/Users/yelog/workspace/swift/VibeBar" }
                ]
              }
            ]
          }
        ]
      }
    ]
    """

    #expect(
        SessionNavigator.resolveKittyTarget(
            from: output,
            requestedWindowID: "30",
            pid: 91639,
            cwd: "/Users/yelog/workspace/swift/VibeBar"
        ) == KittyRemoteTarget(
            osWindowID: 1,
            tabID: 9,
            tabTitle: "NVIM:VibeBar",
            tabIndex: 1,
            windowID: "30"
        )
    )
}

@Test func resolveKittyTargetFallsBackToPidAndCwd() {
    let output = """
    [
      {
        "id": 1,
        "tabs": [
          {
            "id": 9,
            "title": "NVIM:VibeBar",
            "windows": [
              {
                "id": 18,
                "cwd": "/Users/yelog/workspace/swift/VibeBar",
                "pid": 15780,
                "is_active": false,
                "foreground_processes": [
                  { "pid": 91639, "cwd": "/Users/yelog/workspace/swift/VibeBar" }
                ]
              },
              {
                "id": 30,
                "cwd": "/Users/yelog/workspace/swift/VibeBar",
                "pid": 93240,
                "is_active": false,
                "foreground_processes": [
                  { "pid": 70451, "cwd": "/Users/yelog/workspace/swift/VibeBar" }
                ]
              }
            ]
          }
        ]
      }
    ]
    """

    #expect(
        SessionNavigator.resolveKittyTarget(
            from: output,
            requestedWindowID: nil,
            pid: 70451,
            cwd: "/Users/yelog/workspace/swift/VibeBar"
        ) == KittyRemoteTarget(
            osWindowID: 1,
            tabID: 9,
            tabTitle: "NVIM:VibeBar",
            tabIndex: 1,
            windowID: "30"
        )
    )
}

@Test func activeZellijTabCapturesPanePathsAndFocus() {
    let layout = """
    layout {
        cwd "/Users/yelog/workspace/swift/SnapTra Translator"
        tab name="SnapTra Translator" focus=true hide_floating_panes=true {
            pane split_direction="vertical" {
                pane command="claude" size="50%" {
                    args "--dangerously-skip-permissions"
                }
                pane focus=true size="50%"
            }
            pane size=1 borderless=true {
                plugin location="status"
            }
        }
    }
    """

    #expect(
        SessionNavigator.activeZellijTab(from: layout) == ZellijActiveTab(
            name: "SnapTra Translator",
            panes: [
                ZellijPaneDescriptor(
                    commandName: "claude",
                    cwd: "/Users/yelog/workspace/swift/SnapTra Translator",
                    isFocused: false,
                    path: [
                        ZellijPathSegment(direction: .horizontal, childIndex: 0),
                        ZellijPathSegment(direction: .vertical, childIndex: 0),
                    ]
                ),
                ZellijPaneDescriptor(
                    commandName: nil,
                    cwd: "/Users/yelog/workspace/swift/SnapTra Translator",
                    isFocused: true,
                    path: [
                        ZellijPathSegment(direction: .horizontal, childIndex: 0),
                        ZellijPathSegment(direction: .vertical, childIndex: 1),
                    ]
                ),
            ]
        )
    )
}

@Test func nextZellijMoveTargetsClaudePaneFromSiblingSplit() {
    let layout = """
    layout {
        cwd "/Users/yelog/workspace/swift/SnapTra Translator"
        tab name="SnapTra Translator" focus=true hide_floating_panes=true {
            pane split_direction="vertical" {
                pane command="claude" size="50%" {
                    args "--dangerously-skip-permissions"
                }
                pane focus=true size="50%"
            }
            pane size=1 borderless=true {
                plugin location="status"
            }
        }
    }
    """

    #expect(
        SessionNavigator.nextZellijMove(
            from: layout,
            commandName: "claude",
            cwd: "/Users/yelog/workspace/swift/SnapTra Translator"
        ) == .move(.left)
    )
}

@Test func nextZellijMoveReturnsAlreadyFocusedWhenTargetPaneOwnsFocus() {
    let layout = """
    layout {
        cwd "/Users/yelog/workspace/swift/SnapTra Translator"
        tab name="SnapTra Translator" focus=true hide_floating_panes=true {
            pane split_direction="vertical" {
                pane command="claude" focus=true size="50%" {
                    args "--dangerously-skip-permissions"
                }
                pane size="50%"
            }
        }
    }
    """

    #expect(
        SessionNavigator.nextZellijMove(
            from: layout,
            commandName: "claude",
            cwd: "/Users/yelog/workspace/swift/SnapTra Translator"
        ) == .alreadyFocused
    )
}

private func makeSession(
    terminalContext: TerminalContext?
) -> SessionSnapshot {
    SessionSnapshot(
        id: "codex-session",
        tool: .codex,
        pid: 123,
        status: .running,
        source: .sessionFile,
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        updatedAt: Date(timeIntervalSince1970: 1_700_000_030),
        cwd: "/tmp/project",
        command: ["codex"],
        title: "修复 Codex 跳转",
        terminalContext: terminalContext
    )
}
