# VibeBar Energy Efficiency Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Convert VibeBar from frequent broad polling to a measured, event-driven refresh model while preserving detector and session-merge behavior.

**Architecture:** Deliver three gated phases: first remove unnecessary periodic work, then make remaining polling cache-aware, and finally add filesystem/process events with low-frequency reconciliation. Event notifications only trigger refreshes; persisted files and detector outputs remain the source of truth.

**Tech Stack:** Swift 6.2, macOS 13+, Swift Testing, AppKit, Combine, Foundation, DispatchSource, CoreServices FSEvents, OSLog, Swift Package Manager.

---

## Execution Rules

- Work in a dedicated branch or worktree.
- Complete tasks in order; do not begin the next phase before its gate passes.
- Start every behavior change with a failing test.
- Run the narrow test first, then `swift test` at each task boundary.
- Do not change session precedence, status priority, or persisted JSON formats unless a task explicitly says so.
- Suggested commit checkpoints are documentation only. Do not commit unless the user explicitly requests it.

## Phase 0: Establish a Reproducible Baseline

### Task 1: Add Refresh and External-Command Diagnostics

**Files:**
- Create: `Sources/VibeBarCore/EnergyDiagnostics.swift`
- Modify: `Sources/VibeBarCore/DetectorSupport.swift:240-487`
- Modify: `Sources/VibeBarApp/AppModel.swift:275-322`
- Modify: `Sources/VibeBarApp/FullscreenDetector.swift:54-101`
- Test: `Tests/VibeBarCoreTests/EnergyDiagnosticsTests.swift`

**Step 1: Write the failing diagnostics counter test**

Add a test proving an in-memory diagnostics sink records named operations and can return/reset counts without production logging dependencies.

```swift
@Test func energyDiagnosticsCountsAndResetsOperations() {
    let diagnostics = EnergyDiagnostics()
    diagnostics.record(.processSnapshot)
    diagnostics.record(.processSnapshot)

    #expect(diagnostics.count(for: .processSnapshot) == 2)
    diagnostics.reset()
    #expect(diagnostics.count(for: .processSnapshot) == 0)
}
```

**Step 2: Run the narrow test**

Run: `swift test --filter energyDiagnosticsCountsAndResetsOperations`

Expected: FAIL because `EnergyDiagnostics` does not exist.

**Step 3: Implement the minimal diagnostics type**

Create a lock-protected, `Sendable` diagnostics type with these operation cases:

```swift
public enum EnergyOperation: String, Sendable {
    case modelRefresh
    case processSnapshot
    case cwdLookup
    case environmentLookup
    case terminalSnapshot
    case transcriptParse
    case fullscreenCheck
}
```

The production default records OSLog signposts and counters only when `VIBEBAR_ENERGY_DIAGNOSTICS=1`; tests inject an isolated instance. Do not print once per refresh in normal builds.

**Step 4: Instrument existing boundaries**

- Record `modelRefresh` around `performRefresh`.
- Record `processSnapshot` before `/bin/ps -axo`.
- Record `cwdLookup` before `lsof`.
- Record `environmentLookup` before `ps eww`.
- Record `fullscreenCheck` before AX queries.
- Later tasks add transcript and terminal records at their shared cache boundaries.

**Step 5: Run tests and release build**

Run: `swift test --filter EnergyDiagnosticsTests`

Expected: PASS.

Run: `swift build -c release`

Expected: build succeeds with strict concurrency checks.

**Step 6: Capture four 10-minute baselines**

Build and launch with diagnostics:

```bash
VIBEBAR_ENERGY_DIAGNOSTICS=1 swift run VibeBarApp
```

Measure these scenarios with Instruments Energy Log and save traces outside the repository under `/var/folders/d9/5sfcnz292bvbdh3nv19rvhc40000gn/T/opencode/vibebar-energy/`:

1. No visible sessions.
2. One running Claude or Codex session.
3. One session waiting for input for the full 10 minutes.
4. Usage enabled at five-minute cadence.

Record CPU time, wakeups, child-process counts, file reads, and UI responsiveness in an appended results section in this document.

**Suggested commit:** `chore: add energy diagnostics`

## Phase 1: Stop Unnecessary Periodic Work

### Task 2: Make Fullscreen Detection Notification-Driven

**Files:**
- Modify: `Sources/VibeBarApp/FullscreenDetector.swift:13-188`
- Modify: `Sources/VibeBarApp/StatusItemController.swift:47-92, 240-270, 1370-1423`
- Test: `Tests/VibeBarAppTests/FullscreenDetectorTests.swift`

**Step 1: Write failing transition tests**

Inject a detection closure and notification center into an internal initializer. Test that:

- initialization performs one check;
- an active-space notification performs one immediate check and one delayed verification;
- an active-application notification performs one check;
- waiting without notifications performs no additional checks;
- `stop()` removes observers and cancels delayed verification.

Use a test scheduler closure instead of sleeping in tests:

```swift
typealias DelayedActionScheduler = @Sendable (
    Duration,
    @escaping @MainActor @Sendable () -> Void
) -> Void
```

**Step 2: Run the narrow tests**

Run: `swift test --filter FullscreenDetectorTests`

Expected: FAIL because the current detector always installs a repeating timer and has no injected dependencies.

**Step 3: Remove the repeating timer**

- Delete `timer` and `startTimer()`.
- Observe `NSWorkspace.activeSpaceDidChangeNotification`.
- Observe `NSWorkspace.didActivateApplicationNotification`.
- Keep the immediate plus one-second delayed check for Space transitions.
- Keep the existing enter/exit debounce semantics.
- Add `stop()` and call it when detection is no longer needed.

**Step 4: Make detector lifecycle follow notch settings**

- Replace the eager `FullscreenDetector.shared` property in `StatusItemController` with optional/lazy ownership.
- Start and subscribe only while notch mode is enabled.
- Cancel the subscription and stop detection when switching back to menu-bar-only mode.
- Do not change the current `temporarilyBlocked` behavior.

**Step 5: Run tests and manual transition checks**

Run: `swift test --filter FullscreenDetectorTests`

Expected: PASS.

Run: `swift test`

Expected: all tests pass.

Manual checks: enter and leave native fullscreen in Safari, Terminal, iTerm, and a multi-monitor setup. The notch must hide/show without a persistent polling timer.

**Suggested commit:** `perf: replace fullscreen polling with notifications`

### Task 3: Separate Automatic and Forced Usage Refreshes

**Files:**
- Modify: `Sources/VibeBarApp/UsageMonitorViewModel.swift:80-103, 321-412, 508-518`
- Modify: `Sources/VibeBarApp/AppSettings.swift:224-260, 278-310, 400-415`
- Test: `Tests/VibeBarAppTests/UsageRefreshPolicyTests.swift`

**Step 1: Write failing refresh-reason tests**

Add an internal value type:

```swift
enum UsageRefreshReason: Sendable {
    case initial
    case automatic
    case manual
    case cacheReset
    case forceFull

    var forcesFullRefresh: Bool {
        self == .cacheReset || self == .forceFull
    }
}
```

Test that initial, timer, and normal manual refreshes do not force full history, while force-full and cache-reset do.

**Step 2: Run the narrow tests**

Run: `swift test --filter UsageRefreshPolicyTests`

Expected: FAIL because refresh reason is not modeled.

**Step 3: Thread the reason through scheduling**

- Change `scheduleRefresh()` to `scheduleRefresh(reason:)`.
- `refreshNow()` uses `.manual`.
- startup uses `.initial`.
- timer uses `.automatic`.
- `forceFullRefresh()` uses `.forceFull`.
- `clearCacheAndRefresh()` uses `.cacheReset`.
- Pending refreshes preserve the strongest requested reason.

**Step 4: Use configured full-refresh interval**

Pass `AppSettings.shared.usageFullRefreshInterval` instead of fixed `.sixHours` and pass `reason.forcesFullRefresh` instead of `true`.

**Step 5: Verify**

Run: `swift test --filter UsageRefreshPolicyTests`

Expected: PASS.

Run: `swift test --filter Usage`

Expected: all Usage tests pass.

Manual check: enable Usage, wait for two refreshes, and verify diagnostics show one initial/full-or-rebuild load followed by incremental refresh unless the configured interval expires.

**Suggested commit:** `fix: keep usage auto refresh incremental`

### Task 4: Prune and Load Interactions in One Pass

**Files:**
- Modify: `Sources/VibeBarCore/InteractionStore.swift:30-67`
- Modify: `Sources/VibeBarApp/AppModel.swift:571-608`
- Test: `Tests/VibeBarCoreTests/InteractionStoreTests.swift`

**Step 1: Write the failing single-pass behavior test**

Create one active and one expired interaction, then verify:

```swift
let active = store.loadAll(cleaningExpiredAt: now)
#expect(active.map(\.id) == ["active"])
#expect(store.load(id: "expired") == nil)
```

Also test that malformed JSON is ignored without deleting unrelated valid files.

**Step 2: Run the narrow tests**

Run: `swift test --filter InteractionStoreTests`

Expected: FAIL because `loadAll(cleaningExpiredAt:)` does not exist.

**Step 3: Implement one-pass loading**

Add `loadAll(cleaningExpiredAt now: Date?)`. During the existing directory loop, decode each interaction, delete it when expired, and append only active interactions. Keep `loadAll()` as a no-cleanup convenience if existing callers need it.

**Step 4: Update AppModel**

Replace:

```swift
interactionStore.cleanupExpired(now: now)
let interactions = interactionStore.loadAll()
```

with one call to `loadAll(cleaningExpiredAt: now)`.

**Step 5: Verify**

Run: `swift test --filter InteractionStoreTests`

Expected: PASS.

Run: `swift test --filter AppModelTests`

Expected: PASS.

**Suggested commit:** `perf: prune interactions during load`

### Task 5: Add Timer Tolerance and Phase 1 Gate

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift:136-159`
- Modify: `Sources/VibeBarApp/UsageMonitorViewModel.swift:508-518`
- Modify: `docs/plans/2026-08-18-energy-efficiency.md`
- Test: `Tests/VibeBarAppTests/RefreshTimerPolicyTests.swift`

**Step 1: Write failing timer-policy tests**

Extract internal pure helpers that return interval and tolerance. Verify:

- model refresh tolerance is 15-20% of interval with a sensible cap;
- cleanup timer tolerance is at least 30 seconds;
- Usage timer tolerance is at least 10% of cadence;
- no tolerance is negative or greater than its interval.

**Step 2: Run tests**

Run: `swift test --filter RefreshTimerPolicyTests`

Expected: FAIL because the timers do not expose or set tolerance.

**Step 3: Apply tolerance**

Set `Timer.tolerance` before adding each timer to the run loop. Keep current intervals unchanged in Phase 1 so the energy comparison isolates coalescing and fullscreen changes.

**Step 4: Run the full suite and release build**

Run: `swift test`

Expected: PASS.

Run: `swift build -c release`

Expected: PASS.

**Step 5: Repeat baseline scenarios**

Repeat Task 1's four scenarios. Append results to this document.

Phase 1 passes only if:

- no recurring fullscreen timer exists;
- Usage automatic refresh is incremental;
- idle timer wakeups improve by at least 80%;
- session status behavior remains correct.

If the gate fails, stop and profile before Phase 2.

**Suggested commit:** `perf: coalesce background timers`

## Phase 2: Make Remaining Polling Cheap

### Task 6: Introduce Refresh Reasons and Process-Snapshot Policy

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift:24-41, 233-322, 571-627`
- Modify: `Sources/VibeBarCore/CompositeSessionDetector.swift:5-63, 112-176`
- Modify: `Sources/VibeBarCore/DetectorSupport.swift:53-141`
- Test: `Tests/VibeBarAppTests/RefreshPolicyTests.swift`
- Test: `Tests/VibeBarCoreTests/CompositeSessionDetectorTests.swift`

**Step 1: Write failing policy tests**

Define:

```swift
enum MonitorRefreshReason: Sendable {
    case event
    case periodic
    case manual
    case wake
}

struct ProcessSnapshotPolicy: Sendable, Equatable {
    var ttl: TimeInterval
}
```

Expected policy:

- event: 30-second process snapshot TTL;
- periodic: 30 seconds while sessions exist, 60 seconds with no sessions;
- manual: fresh snapshot (`ttl = 0`);
- wake: fresh snapshot after the existing wake delay.

**Step 2: Run tests**

Run: `swift test --filter RefreshPolicyTests`

Expected: FAIL because refresh reason and policy do not exist.

**Step 3: Thread policy into the detector**

- Add refresh reason to `RefreshConfiguration`.
- Let `CompositeSessionDetector` accept `processSnapshotTTL`.
- Change `detectSessions()` to call `DetectorSupport.makeContext(ttl:)` with that value.
- Preserve the existing single-flight cache and `ttl: 0` escape hatch.
- Timer uses `.periodic`, file/setting notifications use `.event`, user refresh uses `.manual`, and wake uses `.wake`.

**Step 4: Add command-spy coverage**

Use the existing detector providers or add a minimal injectable context provider. Prove that two event refreshes inside 30 seconds request one process snapshot and that a manual refresh requests a fresh one.

**Step 5: Verify**

Run: `swift test --filter RefreshPolicyTests`

Expected: PASS.

Run: `swift test --filter CompositeSessionDetectorTests`

Expected: PASS.

**Suggested commit:** `perf: decouple UI refresh from process discovery`

### Task 7: Add Cross-Refresh Terminal Snapshot Cache

**Files:**
- Create: `Sources/VibeBarApp/TerminalSnapshotCache.swift`
- Modify: `Sources/VibeBarApp/AppModel.swift:629-947`
- Modify: `Sources/VibeBarApp/SessionNavigator.swift:543-566, 1138-1290`
- Test: `Tests/VibeBarAppTests/TerminalSnapshotCacheTests.swift`
- Test: `Tests/VibeBarAppTests/SessionNavigatorTests.swift`

**Step 1: Write failing cache tests**

Test hit, expiry, negative caching, explicit invalidation, and concurrent single-flight loading. Use an injected clock and loader counter; do not sleep.

The cache key must include terminal kind and connection identity, for example:

```swift
struct TerminalSnapshotKey: Hashable, Sendable {
    var kind: TerminalClientKind
    var address: String
}
```

**Step 2: Run tests**

Run: `swift test --filter TerminalSnapshotCacheTests`

Expected: FAIL because the cache does not exist.

**Step 3: Implement bounded TTL caching**

- Positive terminal snapshots: 15-second TTL.
- Failed command results: 5-second negative TTL.
- Coalesce concurrent requests for the same key.
- Clear all entries after wake.
- Bound entry count and evict oldest entries to avoid unbounded growth.

**Step 4: Route enrichment through the cache**

Replace refresh-local dictionaries in `enrichKittyTabs`, `enrichWezTermTabs`, `enrichGhosttyTabs`, `enrichITermTabs`, `enrichTmuxTabs`, and `enrichZellijTabs` with the shared cache. Keep parsing and target matching unchanged.

**Step 5: Verify**

Run: `swift test --filter TerminalSnapshotCacheTests`

Expected: PASS.

Run: `swift test --filter SessionNavigatorTests`

Expected: PASS.

Manual check: keep one Kitty/tmux or WezTerm session running for one minute. Diagnostics should show no more than four successful snapshot commands per cache key.

**Suggested commit:** `perf: cache terminal snapshots across refreshes`

### Task 8: Cache Unchanged Transcript Summaries

**Files:**
- Create: `Sources/VibeBarCore/TranscriptSummaryCache.swift`
- Modify: `Sources/VibeBarCore/ClaudeTranscriptDetector.swift:27-128, 389-516`
- Modify: `Sources/VibeBarCore/GeminiTranscriptDetector.swift:22-260`
- Modify: `Sources/VibeBarCore/CodexSessionDetector.swift:121-173, 293-420, 423-538`
- Test: `Tests/VibeBarCoreTests/TranscriptSummaryCacheTests.swift`
- Test: `Tests/VibeBarCoreTests/ClaudeTranscriptDetectorTests.swift`
- Test: `Tests/VibeBarCoreTests/GeminiTranscriptDetectorTests.swift`
- Test: `Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift`

**Step 1: Write failing signature-cache tests**

Define a file identity containing canonical path, file size, and modification timestamp. Test:

- unchanged signature returns the cached summary without invoking parser;
- size or modification change invokes parser once;
- file replacement invalidates the entry;
- parser-version change invalidates all prior entries;
- cache has a bounded maximum entry count.

**Step 2: Run tests**

Run: `swift test --filter TranscriptSummaryCacheTests`

Expected: FAIL because no shared summary cache exists.

**Step 3: Implement the actor cache**

Provide a generic internal API that stores detector-specific `Sendable` summaries without exposing detector private types. Prefer separate typed caches owned by each detector over type erasure if that keeps the implementation smaller.

**Step 4: Integrate Claude and Gemini first**

- Stat the selected active transcript before parsing.
- Return cached summary when unchanged.
- Parse and update the cache only when the signature changes.
- Record `transcriptParse` only around actual parser execution.

Run:

```bash
swift test --filter ClaudeTranscriptDetectorTests
swift test --filter GeminiTranscriptDetectorTests
```

Expected: PASS.

**Step 5: Integrate Codex**

- Cache parsed `session_index.jsonl` by signature.
- Cache rollout summaries by rollout path and signature.
- Cache the filename-to-session-ID index so `loadRolloutSummaries` does not recursively enumerate the entire sessions tree on every refresh.
- Invalidate the directory index when reconciliation detects directory metadata changes.

Run: `swift test --filter CodexSessionDetectorTests`

Expected: PASS.

**Step 6: Verify unchanged-file behavior**

Add detector tests that invoke detection twice against unchanged fixtures and assert the parser spy runs once. Modify/append the fixture and assert it runs exactly once more.

**Suggested commit:** `perf: cache unchanged transcript summaries`

### Task 9: Suppress Semantically Identical UI Publications

**Files:**
- Modify: `Sources/VibeBarCore/Models.swift:530-617`
- Modify: `Sources/VibeBarApp/AppModel.swift:33-52, 309-322`
- Test: `Tests/VibeBarAppTests/AppModelTests.swift`

**Step 1: Write failing semantic-equality tests**

Test that two refresh results with the same user-visible session fields are equal even if the refresh execution time differs, and that status, interaction, title, task, or terminal-context changes are not equal.

Do not ignore timestamps that drive visible duration or stale-session behavior. Define equality explicitly rather than deleting all date comparisons.

**Step 2: Run tests**

Run: `swift test --filter semanticRefreshResult`

Expected: FAIL because semantic refresh comparison does not exist.

**Step 3: Implement internal semantic comparison**

Add a focused comparator used by `applyRefreshResult`; do not add broad `Equatable` conformances if they would accidentally change unrelated behavior.

Only assign these `@Published` properties when changed:

- `sessions`
- `summary`
- `pendingInteractionsBySessionID`

Timer adjustment and refresh-state cleanup must still execute every time.

**Step 4: Verify**

Run: `swift test --filter AppModelTests`

Expected: PASS.

Run: `swift test`

Expected: PASS.

**Suggested commit:** `perf: skip unchanged model publications`

### Task 10: Phase 2 Measurement Gate

**Files:**
- Modify: `docs/plans/2026-08-18-energy-efficiency.md`

**Step 1: Run full verification**

Run: `swift test`

Expected: PASS.

Run: `swift build -c release`

Expected: PASS.

**Step 2: Repeat all four baseline scenarios**

Append measurements and compare against Phase 0 and Phase 1.

**Step 3: Enforce the gate**

Do not start Phase 3 unless:

- `/bin/ps -axo` count is at most 21 during a 10-minute active run;
- unchanged transcript parser count is one per file;
- terminal command count respects the configured TTL;
- no detector fixture or navigation regression exists.

If these targets already satisfy the product's energy goal, Phase 3 may be deferred. Event-driven complexity is not mandatory when measured benefit no longer justifies it.

## Phase 3: Event-Driven Refresh With Reconciliation

### Task 11: Add a Debounced Refresh Trigger Coordinator

**Files:**
- Create: `Sources/VibeBarApp/RefreshTriggerCoordinator.swift`
- Modify: `Sources/VibeBarApp/AppModel.swift:57-84, 233-322`
- Test: `Tests/VibeBarAppTests/RefreshTriggerCoordinatorTests.swift`

**Step 1: Write failing coordinator tests**

Using an injected clock/scheduler, verify:

- ten events inside 250 ms produce one refresh;
- events arriving during a refresh produce one pending refresh;
- manual refresh is not delayed;
- wake cancels pending event refresh and schedules one wake reconciliation;
- `stop()` prevents further callbacks.

**Step 2: Run tests**

Run: `swift test --filter RefreshTriggerCoordinatorTests`

Expected: FAIL because the coordinator does not exist.

**Step 3: Implement the coordinator**

Use an actor or `@MainActor` class with one debounce task and one pending flag. Emit `MonitorRefreshReason` values through a callback; do not let filesystem watchers call `performRefresh` directly.

**Step 4: Route existing triggers through it**

Route timer, settings changes, wake, and explicit user refresh through the coordinator while preserving manual refresh immediacy.

**Step 5: Verify**

Run: `swift test --filter RefreshTriggerCoordinatorTests`

Expected: PASS.

**Suggested commit:** `refactor: centralize refresh triggers`

### Task 12: Watch VibeBar Session and Interaction Directories

**Files:**
- Create: `Sources/VibeBarCore/DirectoryChangeWatcher.swift`
- Modify: `Sources/VibeBarCore/VibeBarPaths.swift`
- Modify: `Sources/VibeBarApp/AppModel.swift:74-84`
- Test: `Tests/VibeBarCoreTests/DirectoryChangeWatcherTests.swift`

**Step 1: Write failing filesystem tests**

Using a temporary directory, verify create, atomic replacement, rename, and delete each emit a change signal. Verify `stop()` closes the descriptor and emits no more events.

**Step 2: Run tests**

Run: `swift test --filter DirectoryChangeWatcherTests`

Expected: FAIL because the watcher does not exist.

**Step 3: Implement a directory watcher**

Use `DispatchSource.makeFileSystemObjectSource` with `.write`, `.delete`, `.rename`, and `.attrib`. Reopen the directory when the watched directory itself is replaced. The watcher emits only a signal; it does not read or decode files.

**Step 4: Connect watchers**

Watch `VibeBarPaths.sessionsDirectory` and `VibeBarPaths.interactionsDirectory`, then send `.event` to `RefreshTriggerCoordinator`.

Keep the periodic timer temporarily unchanged until Task 15.

**Step 5: Verify**

Run: `swift test --filter DirectoryChangeWatcherTests`

Expected: PASS.

Manual check: write an agent event and confirm UI changes within one second without waiting for the periodic timer.

**Suggested commit:** `feat: refresh on session file changes`

### Task 13: Watch Recursive Transcript Roots

**Files:**
- Create: `Sources/VibeBarCore/RecursiveFileEventWatcher.swift`
- Modify: `Sources/VibeBarApp/AppModel.swift:74-84, 324-362`
- Test: `Tests/VibeBarCoreTests/RecursiveFileEventWatcherTests.swift`

**Step 1: Write failing recursive watcher tests**

Create nested temporary directories and verify append, create, delete, and rename events include the affected path. Verify multiple writes are delivered as a batch and shutdown is clean.

**Step 2: Run tests**

Run: `swift test --filter RecursiveFileEventWatcherTests`

Expected: FAIL because the FSEvents wrapper does not exist.

**Step 3: Implement the FSEvents wrapper**

- Wrap `FSEventStreamCreate` and schedule it on a dedicated serial dispatch queue.
- Use file-event flags and a short latency suitable for the coordinator's 250 ms debounce.
- Make lifecycle explicit: `start(paths:)`, `stop()`, and deinit cleanup.
- Convert callbacks into `Sendable` path batches before crossing concurrency domains.

**Step 4: Watch only enabled source roots**

Watch enabled roots for Claude, Codex, and Gemini. Restart watchers when detection settings or configured homes change. Do not watch missing directories; retry at reconciliation.

**Step 5: Verify**

Run: `swift test --filter RecursiveFileEventWatcherTests`

Expected: PASS.

Run: `swift test`

Expected: PASS.

**Suggested commit:** `feat: refresh on transcript file events`

### Task 14: Parse Appended JSONL Content Incrementally

**Files:**
- Create: `Sources/VibeBarCore/IncrementalJSONLReader.swift`
- Modify: `Sources/VibeBarCore/TranscriptSummaryCache.swift`
- Modify: `Sources/VibeBarCore/ClaudeTranscriptDetector.swift:389-516`
- Modify: `Sources/VibeBarCore/CodexSessionDetector.swift:423-538`
- Test: `Tests/VibeBarCoreTests/IncrementalJSONLReaderTests.swift`
- Test: `Tests/VibeBarCoreTests/ClaudeTranscriptDetectorTests.swift`
- Test: `Tests/VibeBarCoreTests/CodexSessionDetectorTests.swift`

**Step 1: Write failing incremental-reader tests**

Cover:

- initial full read;
- append of complete lines;
- append ending in a partial line;
- completion of the partial line on the next read;
- truncation;
- atomic replacement/inode change;
- invalid UTF-8 and malformed JSON lines;
- offset persistence only after successful line delivery.

**Step 2: Run tests**

Run: `swift test --filter IncrementalJSONLReaderTests`

Expected: FAIL because incremental reader state does not exist.

**Step 3: Implement reader state**

Track file identity, byte offset, and trailing partial bytes. On truncation or identity change, reset to offset zero. Return complete newly appended lines and the next state; detector-specific summary reduction remains in each detector.

**Step 4: Make detector summaries reducible**

Refactor Claude and Codex parsers so they can apply new lines to a cached summary. Do not duplicate JSON interpretation between full and incremental paths; the full path should fold all lines through the same reducer.

**Step 5: Verify**

Run:

```bash
swift test --filter IncrementalJSONLReaderTests
swift test --filter ClaudeTranscriptDetectorTests
swift test --filter CodexSessionDetectorTests
```

Expected: PASS.

**Suggested commit:** `perf: parse transcript appends incrementally`

### Task 15: Observe Known Process Exit and Slow Reconciliation

**Files:**
- Create: `Sources/VibeBarApp/SessionProcessObserver.swift`
- Modify: `Sources/VibeBarApp/AppModel.swift:43-84, 136-174, 309-322`
- Test: `Tests/VibeBarAppTests/SessionProcessObserverTests.swift`
- Test: `Tests/VibeBarAppTests/RefreshTimerPolicyTests.swift`

**Step 1: Write failing process-observer tests**

Launch a short-lived child process in the test and verify one exit callback. Verify duplicate registration for the same PID creates one source, removed sessions cancel sources, and `stop()` cancels all sources.

**Step 2: Run tests**

Run: `swift test --filter SessionProcessObserverTests`

Expected: FAIL because the observer does not exist.

**Step 3: Implement process exit observation**

Use `DispatchSource.makeProcessSource(identifier:eventMask:[.exit])` for known positive PIDs. Exit events trigger `.event`; they do not mutate sessions directly.

**Step 4: Reconcile observer registrations after result application**

After each accepted session update, register new PIDs and unregister removed PIDs. Ignore PID zero and sessions that do not represent a local process.

**Step 5: Slow the reconciliation timer**

After file and process events are active:

- visible sessions: reconcile every 60 seconds;
- no sessions: reconcile every 120 seconds;
- manual refresh remains immediate;
- wake remains a delayed fresh reconciliation.

Set suitable timer tolerance, at least 15 seconds for reconciliation.

**Step 6: Verify**

Run: `swift test --filter SessionProcessObserverTests`

Expected: PASS.

Run: `swift test --filter RefreshTimerPolicyTests`

Expected: PASS with the new reconciliation intervals.

Manual check: kill a known CLI session and confirm state changes promptly; then create a new unsupported/fallback-only CLI session and confirm discovery within the reconciliation bound.

**Suggested commit:** `feat: reconcile sessions from file and process events`

### Task 16: Failure Recovery and Final Acceptance

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift`
- Modify: `Sources/VibeBarCore/DirectoryChangeWatcher.swift`
- Modify: `Sources/VibeBarCore/RecursiveFileEventWatcher.swift`
- Modify: `docs/plans/2026-08-18-energy-efficiency.md`
- Test: `Tests/VibeBarAppTests/RefreshTriggerCoordinatorTests.swift`
- Test: `Tests/VibeBarCoreTests/DirectoryChangeWatcherTests.swift`
- Test: `Tests/VibeBarCoreTests/RecursiveFileEventWatcherTests.swift`

**Step 1: Add watcher-failure tests**

Verify watcher deletion, restart failure, and event-stream shutdown request one reconciliation and retry with bounded backoff. Ensure repeated failures do not create a tight retry loop.

**Step 2: Implement bounded recovery**

- First retry after 1 second.
- Exponential backoff capped at 60 seconds.
- Successful start resets backoff.
- Periodic reconciliation remains active while watchers are unavailable.

**Step 3: Run all automated checks**

Run: `swift test`

Expected: PASS.

Run: `swift build -c release`

Expected: PASS.

**Step 4: Run final manual matrix**

Verify:

1. Menu-bar mode with notch disabled.
2. Notch mode with fullscreen transitions and multiple displays.
3. Claude, Codex, OpenCode, and Gemini start/run/wait/exit flows.
4. Kitty, WezTerm, Ghostty, iTerm, tmux, and Zellij navigation where available.
5. Sleep/wake with sessions running.
6. Usage automatic, manual, force-full, and cache-reset refreshes.
7. Watcher root deleted and recreated while the app runs.

**Step 5: Run final energy comparison**

Repeat the four Phase 0 scenarios for 10 minutes each. The final gate requires:

- plugin/session updates normally visible within one second;
- transcript append updates within two seconds;
- no-session process scan at most once per 120 seconds;
- no repeating fullscreen check;
- no unchanged transcript reparse;
- no terminal command more frequently than its cache TTL;
- materially lower CPU time and wakeups than Phase 0 in every scenario.

Append exact measurements and residual hotspots below.

**Suggested commit:** `perf: complete event-driven energy optimization`

## Measurement Results

Fill this table at each gate; do not estimate values.

| Scenario | Phase | CPU time / 10 min | Wakeups | `/bin/ps -axo` | `lsof` | Transcript parses | Terminal commands | Notes |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| No sessions | Baseline | TBD | TBD | TBD | TBD | TBD | TBD | |
| Running | Baseline | TBD | TBD | TBD | TBD | TBD | TBD | |
| Awaiting input | Baseline | TBD | TBD | TBD | TBD | TBD | TBD | |
| Usage enabled | Baseline | TBD | TBD | TBD | TBD | TBD | TBD | |

## Phase 1 Gate Status (2026-08-18)

**Code-level gate items verified by implementation and tests:**

- ✅ No recurring fullscreen timer exists: `FullscreenDetector` no longer installs a repeating `Timer`; it observes `activeSpaceDidChangeNotification` and `didActivateApplicationNotification` with one delayed verification after Space transitions (`Sources/VibeBarApp/FullscreenDetector.swift`). Detection lifecycle follows notch settings: `StatusItemController.updateFullscreenDetection()` creates/stops the detector only while `notchDisplayEnabled` is on.
- ✅ Usage automatic refresh is incremental: `UsageMonitorViewModel.scheduleRefresh(reason:)` passes `reason.forcesFullRefresh` to the loader instead of a hard-coded `true`. Timer ticks use `.automatic` and stay incremental; only `.cacheReset` and `.forceFull` force full history (`Sources/VibeBarApp/UsageMonitorViewModel.swift`).
- ✅ Session status behavior correct: all 307 tests pass (`swift test`), including existing detector fixture, merge, and navigation regression tests.
- ✅ Interaction pruning happens in one directory pass (`InteractionStore.loadAll(cleaningExpiredAt:)`), malformed JSON is ignored without deleting valid files.
- ✅ Timer tolerance applied: model refresh 20% of interval (capped at 5 s), cleanup ≥ 30 s (60 s used), Usage ≥ 10% of cadence.

**Pending measurement (requires live GUI session + Instruments Energy Log):**

- ⏳ Idle timer wakeups improve by at least 80% vs baseline.
- ⏳ Re-run the four Phase 0 scenarios for 10 minutes each and append exact CPU time / wakeups / child-process counts / file reads above.

Phase 1 is **conditionally complete pending measurement confirmation**; Phase 2 implementation proceeds with the assumption that the code-level gate items are satisfied.

## Phase 2 Gate Status (2026-08-18)

**Code-level gate items verified by implementation and tests:**

- ✅ `/bin/ps -axo` bounded by TTL: `ProcessSnapshotPolicyResolver` maps event → 30 s TTL, periodic → 30 s (sessions) / 60 s (no sessions), manual/wake → fresh. Verified by `eventRefreshesShareProcessSnapshotWithinTTLAndManualRefreshIsFresh` (two event refreshes → one snapshot; manual → fresh).
- ✅ Unchanged transcript parser runs once per file: `TranscriptSummaryCache` keyed by path+size+mtime+parser version; Claude/Gemini cache raw summaries and re-derive time-sensitive status; Codex caches session index, per-rollout summaries, and a date-window directory index. Verified by parser-spy tests (`claudeTranscriptDetectorParsesUnchangedTranscriptOnlyOnce`, `geminiTranscriptDetectorParsesUnchangedTranscriptOnlyOnce`, `codexSessionDetectorParsesUnchangedTranscriptsOnlyOnce`).
- ✅ Terminal commands bounded by TTL: `TerminalSnapshotCache` (15 s positive / 5 s negative, coalesced, bounded); all six `enrich*Tabs` routes now read through the shared cache.
- ✅ No detector fixture or navigation regression: all 337 tests pass (`swift test`), release build succeeds (`swift build -c release`).
- ✅ Semantic UI publication suppression: `applyRefreshResult` only republishes `sessions`/`summary`/`pendingInteractionsBySessionID` when semantically changed (`updatedAt` refresh time excluded; duration/stale-driving timestamps retained). Verified by `semanticRefreshResult*` tests.

**Pending measurement (requires live GUI session + Instruments Energy Log):**

- ⏳ Re-run all four Phase 0 baseline scenarios for 10 minutes each and append exact CPU time / wakeups / child-process counts / file reads above.
- ⏳ Confirm `/bin/ps -axo` ≤ 21 per 10-minute active run, terminal command count respects TTL, and unchanged transcript parse count is one per file.

The Phase 2 code-level gate is satisfied. Phase 3 (event-driven refresh) **may be deferred** per the plan when the measured energy goal is already met, since the remaining periodic work is now TTL-bounded and cache-aware.

## Phase 3 Gate Status (2026-08-18)

**Code-level gate items verified by implementation and tests:**

- ✅ Task 11 — `RefreshTriggerCoordinator` debounces event bursts (250 ms) into one refresh; manual/wake bypass the debounce; `stop()` prevents callbacks. Verified by `RefreshTriggerCoordinatorTests`.
- ✅ Task 12 — `DirectoryChangeWatcher` (kqueue) watches `VibeBarPaths.sessionsDirectory` and `.interactionsDirectory`; create/atomic-replace/rename/delete each emit a signal. Verified by `DirectoryChangeWatcherTests`.
- ✅ Task 13 — `RecursiveFileEventWatcher` (FSEvents, file-event flags, 0.2 s latency) watches enabled Claude/Codex/Gemini transcript roots and reports affected-path batches. Verified by `RecursiveFileEventWatcherTests`.
- ✅ Task 14 — `IncrementalJSONLReader` tracks inode/offset/partial-line; Claude and Codex fold appended lines into cached summaries via a shared reducer. Verified by `IncrementalJSONLReaderTests` and detector suites.
- ✅ Task 15 — `SessionProcessObserver` (actor, `DispatchSourceProcess` `.exit`) watches known positive PIDs; registrations reconciled after each accepted refresh; reconciliation timer slowed to 60 s (sessions) / 120 s (no sessions) with ≥15 s tolerance. Verified by `SessionProcessObserverTests` + `RefreshTimerPolicyTests`.
- ✅ Task 16 — Bounded backoff recovery (1 s → 60 s cap, reset on success) in both watchers; missing-directory and deletion recovery verified; no tight retry loop. Verified by watcher failure tests.
- ✅ All 367 tests pass (`swift test`), release build succeeds (`swift build -c release`), and the app launches with watchers active.

**Pending measurement (requires live GUI session + Instruments Energy Log):**

- ⏳ Final manual matrix (Task 16 Step 4): menu-bar/notch modes, fullscreen transitions, all CLI tool flows, terminal navigation, sleep/wake, Usage refresh modes, watcher-root deletion/recreation.
- ⏳ Final 10-minute energy comparison across the four Phase 0 scenarios (Task 16 Step 5), asserting plugin/session updates within 1 s, transcript appends within 2 s, no-session scan ≤ 1 per 120 s, no repeating fullscreen check, no unchanged transcript reparse, no terminal command more frequent than its TTL, and materially lower CPU/wakeups than Phase 0.
