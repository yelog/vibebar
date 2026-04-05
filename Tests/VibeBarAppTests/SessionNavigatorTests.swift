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

@Test func ghosttyJumpPlanUsesTerminalAndActivatesClientApp() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .ghostty,
            bundleIdentifier: "com.mitchellh.ghostty",
            clientWindowID: "window-1",
            clientTabID: "tab-2",
            clientNativeSessionID: "terminal-3",
            sessionManagerKind: .none,
            origin: .cli
        )
    )

    #expect(
        SessionNavigator.plan(for: session).strategies == [
            .focusGhosttyTerminal(
                windowID: "window-1",
                tabID: "tab-2",
                terminalID: "terminal-3",
                cwd: "/tmp/project"
            ),
            .activateBundle("com.mitchellh.ghostty"),
        ]
    )
}

@Test func weztermJumpPlanUsesPaneAndActivatesClientApp() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .wezterm,
            bundleIdentifier: "com.github.wez.wezterm",
            clientControlAddress: "/tmp/wezterm-gui.sock",
            clientSessionID: "42",
            sessionManagerKind: .none,
            origin: .cli
        )
    )

    #expect(
        SessionNavigator.plan(for: session).strategies == [
            .focusWezTermPane(controlAddress: "/tmp/wezterm-gui.sock", paneID: "42"),
            .activateBundle("com.github.wez.wezterm"),
        ]
    )
}

@Test func iTermJumpPlanUsesSessionAndActivatesClientApp() {
    let session = makeSession(
        terminalContext: TerminalContext(
            clientKind: .iterm,
            bundleIdentifier: "com.googlecode.iterm2",
            tty: "ttys007",
            clientWindowID: "5001",
            clientNativeSessionID: "session-2",
            clientTabIndex: 3,
            sessionManagerKind: .none,
            origin: .cli
        )
    )

    #expect(
        SessionNavigator.plan(for: session).strategies == [
            .focusITermSession(
                windowID: "5001",
                tabIndex: 3,
                tty: "ttys007",
                uniqueID: "session-2"
            ),
            .activateBundle("com.googlecode.iterm2"),
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
            .focusGhosttyTerminal(windowID: nil, tabID: nil, terminalID: nil, cwd: "/tmp/project"),
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

@Test func inferZellijTabIndexPrefersExplicitTabName() {
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
        SessionNavigator.inferZellijTabIndex(
            from: layout,
            tabName: "VibeBar",
            cwd: "/Users/yelog/workspace/swift/AnotherProject"
        ) == 2
    )
}

@Test func inferZellijTabIndexFallsBackToCwd() {
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
        SessionNavigator.inferZellijTabIndex(
            from: layout,
            tabName: nil,
            cwd: "/Users/yelog/workspace/swift/VibeBar"
        ) == 2
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

@Test func resolveWezTermTargetPrefersExactPaneID() {
    let output = """
    [
      {
        "window_id": 1,
        "tab_id": 10,
        "pane_id": 100,
        "title": "redis",
        "cwd": "file:///Users/yelog/workspace/rust/rust-redis-desktop"
      },
      {
        "window_id": 1,
        "tab_id": 11,
        "pane_id": 101,
        "title": "calendar-main",
        "cwd": "file:///Users/yelog/workspace/swift/calendar-pro"
      },
      {
        "window_id": 1,
        "tab_id": 11,
        "pane_id": 102,
        "title": "calendar-side",
        "cwd": "file:///Users/yelog/workspace/swift/calendar-pro"
      }
    ]
    """

    #expect(
        SessionNavigator.resolveWezTermTarget(
            from: output,
            requestedPaneID: "102",
            cwd: "/Users/yelog/workspace/swift/calendar-pro"
        ) == WezTermRemoteTarget(
            windowID: "1",
            tabID: "11",
            paneID: "102",
            tabTitle: "calendar-side",
            tabIndex: 2
        )
    )
}

@Test func resolveWezTermTargetFallsBackToUniqueCwd() {
    let output = """
    [
      {
        "window_id": 1,
        "tab_id": 10,
        "pane_id": 100,
        "title": "redis",
        "cwd": "file:///Users/yelog/workspace/rust/rust-redis-desktop"
      },
      {
        "window_id": 1,
        "tab_id": 11,
        "pane_id": 101,
        "title": "vibebar",
        "cwd": "file:///Users/yelog/workspace/swift/VibeBar"
      }
    ]
    """

    #expect(
        SessionNavigator.resolveWezTermTarget(
            from: output,
            requestedPaneID: nil,
            cwd: "/Users/yelog/workspace/swift/VibeBar"
        ) == WezTermRemoteTarget(
            windowID: "1",
            tabID: "11",
            paneID: "101",
            tabTitle: "vibebar",
            tabIndex: 2
        )
    )
}

@Test func resolveGhosttyTargetPrefersUniqueCwdTabAndTerminal() {
    let output = """
    tab\twindow-a\ttab-a\t1\t1\tSnapTra Translator
    terminal\twindow-a\ttab-a\tterminal-a\t1\tclaude\t/Users/yelog/workspace/swift/SnapTra Translator
    tab\twindow-a\ttab-b\t2\t0\tVibeBar
    terminal\twindow-a\ttab-b\tterminal-b\t1\topencode\t/Users/yelog/workspace/swift/VibeBar
    """

    #expect(
        SessionNavigator.resolveGhosttyTarget(
            from: output,
            cwd: "/Users/yelog/workspace/swift/VibeBar",
            titleHints: []
        ) == GhosttyRemoteTarget(
            windowID: "window-a",
            tabID: "tab-b",
            tabTitle: "VibeBar",
            tabIndex: 2,
            terminalID: "terminal-b"
        )
    )
}

@Test func resolveGhosttyTargetFallsBackToTabWhenPaneIsAmbiguous() {
    let output = """
    tab\twindow-a\ttab-a\t1\t1\tSnapTra Translator
    terminal\twindow-a\ttab-a\tterminal-a\t1\tclaude\t/Users/yelog/workspace/swift/SnapTra Translator
    terminal\twindow-a\ttab-a\tterminal-b\t0\tzsh\t/Users/yelog/workspace/swift/SnapTra Translator
    """

    #expect(
        SessionNavigator.resolveGhosttyTarget(
            from: output,
            cwd: "/Users/yelog/workspace/swift/SnapTra Translator",
            titleHints: []
        ) == GhosttyRemoteTarget(
            windowID: "window-a",
            tabID: "tab-a",
            tabTitle: "SnapTra Translator",
            tabIndex: 1,
            terminalID: "terminal-a"
        )
    )
}

@Test func resolveGhosttyTargetPrefersTerminalMatchingToolHintWithinSameCwd() {
    let output = """
    tab\twindow-a\ttab-a\t1\t1\tyelog@yelog-mbp:~/.config
    terminal\twindow-a\ttab-a\tterminal-claude\t0\t✳ Claude Code\t/Users/yelog/.config
    terminal\twindow-a\ttab-a\tterminal-shell\t1\tyelog@yelog-mbp:~/.config\t/Users/yelog/.config
    tab\twindow-a\ttab-b\t2\t0\tyelog@yelog-mbp:~
    terminal\twindow-a\ttab-b\tterminal-home\t1\tyelog@yelog-mbp:~\t/Users/yelog
    """

    #expect(
        SessionNavigator.resolveGhosttyTarget(
            from: output,
            cwd: "/Users/yelog/.config",
            titleHints: ["Claude Code", "claude"]
        ) == GhosttyRemoteTarget(
            windowID: "window-a",
            tabID: "tab-a",
            tabTitle: "yelog@yelog-mbp:~/.config",
            tabIndex: 1,
            terminalID: "terminal-claude"
        )
    )
}

@Test func resolveITermTargetMatchesTTYAndReturnsDisplayTabIndex() {
    let output = """
    window\t1001
    tab\t1001\t0
    session\t1001\t0\tw0t0p0\tsession-1\tttys006\tzsh
    tab\t1001\t1
    session\t1001\t1\tw0t1p0\tsession-2\tttys007\tclaude
    """

    #expect(
        SessionNavigator.resolveITermTarget(
            from: output,
            tty: "ttys007",
            sessionID: nil
        ) == ITermRemoteTarget(
            windowID: "1001",
            rawTabIndex: 1,
            displayTabIndex: 2,
            sessionID: "w0t1p0",
            uniqueID: "session-2"
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
