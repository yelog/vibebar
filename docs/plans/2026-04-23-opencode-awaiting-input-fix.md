# OpenCode Awaiting Input Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make OpenCode interactions reliably appear in VibeBar and keep sessions in `awaiting_input` until an explicit interaction acknowledgement or OpenCode reply event arrives.

**Architecture:** Fix the state machine at the OpenCode plugin boundary so the plugin becomes the single source of truth for entering and exiting `awaiting_input`. Keep the existing Swift agent/App hydration flow, and add regression coverage on both the plugin and Swift merge logic so later progress events cannot silently clear a pending interaction.

**Tech Stack:** JavaScript ESM plugin, Node built-in test runner, Swift 6.2, Swift Testing

---

### Task 1: Add a plugin regression harness

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.js`
- Create: `plugins/opencode-vibebar-plugin/index.test.js`

**Step 1: Write the failing test for entering awaiting input**

Create `plugins/opencode-vibebar-plugin/index.test.js` with a Node test that:

- boots the plugin with a fake `ctx.client`
- captures outbound envelopes instead of writing to the real socket
- sends a synthetic `question.asked`
- asserts that an event with `status: "awaiting_input"` is emitted before the interaction is considered active

**Step 2: Run the test to verify it fails**

Run: `node --test plugins/opencode-vibebar-plugin/index.test.js`

Expected: FAIL because the current plugin does not emit an explicit `awaiting_input` status event on `question.asked`.

**Step 3: Add the minimal test seam**

Refactor `plugins/opencode-vibebar-plugin/index.js` so tests can inject mocked transport functions without changing runtime behavior. Keep production exports intact; add the smallest possible helper, for example a runtime factory used by both production code and tests.

**Step 4: Re-run the test harness**

Run: `node --test plugins/opencode-vibebar-plugin/index.test.js`

Expected: The harness loads and the original assertion still fails for the intended reason.

**Step 5: Commit**

```bash
git add plugins/opencode-vibebar-plugin/index.js plugins/opencode-vibebar-plugin/index.test.js
git commit -m "test: add opencode awaiting input harness"
```

### Task 2: Emit explicit awaiting-input state on interactions

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.js`
- Test: `plugins/opencode-vibebar-plugin/index.test.js`

**Step 1: Extend the failing test to cover both interaction types**

Add a second assertion or test case for `permission.asked` that expects:

- one `status_changed` event with `status: "awaiting_input"`
- one `interaction_request`

**Step 2: Implement the minimal event emission**

In `question.asked` and `permission.asked`:

- set the local state to `awaiting_input`
- emit `sendEvent(makeEvent("status_changed", "awaiting_input", ...))`
- then enqueue the interaction

Do not add a new protocol message type; reuse the existing event envelope.

**Step 3: Run the focused plugin tests**

Run: `node --test plugins/opencode-vibebar-plugin/index.test.js`

Expected: PASS for the explicit-enter-awaiting-input cases.

**Step 4: Commit**

```bash
git add plugins/opencode-vibebar-plugin/index.js plugins/opencode-vibebar-plugin/index.test.js
git commit -m "fix: emit opencode awaiting input state immediately"
```

### Task 3: Keep awaiting input sticky until explicit acknowledgement

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.js`
- Test: `plugins/opencode-vibebar-plugin/index.test.js`

**Step 1: Write a failing test for progress during a pending question**

Add a test sequence:

1. send `question.asked`
2. send `message.part.updated` for assistant output
3. send `session.status` with `busy`

Assert that no later `status_changed` event switches the session back to `running` while the interaction remains pending.

**Step 2: Run the focused test to verify it fails**

Run: `node --test plugins/opencode-vibebar-plugin/index.test.js --test-name-pattern "pending question"`

Expected: FAIL because the current plugin calls `markRunningFromProgress()` and resolves the interaction early.

**Step 3: Implement the minimal sticky-awaiting rule**

Update `plugins/opencode-vibebar-plugin/index.js` so that when `activeInteraction` or `interactionQueue` is non-empty:

- `message.part.updated` may update summaries, but must not call `markRunningFromProgress()`
- `session.status` values `busy` / `retry` must not clear the pending interaction
- heartbeat must remain informational only

Keep the logic local to the plugin state machine; do not move this policy into Swift.

**Step 4: Re-run the focused test**

Run: `node --test plugins/opencode-vibebar-plugin/index.test.js --test-name-pattern "pending question"`

Expected: PASS.

**Step 5: Commit**

```bash
git add plugins/opencode-vibebar-plugin/index.js plugins/opencode-vibebar-plugin/index.test.js
git commit -m "fix: keep opencode awaiting input until explicit reply"
```

### Task 4: Resume running only after ack or replied events

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.js`
- Test: `plugins/opencode-vibebar-plugin/index.test.js`

**Step 1: Write failing tests for the allowed exit paths**

Add tests for:

- `question.asked -> interaction_response ack -> running`
- `question.asked -> question.replied -> running`
- `permission.asked -> permission.replied -> running`

Each test should assert that `running` is emitted only after the explicit resolution signal.

**Step 2: Run the tests to verify failures**

Run: `node --test plugins/opencode-vibebar-plugin/index.test.js --test-name-pattern "running only after"`

Expected: At least one FAIL because current behavior can resume too early or inconsistently.

**Step 3: Implement the minimal explicit-exit rule**

Adjust the resolution paths in `plugins/opencode-vibebar-plugin/index.js` so that only:

- explicit ack responses
- `question.replied`
- `question.rejected`
- `permission.replied`

remove the active interaction and emit `status_changed(running)`.

**Step 4: Re-run the exit-path tests**

Run: `node --test plugins/opencode-vibebar-plugin/index.test.js --test-name-pattern "running only after"`

Expected: PASS.

**Step 5: Commit**

```bash
git add plugins/opencode-vibebar-plugin/index.js plugins/opencode-vibebar-plugin/index.test.js
git commit -m "fix: resume opencode running only after explicit interaction resolution"
```

### Task 5: Lock Swift-side merge behavior with regression tests

**Files:**
- Modify: `Tests/VibeBarAppTests/AppModelTests.swift`
- Modify: `Sources/VibeBarApp/AppModel.swift` if needed

**Step 1: Write the failing Swift regression**

Add a test near the existing OpenCode merge coverage in `Tests/VibeBarAppTests/AppModelTests.swift` that models:

- a plugin session in `awaitingInput`
- a matching interaction that still exists
- a detected OpenCode process update that only shows normal progress inside the grace window

Assert that the interaction remains active and the merged session stays in `awaitingInput`.

**Step 2: Run the focused Swift test**

Run: `swift test --filter AppModelTests`

Expected: Either PASS immediately, proving current Swift logic is already sufficient, or FAIL if a small merge adjustment is still needed.

**Step 3: Make the smallest Swift change only if required**

If the new test fails, update `Sources/VibeBarApp/AppModel.swift` with the smallest possible adjustment so App hydration still prefers a live OpenCode interaction over inferred progress.

**Step 4: Re-run the focused Swift test**

Run: `swift test --filter AppModelTests`

Expected: PASS.

**Step 5: Commit**

```bash
git add Tests/VibeBarAppTests/AppModelTests.swift Sources/VibeBarApp/AppModel.swift
git commit -m "test: cover opencode awaiting input merge behavior"
```

### Task 6: Full verification

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.js` only if follow-up fixes are needed
- Modify: `Tests/VibeBarAppTests/AppModelTests.swift` only if follow-up fixes are needed

**Step 1: Run plugin syntax validation**

Run: `node --check plugins/opencode-vibebar-plugin/index.js`

Expected: no output, exit code 0.

**Step 2: Run the plugin regression suite**

Run: `node --test plugins/opencode-vibebar-plugin/index.test.js`

Expected: PASS.

**Step 3: Run the targeted Swift tests**

Run: `swift test --filter AppModelTests`

Expected: PASS.

**Step 4: Run the full Swift test suite**

Run: `swift test`

Expected: PASS.

**Step 5: Commit verification-only follow-ups if needed**

```bash
git add plugins/opencode-vibebar-plugin/index.js plugins/opencode-vibebar-plugin/index.test.js Tests/VibeBarAppTests/AppModelTests.swift Sources/VibeBarApp/AppModel.swift
git commit -m "chore: finalize opencode awaiting input regression coverage"
```
