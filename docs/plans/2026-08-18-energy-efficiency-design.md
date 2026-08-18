# VibeBar Energy Efficiency Design

## Context

VibeBar has already completed two power-related improvements:

- `docs/plans/2026-03-06-power-optimization.md` moved refresh work off the main actor, introduced adaptive intervals, shared one process snapshot per refresh, and added short runtime caches.
- `docs/plans/2026-04-29-process-scan-wake-cpu.md` coalesced process snapshots, bounded child-process execution, and delayed refresh after wake.

The remaining energy cost comes from periodic work that is still both frequent and broad:

- `FullscreenDetector` performs Accessibility queries every 0.5 seconds.
- Active or awaiting-input sessions run the complete refresh path every 2 seconds.
- Every complete refresh still builds a process context using `/bin/ps`.
- Transcript detectors repeatedly enumerate directories and parse unchanged JSONL content.
- Terminal tab enrichment caches results only for one refresh.
- Usage auto-refresh always requests a full refresh.

## Goals

- Reduce idle timer wakeups by at least 80% with notch display enabled.
- Stop automatic Usage refreshes from forcing full history refreshes.
- Run full process discovery no more than once every 30 seconds during steady active use.
- Avoid parsing unchanged transcript and rollout files.
- Preserve near-real-time updates for plugin and interaction events.
- Preserve a low-frequency reconciliation scan so missed filesystem events cannot leave state permanently stale.

## Non-Goals

- Do not replace every process query with `libproc` in the first release.
- Do not change session merge precedence or user-visible status semantics.
- Do not remove process-scan fallback.
- Do not introduce a database for session state.
- Do not optimize one-time settings or menu construction unless profiling identifies it as a remaining hotspot.

## Delivery Strategy

Use three gated phases. Each phase must be measured before the next begins.

### Phase 1: Stop Unnecessary Periodic Work

- Remove the 0.5-second fullscreen timer. Use active-space and active-application notifications, with one delayed verification after transitions.
- Do not instantiate fullscreen detection when notch display is disabled.
- Make Usage timer refresh incremental; reserve full refresh for explicit user actions, cache reset, parser changes, and configured full-refresh expiry.
- Read and prune interaction files in one directory pass.
- Add timer tolerance to remaining polling timers.

This phase is deliberately small and must not alter detector selection or merge behavior.

### Phase 2: Make Polling Cheap

- Introduce an explicit refresh reason: event, periodic reconciliation, manual, and wake.
- Reuse process snapshots for 30 seconds during event and timer refreshes. Manual and wake reconciliation may request a fresh snapshot.
- Persist terminal snapshot caches across refreshes with bounded TTLs.
- Cache transcript summaries by file identity, size, and modification time.
- Publish model values only when their semantic content changes.

The existing timer remains as a fallback, but most timer ticks should perform no child-process launch and no transcript parse.

### Phase 3: Event-Driven Refresh

- Watch VibeBar session and interaction directories with `DispatchSourceFileSystemObject`.
- Watch recursive Claude, Codex, and Gemini data roots with FSEvents.
- Coalesce events through one debounce coordinator.
- Parse appended JSONL bytes from the previous offset.
- Observe known process exits with `DispatchSourceProcess`.
- Retain a 60-120 second reconciliation timer for new CLI process discovery and missed-event recovery.

## Data Flow

```text
Agent socket / session file / interaction file / transcript event
                              |
                              v
                    RefreshTriggerCoordinator
                       250 ms debounce
                              |
                              v
                   Targeted refresh request
                    |        |         |
                    v        v         v
               file store  transcript terminal cache
                    \        |        /
                     Session merge
                          |
                  semantic equality check
                          |
                     UI publication

Periodic reconciliation (60-120 s)
                          |
          process discovery + cache reconciliation
```

## Error Handling

- Filesystem watchers are optimization signals, not the source of truth. Watcher errors schedule a reconciliation and restart the watcher with backoff.
- File replacement, truncation, inode change, or parser-version change invalidates the incremental parser entry and triggers one full parse of that file.
- A timed-out process or terminal command returns the last unexpired cache value when available; otherwise existing empty-result behavior remains.
- Event bursts are coalesced. A refresh requested while another refresh is running sets one pending refresh rather than creating an unbounded queue.
- Resume from sleep invalidates time-sensitive caches and schedules one delayed reconciliation.

## Testing Strategy

- Unit-test refresh-reason policy, Usage full/incremental selection, interaction pruning, transcript cache invalidation, JSONL append parsing, and event debounce behavior.
- Keep existing detector fixture tests as semantic regression coverage.
- Add command-spy tests proving repeated unchanged refreshes do not launch another process or terminal command.
- Run `swift test` after every task and `swift build -c release` at each phase gate.
- Measure no-session, running, awaiting-input, and Usage-enabled scenarios with the same duration and dataset before and after each phase.

## Acceptance Gates

### Phase 1 Gate

- No recurring 0.5-second fullscreen timer exists.
- Fullscreen transitions remain correct in menu-bar and notch modes.
- Usage automatic refresh reports incremental mode after the initial load.
- Idle timer callbacks drop by at least 80% from baseline.

### Phase 2 Gate

- During a 10-minute active session, full `/bin/ps -axo` launches are at most 21: one initial scan plus one every 30 seconds.
- An unchanged Claude or Codex transcript is parsed once, not once per UI refresh.
- Terminal snapshot commands are bounded by their TTL and do not execute every two seconds.
- Session status and navigation behavior match the pre-change fixture tests.

### Phase 3 Gate

- Plugin/session updates appear within one second under normal load.
- Transcript append updates appear within two seconds.
- No-session reconciliation launches at most one full process scan per 120 seconds.
- Killing a known session process removes or updates it without waiting for the full reconciliation interval.
- A simulated dropped watcher event is repaired by the next reconciliation.
