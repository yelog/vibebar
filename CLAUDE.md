# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run Commands

```bash
# Build
swift build
swift build -c release

# Run app
swift run VibeBarApp

# Run agent (for plugin events)
swift run vibebar-agent --verbose

# Run CLI wrapper
swift run vibebar claude
swift run vibebar opencode
swift run vibebar codex -- --model gpt-5-codex

# Package universal .dmg
bash scripts/build/package-app.sh

# Install local plugins for development
bash scripts/install/setup-local-plugins.sh
```

## Architecture Overview

VibeBar is a macOS menu bar app that monitors TUI session activity for CLI agent tools (Claude Code, Codex, OpenCode, Aider, Gemini CLI, GitHub Copilot).

### Module Structure

- **VibeBarCore**: Core library with models, detection, storage, localization
- **VibeBarApp**: macOS menu bar app (SwiftUI + AppKit)
- **VibeBarCLI** (`vibebar`): PTY wrapper for launching CLI tools with session tracking
- **VibeBarAgent** (`vibebar-agent`): Unix socket server for plugin event ingestion

### Session Detection Pipeline

Detection channels with priority-based merging:

1. **Plugin** (priority 6): Real-time push via `vibebar-agent` socket - highest accuracy
2. **HTTP API** (priority 5): Query tool HTTP endpoints (OpenCode port 4096)
3. **Session File** (priority 4): Parse Codex local session index / rollout files
4. **Log File** (priority 3): Parse tool logs (Claude Code)
5. **Transcript File** (priority 2): Parse transcript files (Gemini)
6. **Process Scan** (priority 1): Fallback `ps` scanning - lowest accuracy

Session data flows:
- Plugins → `vibebar-agent` → session files in `~/Library/Application Support/VibeBar/sessions/`
- Codex session files → `CodexSessionDetector` → merged snapshots
- Wrapper → writes session files directly
- Detectors → `CompositeSessionDetector.detectSessions()` → merged in `MonitorViewModel.refreshNow()`

### Key Types

- `ToolKind`: Enum of supported CLI tools (claudeCode, codex, opencode, aider, gemini, githubCopilot)
- `SessionSnapshot`: Single session with tool, pid, status, cwd, timestamps
- `ToolActivityState`: Session state (idle, running, awaitingInput, unknown)
- `DetectionMethodPreference`: Detection methods that can be enabled/disabled per tool
- `CLISettingsManager`: Per-tool configuration stored in UserDefaults

### Detection Configuration

Each tool has configurable detection methods via `CLISettingsManager`:
- Claude Code: plugin, logFile, processScan
- Codex: sessionFile, processScan
- OpenCode: plugin, httpAPI, processScan
- GitHub Copilot: processScan only
- Gemini: transcriptFile, processScan
- Aider: processScan only

### Plugin System

Two plugins in `plugins/`:
- `claude-vibebar-plugin`: Claude Code plugin via `claude plugin install`
- `opencode-vibebar-plugin`: OpenCode plugin via config file

Plugin management handled by `PluginDetector` with install/uninstall/update operations.

### Runtime Paths

- Sessions: `~/Library/Application Support/VibeBar/sessions/*.json`
- Agent socket: `~/Library/Application Support/VibeBar/runtime/agent.sock`
- Plugins: `plugins/` in source mode, `Contents/Resources/plugins/` in app bundle

### Localization

L10n system with 4 languages (zh, en, ja, ko). String keys in `L10nStrings.swift`, accessed via `L10n.shared.string(.keyName)`.

## Code Conventions

- Swift 6 with strict concurrency (`Sendable`, `@MainActor`)
- SwiftUI for UI, AppKit for status item/window management
- UserDefaults for persistence, JSON files for session storage
- Resource bundles: SPM processes PNG icons in `VibeBarApp/Resources/`
