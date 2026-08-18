# Pi and Oh My Pi Support Design

**Date:** 2026-08-18

## Goal

Add Pi and Oh My Pi (OMP) as separate VibeBar tools with real-time session state and metadata. The first release includes extension events, process-scan fallback, extension installation, settings integration, and normal menu/notch/notification presentation. Usage aggregation and interaction replies are explicitly out of scope.

## Product Model

- Pi and OMP are separate `ToolKind` cases.
- Pi uses executable `pi` and the default extension root `~/.pi/agent/extensions`.
- OMP uses executable `omp`, the default extension root `~/.omp/agent/extensions`, and profile roots under `~/.omp/profiles/<name>/agent/extensions`.
- OMP installation targets the default profile and every named profile that exists at installation time.
- A profile created later is picked up by the next install or update operation.

## Architecture

Use an extension-first integration with process scanning as fallback:

```text
Pi / OMP lifecycle
  -> bundled VibeBar extension
  -> VibeBar Agent Unix socket
  -> AgentEvent
  -> AgentEventReducer
  -> SessionFileStore
  -> MonitorViewModel merge
  -> menu / notch / notifications

ProcessScanner
  -> PID / cwd / terminal context fallback
  -> MonitorViewModel merge
```

The extensions send the existing `{ "kind": "event", "event": ... }` envelope. No new IPC protocol is introduced. `AgentEvent`, `AgentEventReducer`, `VibeBarAgent`, and `SessionFileStore` remain the authoritative event ingestion path.

## Event Contract

The shared runtime emits `AgentEvent` version 1. Pi uses source `pi-extension` and tool `pi`; OMP uses source `oh-my-pi-extension` and tool `oh-my-pi`.

| Runtime event | VibeBar result | Metadata |
| --- | --- | --- |
| `session_start` | `idle` | session ID, cwd, title, transcript path, PID, terminal environment |
| `input` | `running` | last user message and current task |
| `agent_start` | `running` | title and model |
| `message_update` | keep `running` | throttled running summary |
| `tool_execution_start/update` | `running` | tool name and compact argument summary |
| Pi `agent_settled` | `idle` | final assistant summary |
| OMP `session_stop` | `idle` | final assistant summary |
| `session_shutdown` | delete session | shutdown reason |

`message_update` is coalesced with a trailing delay of approximately 500 ms and capped in length. Socket failures are swallowed after local cleanup so VibeBar cannot break the host agent.

The runtime reads session metadata defensively because Pi and OMP expose slightly different APIs. It prefers the runtime session ID, explicit session name/title, current cwd, and persisted session file path. Terminal environment keys use the same pass-through set as the Claude and OpenCode integrations.

## Extension Packaging

Add `plugins/pi-vibebar-extension/` with:

- a dependency-free shared JavaScript runtime;
- a Pi `index.ts` entry adapter;
- an OMP `index.ts` entry adapter;
- Node tests for event mapping, throttling, and transport failures;
- package metadata carrying the bundled extension version.

The installer copies only the selected adapter plus shared runtime into each managed destination. A VibeBar marker and version file distinguish managed installations from user files.

## Installation Semantics

`PiFamilyExtensionInstaller` owns path discovery, detection, install, update, and uninstall.

- Install writes a temporary sibling directory and atomically replaces the managed directory.
- Detection reports CLI missing, not installed, installed, partially installed, or update available through the existing plugin UI status model.
- OMP is fully installed only when the default target and all currently discovered profile targets contain the bundled managed version.
- Uninstall removes only directories carrying the VibeBar marker.
- User-created files and unrelated extensions are never deleted.
- Re-running install repairs partial installations and adds newly discovered OMP profiles.

## VibeBar Integration

`ToolKind` receives `.pi` and `.ohMyPi` cases with independent display names, executable names, icons, CLI aliases, and process detection.

Both tools expose `.plugin` and `.processScan` detection methods. Existing users receive configurations for the new tools through a configuration migration rather than only through fresh defaults.

`PluginStatusReport` and `PluginDetector` include Pi and OMP and delegate filesystem work to `PiFamilyExtensionInstaller`. Existing settings rows are reused.

The monitor treats plugin events as authoritative. Process scans may fill PID, cwd, start time, and terminal context, but may not overwrite plugin state or richer metadata. Pi-family sessions correlate by stable runtime session ID when available and by PID as fallback.

## Failure Handling

- Missing extension or unavailable VibeBar Agent leaves process-scan fallback operational.
- Unknown extension event fields are ignored.
- Failed extension sends never throw into Pi or OMP.
- Failed or partial installs surface a plugin error without modifying unrelated extension directories.
- Stale idle sessions continue to use the existing stale-session cleanup policy.
- If an extension session and process session cannot be correlated safely, VibeBar preserves both rather than merging unrelated sessions.

## Testing

Automated coverage includes:

- tool aliases and direct/runtime-based process detection;
- default configuration and migration for existing settings;
- extension event mapping, metadata extraction, throttling, shutdown cleanup, and socket failure handling;
- Pi install/update/uninstall;
- OMP default and existing-profile synchronization;
- managed-marker safety and partial installation repair;
- event source decoding and reducer behavior;
- plugin/process merge precedence and session deduplication;
- package version validation and full Swift build/test regression.

Manual acceptance runs one Pi session, one default OMP session, and one named-profile OMP session. Each must transition from idle to running and back, show title/user message/summary/cwd, and retain terminal navigation context.

## Out of Scope

- Pi or OMP token/cost usage loaders.
- Permission, question, or plan-review replies from VibeBar.
- Parsing session JSONL as a primary detector.
- Automatically monitoring for OMP profiles created after installation.
