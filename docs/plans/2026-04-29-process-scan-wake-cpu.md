# Process Scan Wake CPU Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce high CPU and duplicate `ps` processes after wake by coalescing process snapshots, bounding external command lifetime, and debouncing wake refreshes.

**Architecture:** Keep existing detection and merge semantics. Add a short thread-safe cache/single-flight layer to the existing `DetectorSupport.makeContext()`, route `ps`/`lsof` execution through a timeout helper, and add delayed wake refresh handling in `MonitorViewModel`.

**Tech Stack:** Swift 6.2, Swift concurrency actors/tasks, Foundation `Process`, AppKit `NSWorkspace` notifications, Swift Package Manager tests.

---

### Task 1: Coalesce Process Snapshot Loading

**Files:**
- Modify: `Sources/VibeBarCore/DetectorSupport.swift`
- Test: `Tests/VibeBarCoreTests/DetectorSupportTests.swift` if existing patterns support it

**Step 1: Add a thread-safe process snapshot cache**

Create a private cache inside `DetectorSupport` that stores the latest `DetectionContext` with a timestamp and uses a condition lock to track an in-flight load.

**Step 2: Coalesce existing context loading**

Update `public static func makeContext(ttl: TimeInterval = 1) -> DetectionContext` so it:
- returns the cached context when it is younger than `ttl`
- waits for the in-flight load when one exists
- otherwise calls `listProcesses()` once and wakes any waiters

**Step 3: Preserve fresh-snapshot escape hatch**

Allow callers to pass `ttl: 0` to bypass the short cache when a fresh snapshot is required.

**Step 4: Verify**

Run: `swift build`
Expected: build succeeds.

### Task 2: Add External Command Timeouts

**Files:**
- Modify: `Sources/VibeBarCore/DetectorSupport.swift`

**Step 1: Add process output helper**

Implement a private helper that runs `Process`, reads stdout, and terminates the process if it exceeds a small timeout.

**Step 2: Use helper for `ps` and `lsof`**

Route these functions through the helper:
- `listProcesses()`
- `getCPUUsage(pid:)`
- `loadListeningPort(pid:)`
- `loadCwds(pids:)`
- `loadProcessEnvironment(pid:)`

**Step 3: Keep failure semantics unchanged**

Return empty arrays/dictionaries or `nil` on timeout, matching current run failure behavior.

**Step 4: Verify**

Run: `swift build`
Expected: build succeeds.

### Task 3: Debounce Wake Refreshes

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift`

**Step 1: Add wake observer state**

Add a notification observer token and a wake refresh task property to `MonitorViewModel`.

**Step 2: Observe wake notifications**

Register for `NSWorkspace.didWakeNotification` in init and remove the observer in deinit.

**Step 3: Delay one wake refresh**

On wake, cancel any previous wake task, then schedule a MainActor task that sleeps for a few seconds and calls `refreshNow()` if not paused.

**Step 4: Verify**

Run: `swift build`
Expected: build succeeds.

### Task 4: Full Verification

**Files:**
- No additional files expected

**Step 1: Run tests**

Run: `swift test`
Expected: tests pass, or existing unrelated failures are documented.

**Step 2: Inspect diff**

Run: `git diff -- Sources/VibeBarCore/DetectorSupport.swift Sources/VibeBarCore/CompositeSessionDetector.swift Sources/VibeBarApp/AppModel.swift Sources/VibeBarAgent/main.swift docs/plans/2026-04-29-process-scan-wake-cpu*.md`
Expected: diff only contains the planned minimal fix.

**Step 3: Commit**

Do not commit unless the user explicitly requests it.
