# VibeBar

VibeBar is a lightweight macOS menu bar app that monitors live TUI session activity for **Claude Code**, **Codex**, and **OpenCode**.

<img src="vibebar.png" alt="VibeBar screenshot" width="600" />

Multiple icon styles and color schemes are provided, which can be configured in the settings.

<img src="vibebar-setting.png" alt="VibeBar setting screenshot" width="600" />

## Recommended Integration (Important)

- **Claude Code**: use the VibeBar plugin (recommended).
- **OpenCode**: use the VibeBar plugin (recommended).
- **Codex**: use `vibebar` wrapper (recommended), because Codex currently has no plugin system in this repo.
- `vibebar` wrapper still supports `claude` / `opencode`, but plugin integration is the preferred path for those two tools.

## Features

- Real-time menu bar status for multiple sessions and tools.
- Session states: `running`, `awaiting_input`, `idle`, `stopped`, `unknown`.
- Three data channels for reliability:
  - PTY wrapper (`vibebar`)
  - Local plugin events via `vibebar-agent`
  - `ps` process scanning fallback
- In-app plugin management (install/uninstall/update) for Claude/OpenCode.
- In-app wrapper command management for `vibebar`.
- Multiple icon styles, color themes, launch at login, and update checks.
- Multi-language UI (`English`, `中文`, `日本語`, `한국어`).

## Project Layout

- `VibeBarCore`: models, storage, aggregation, scanners, plugin/wrapper detection.
- `VibeBarApp`: macOS menu bar app and settings UI.
- `VibeBarCLI` (`vibebar`): PTY wrapper around target CLIs.
- `VibeBarAgent` (`vibebar-agent`): local Unix socket server for plugin events.
- `plugins/*`: Claude/OpenCode plugin packages.

## How Session Detection Works

VibeBar merges data from 3 channels:

1. `vibebar` PTY wrapper: high-fidelity interaction states.
2. `vibebar-agent` socket events: plugin lifecycle/status updates.
3. `ps` scan fallback: process-based discovery when stronger sources are missing.

State priority at tool level:

`running > awaiting_input > idle > stopped > unknown`

Runtime data paths:

- Session files: `~/Library/Application Support/VibeBar/sessions/*.json`
- Agent socket: `~/Library/Application Support/VibeBar/runtime/agent.sock`

## Installation

### Option A: Download app (recommended)

1. Download latest `VibeBar-*-universal.dmg` from [GitHub Releases](https://github.com/yelog/VibeBar/releases).
2. Drag `VibeBar.app` to `Applications`.
3. First launch: right-click app and choose **Open** (Gatekeeper).

### Option B: Build from source

Requirements: macOS 13+, Xcode Command Line Tools, Swift 6.2.

```bash
swift build
```

## Quick Start (Source Build)

1. Start app:

```bash
swift run VibeBarApp
```

2. Start agent (recommended for plugin events):

```bash
swift run vibebar-agent --verbose
```

3. Install local plugins for Claude/OpenCode:

```bash
bash scripts/install/setup-local-plugins.sh
```

4. Run Codex with wrapper (recommended path):

```bash
swift run vibebar codex -- --model gpt-5-codex
```

5. Optional fallback: run Claude/OpenCode via wrapper when plugin is unavailable:

```bash
swift run vibebar claude
swift run vibebar opencode
```

Plugin docs:

- `plugins/README.md`
- `plugins/claude-vibebar-plugin/README.md`
- `plugins/opencode-vibebar-plugin/README.md`

## Development Commands

```bash
# Build
swift build
swift build -c release

# Run
swift run VibeBarApp
swift run vibebar-agent --verbose
swift run vibebar codex

# Test (placeholder)
swift test
```

Package universal `.dmg`:

```bash
bash scripts/build/package-app.sh
```

## Troubleshooting

- No menu bar icon: ensure local macOS GUI session (not headless/SSH).
- Stale sessions: use **Purge Stale** and verify session files path above.
- Missing plugin events: ensure `vibebar-agent` is running and check socket path:

```bash
swift run vibebar-agent --print-socket-path
```

## Limitations

- Without plugins, awaiting-input detection relies on heuristics.
- Codex has no plugin event channel in this repo yet.
- Automated tests are still minimal.
