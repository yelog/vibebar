# OpenCode Stale Session Fallback Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Prevent a newly started OpenCode process from inheriting a stale title and timestamps from an older same-project SQLite session when no reliable session id is available yet.

**Architecture:** Keep the fix inside `OpenCodeHTTPDetector`'s SQLite fallback path. Derive the current process start time from `ps` elapsed seconds, only accept a `cwd`-matched SQLite session if it was created near or after that process start, and otherwise emit an unresolved process snapshot with no borrowed title or session id. Lock the behavior with focused Swift tests.

**Tech Stack:** Swift 6.2, SQLite3, Swift Testing

---

### Task 1: Add a failing regression for stale same-project fallback

**Files:**
- Create: `Tests/VibeBarCoreTests/OpenCodeHTTPDetectorTests.swift`
- Modify: `Sources/VibeBarCore/OpenCodeHTTPDetector.swift`

**Step 1: Write the failing test**

Add a test that builds a temporary `opencode.db` with:

- one `project.worktree = /Users/yelog/workspace/swift/VibeBar`
- one historical `session` row for that project with an old `title`
- a synthetic `DetectorSupport.ProcEntry` for a fresh `opencode` process with no `-s` argument

Assert that the helper deciding whether to reuse the `cwd`-matched session rejects the stale row.

**Step 2: Run the focused test to verify it fails**

Run: `swift test --filter OpenCodeHTTPDetectorTests`
Expected: FAIL because the current fallback accepts the most recently updated same-project session unconditionally.

### Task 2: Add freshness gating to `cwd` fallback

**Files:**
- Modify: `Sources/VibeBarCore/OpenCodeHTTPDetector.swift`
- Test: `Tests/VibeBarCoreTests/OpenCodeHTTPDetectorTests.swift`

**Step 1: Implement the smallest helper**

In `OpenCodeHTTPDetector.swift` add a small helper that:

- derives `processStartedAt = now - elapsedSeconds`
- returns `true` only when a `cwd`-matched SQLite session has `timeCreated >= processStartedAt - grace`

Keep explicit `-s` / `--session` lookup unchanged.

**Step 2: Use the helper in SQLite fallback**

When `querySessionByCwd` returns a stale row:

- do not copy `sessionId`
- do not copy `title`
- do not copy stale timestamps
- keep the current process visible as an unresolved OpenCode session

**Step 3: Re-run the focused test**

Run: `swift test --filter OpenCodeHTTPDetectorTests`
Expected: PASS for the stale-row regression.

### Task 3: Add the positive coverage for fresh fallback

**Files:**
- Modify: `Tests/VibeBarCoreTests/OpenCodeHTTPDetectorTests.swift`

**Step 1: Add a passing-path test**

Add a second test where the SQLite `timeCreated` is at or after the synthetic process start time and assert the helper accepts the `cwd`-matched row.

**Step 2: Run the focused detector tests**

Run: `swift test --filter OpenCodeHTTPDetectorTests`
Expected: PASS for both stale and fresh scenarios.

### Task 4: Full verification

**Files:**
- Modify: `Sources/VibeBarCore/OpenCodeHTTPDetector.swift` only if follow-up fixes are needed
- Modify: `Tests/VibeBarCoreTests/OpenCodeHTTPDetectorTests.swift` only if assertions need tightening

**Step 1: Run the focused detector tests**

Run: `swift test --filter OpenCodeHTTPDetectorTests`
Expected: PASS.

**Step 2: Run the broader package tests**

Run: `swift test`
Expected: PASS, or surface any unrelated pre-existing failures clearly.

**Step 3: Manually sanity-check the fix**

Launch a fresh `opencode` in a repo without `-s` and verify VibeBar no longer shows the previous session title before the new session is actually created.

**Step 4: Document outcome**

Summarize the root cause, the freshness heuristic, and any remaining limitations in the final response.
