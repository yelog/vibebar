# VibeBar

**[English](README.md)** · [中文](README_zh.md) · [日本語](README_ja.md) · [한국어](README_ko.md)

VibeBar is a lightweight macOS menu bar app that monitors live TUI session activity for **Claude Code**, **Codex**, **OpenCode**, **Aider**, **Gemini CLI**, and **GitHub Copilot**.

<table>
  <tr>
    <th>Agent Sessions and Token Usage Trend</th>
    <th>Agent Session and Token Usage Trend</th>
  </tr>
  <tr>
    <td>
      <img src="docs/images/vibebar-light.png" />
    </td>
    <td>
      <img src="docs/images/vibebar-dark.png" />
    </td>
  </tr>
</table>

Multiple icon styles and color schemes are provided, which can be configured in the settings.

<img src="docs/images/vibebar-setting.png" alt="VibeBar setting screenshot" width="600" />

## Recommended Integration (Important)

- **Claude Code**: use the VibeBar plugin (recommended).
- **OpenCode**: use the VibeBar plugin (recommended).
- **Aider**: use `vibebar` wrapper (recommended), and optionally `vibebar notify` for better awaiting-input signals.
- **Gemini CLI**: use `vibebar` wrapper (recommended). In headless/prompt mode, wrapper auto-enables `--output-format stream-json` unless already set.
- **GitHub Copilot**: use `vibebar` wrapper when you want wrapper-level tracking. Current built-in detection otherwise relies on process scanning.
- **Pi / Oh My Pi**: use the managed extension (recommended). Install it from CLI settings; it reports real-time session state directly from a directly-launched `pi` / `omp`, with no wrapper required. Oh My Pi installation covers the default profile and any named profiles that exist at install time — run update after creating a new profile. Process scan remains the fallback.
- **Codex**: VibeBar now prefers local session-file detection from `~/.codex/session_index.jsonl` and `~/.codex/sessions/**/rollout-*.jsonl`, and falls back to `processScan`. If you install the managed Codex hook from the CLI settings, VibeBar can also handle `PermissionRequest`, `AskUserQuestion`, and `PlanReview` inline from the menu / notch UI. `vibebar codex` wrapper remains optional when you want wrapper-level tracking.
- `vibebar` wrapper supports `claude` / `codex` / `opencode` / `aider` / `gemini` / `copilot`, while plugin integration remains the preferred path where available.

## Features

- Real-time menu bar status for multiple sessions and tools.
- Optional notch display mode on supported MacBook screens, extending a small black icon area from the right side of the notch and automatically falling back to the standard menu bar entry on unsupported primary displays.
- Session states: `running`, `awaiting_input`, `idle`, `stopped`, `unknown`.
- Inline interaction reply flow for Codex CLI hooks: approve / deny permissions, answer questions, and review plans without returning to the terminal.
- Four data channels for reliability:
  - PTY wrapper (`vibebar`)
  - Local plugin events via `vibebar-agent`
  - Local session files (`Codex` session index / rollout, `Gemini` transcript)
  - `ps` process scanning fallback
- In-app plugin management (install/uninstall/update) for Claude Code, OpenCode, and Pi / Oh My Pi.
- In-app wrapper command management for `vibebar`.
- Multiple icon styles, color themes, launch at login, and update checks.
- Multi-language UI (`English`, `中文`, `日本語`, `한국어`).

## Token Usage Tracking

VibeBar tracks token usage across supported AI tools with detailed analytics and visualization:

**Supported Tools:**
- **Claude Code** — reads transcript `.jsonl` files recursively under `~/.config/claude/projects` and `~/.claude/projects`.
- **Codex** — reads `.jsonl` session files recursively under `~/.codex/sessions`.
- **OpenCode** — reads from `~/.local/share/opencode/opencode.db`.
- **Gemini CLI** — reads chat JSON files under `~/.gemini/tmp/**/chats/*.json`.

Environment overrides are supported where the upstream CLI provides them: `CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `OPENCODE_DATA_DIR`, and `GEMINI_CLI_HOME`.

**Token Metrics:**
- Input tokens, Output tokens
- Cache read tokens, Cache write tokens
- Total tokens and estimated cost in USD
- Pricing data is bundled and can be refreshed/cached under VibeBar's Application Support directory.

**Visualization Options:**
- **GitHub-style Heatmap** — 39-week activity matrix with color-coded intensity
- **Bar Chart** — Stacked bars showing usage by time period
- **Line Chart** — Trend lines for usage over time

**Configuration:**
- Toggle between **Tokens** or **Cost** view
- Adjust granularity: Hour / Day / Week / Month
- Group by: Tool / Model / None
- Set refresh interval: 5min / 15min / 30min / 1hour
- Customize maximum series displayed

Access via the menu bar dropdown to view your AI usage patterns and costs at a glance.

## Project Layout

- `VibeBarCore`: models, storage, aggregation, scanners, plugin/wrapper detection.
- `VibeBarApp`: macOS menu bar app and settings UI.
- `VibeBarCLI` (`vibebar`): PTY wrapper around target CLIs.
- `VibeBarAgent` (`vibebar-agent`): local Unix socket server for plugin events.
- `plugins/*`: Claude Code, OpenCode, and Pi / Oh My Pi extension packages.

## How Session Detection Works

VibeBar merges data from 4 channels:

1. `vibebar` PTY wrapper: high-fidelity interaction states.
2. `vibebar-agent` socket events: plugin lifecycle/status updates.
3. Local session files: Codex session index / rollout files, Gemini transcripts.
4. `ps` scan fallback: process-based discovery when stronger sources are missing.

Default detection methods by tool:

- Claude Code: plugin + transcript files.
- Codex: managed hook + session files + process scan.
- OpenCode: plugin + local HTTP API + process scan.
- Pi / Oh My Pi: managed extension + process scan.
- Gemini CLI: transcript files.
- Aider: process scan.
- GitHub Copilot: process scan.

State priority at tool level:

`running > awaiting_input > idle > stopped > unknown`

Runtime data paths:

- Session files: `~/Library/Application Support/VibeBar/sessions/*.json`
- Interaction requests: `~/Library/Application Support/VibeBar/interactions/`
- Agent socket: `~/Library/Application Support/VibeBar/runtime/agent.sock`
- Usage cache/state: `~/Library/Application Support/VibeBar/usage/`
- Pricing cache: `~/Library/Application Support/VibeBar/pricing/`
- Managed wrapper version: `~/Library/Application Support/VibeBar/bin/vibebar.version`

Set `VIBEBAR_AGENT_SOCKET` to override the socket path used by `vibebar notify` and managed hooks.

## Installation

### Option A: Download app (recommended)

1. Download latest `VibeBar-*-universal.dmg` from [GitHub Releases](https://github.com/yelog/VibeBar/releases).
2. Drag `VibeBar.app` to `Applications`.
3. First launch: right-click app and choose **Open** (Gatekeeper).

### Option B: Homebrew

Add the shared tap and install:

```bash
brew tap yelog/tap
brew install --cask yelog/tap/vibebar
```

If Homebrew reports that `vibebar` exists in multiple taps, use the fully-qualified name above or remove the old tap:

```bash
brew untap yelog/vibebar
brew install --cask yelog/tap/vibebar
```

**Upgrade:**

```bash
brew upgrade --cask yelog/tap/vibebar
```

### Option C: Build from source

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

4. Optional: run Codex with wrapper for wrapper-level tracking:

```bash
swift run vibebar codex -- --model gpt-5-codex
```

If you want inline Codex approvals and question replies, open **Settings → CLI**, switch Codex detection to **Hook**, and install the managed Codex hook. VibeBar will write `~/.codex/hooks.json`, enable `codex_hooks = true`, and register:

- `SessionStart`
- `SessionEnd`
- `UserPromptSubmit`
- `PreToolUse`
- `PostToolUse`
- `Stop`
- `PermissionRequest`
- `AskUserQuestion`
- `PlanReview`

VibeBar only manages its own Codex hook entries when reinstalling or uninstalling. Permission requests wait for a menu/notch reply for up to 3600 seconds; non-interaction hook events use short best-effort delivery.

5. Run Aider with wrapper (recommended path):

```bash
swift run vibebar aider -- --model sonnet
```

6. Optional: forward Aider notifications into VibeBar state updates:

```bash
aider --notifications --notifications-command "vibebar notify aider awaiting_input"
```

7. Run Gemini CLI with wrapper:

```bash
swift run vibebar gemini -p "explain this codebase"
```

For Gemini prompt/headless invocations (`-p`, `--prompt`, `--stdin`, or non-TTY stdin), `vibebar` automatically adds `--output-format stream-json` unless you already provide `--output-format`.

Gemini hooks integration example (`.gemini/settings.json`):

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "vibebar notify gemini session_start session_id=$GEMINI_SESSION_ID" }]
    }],
    "AfterAgent": [{
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "vibebar notify gemini after_agent session_id=$GEMINI_SESSION_ID" }]
    }],
    "SessionEnd": [{
      "matcher": "*",
      "hooks": [{ "type": "command", "command": "vibebar notify gemini session_end session_id=$GEMINI_SESSION_ID" }]
    }]
  }
}
```

8. Optional fallback: run Claude/OpenCode/GitHub Copilot via wrapper when plugin or stronger detection is unavailable:

```bash
swift run vibebar claude
swift run vibebar opencode
swift run vibebar copilot
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
swift run vibebar --help
swift run vibebar --version

# Test
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
- Codex has no dedicated plugin package in this repo yet; accurate detection relies on local session files, optional hooks metadata, and process correlation.
- Aider has no native plugin event channel in this repo yet; use `vibebar notify` via `--notifications-command` for better awaiting-input detection.
- Gemini CLI transcript parsing is auxiliary only; it augments hook/process detection and should not be treated as a primary real-time source.
- GitHub Copilot has no managed plugin or hook package in this repo yet; built-in detection is process-scan only unless you run it through the wrapper or forward custom `vibebar notify` events.
- Automated tests are still minimal.

## Acknowledgments

This project was inspired by [ccusage](https://github.com/ryoppippi/ccusage). Thanks to [@ryoppippi](https://github.com/ryoppippi) for the great idea and implementation.
