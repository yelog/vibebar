# OpenCode Question Reply State Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make VibeBar submit complete OpenCode Question answers and keep the interaction in `awaiting_input` until OpenCode confirms the reply.

**Architecture:** Normalize every OpenCode question into the existing `PendingInteraction.prompts` model and rebuild the ordered `answers: string[][]` payload inside the plugin. Keep the current agent broker protocol: the App sends a decision, the plugin performs the real OpenCode reply, and only the plugin's ack or OpenCode replied/rejected event clears the persisted interaction. Remove only the App's premature OpenCode optimistic resolution; retain current local resolution for transports whose response is already authoritative.

**Tech Stack:** JavaScript ES modules and Node test runner, Swift 6.2, SwiftUI, Swift Testing, Unix-domain socket interaction broker

---

### Task 1: Normalize All OpenCode Questions

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.test.js`
- Modify: `plugins/opencode-vibebar-plugin/index.js:416-445`

**Step 1: Write the failing multi-question interaction test**

Extend `questionAskedEvent` so tests can provide a questions array while preserving its current default. Add a test that emits two questions and verifies both are represented as prompts in order:

```js
function questionAskedEvent(questions = [
  {
    header: "工作模式",
    question: "接下来怎么做？",
    options: [
      { label: "直接实现", description: "本会话继续修改" },
      { label: "只保留计划", description: "先不写代码" },
    ],
  },
]) {
  return {
    event: {
      type: "question.asked",
      properties: {
        id: "que_123",
        sessionID: "ses_123",
        questions,
      },
    },
  };
}

test("question.asked preserves every question as an ordered prompt", async () => {
  const fixture = await makeFixture();
  const questions = [
    {
      header: "工作模式",
      question: "接下来怎么做？",
      options: [{ label: "直接实现", description: "继续修改" }],
      custom: false,
    },
    {
      header: "验证范围",
      question: "运行哪些检查？",
      options: [
        { label: "相关测试", description: "只运行相关测试" },
        { label: "完整测试", description: "运行完整测试" },
      ],
      multiple: true,
      custom: true,
    },
  ];

  await fixture.plugin.event(questionAskedEvent(questions));

  const interaction = fixture.interactionRequests[0];
  assert.equal(interaction.prompts.length, 2);
  assert.deepEqual(interaction.prompts.map((prompt) => prompt.id), ["question.0", "question.1"]);
  assert.equal(interaction.prompts[0].title, "接下来怎么做？");
  assert.equal(interaction.prompts[1].allows_multiple_selection, true);
  assert.equal(interaction.prompts[1].allows_free_text, true);
  assert.equal(interaction.prompts[1].metadata.question_index, "1");
  assert.equal(interaction.transport_context.opencode_session_id, "ses_123");
});
```

Also assert that the one-question fixture still populates top-level `title`, `message`, and `options`, preserving the current compact UI.

**Step 2: Run the plugin test and verify it fails**

Run:

```bash
node --test plugins/opencode-vibebar-plugin/index.test.js --test-name-pattern "ordered prompt"
```

Expected: FAIL because `buildQuestionInteraction` currently reads only `questions[0]` and does not emit `prompts`.

**Step 3: Implement complete question normalization**

Replace the first-question-only conversion with an ordered prompt conversion. Use local array indexes as stable keys because OpenCode question entries do not expose their own IDs:

```js
function buildQuestionPrompt(question, index) {
  const options = (question?.options || []).map((option, optionIndex) => ({
    id: String(optionIndex),
    label: option.label,
    detail: option.description,
  }));

  return clean({
    id: `question.${index}`,
    title: question?.question || question?.header || `Question ${index + 1}`,
    options,
    allows_free_text: Boolean(question?.custom ?? question?.text),
    allows_multiple_selection: Boolean(question?.multiple),
    metadata: {
      question_index: String(index),
      header: question?.header || "",
    },
  });
}

function buildQuestionInteraction(event) {
  const questions = event?.properties?.questions || [];
  if (questions.length === 0) return null;

  const prompts = questions.map(buildQuestionPrompt);
  const firstQuestion = questions[0];
  const firstPrompt = prompts[0];

  return clean({
    id: makeInteractionID(event.properties.id),
    session_id: instanceID,
    tool: "opencode",
    kind: "question",
    title: firstQuestion.header || "需要回答",
    message: firstQuestion.question || "请选择一个选项",
    options: firstPrompt.options,
    prompts,
    allows_free_text: firstPrompt.allows_free_text,
    requested_at: new Date().toISOString(),
    expires_at: interactionExpiresAt(),
    transport_context: {
      source: "opencode-plugin",
      request_kind: "question",
      opencode_request_id: event.properties.id,
      opencode_session_id: opencodeSessionID(event),
      question_count: String(questions.length),
    },
  });
}
```

Use `question.custom` as the current protocol field and retain `question.text` only as a compatibility fallback.

**Step 4: Run focused and complete plugin tests**

Run:

```bash
node --test plugins/opencode-vibebar-plugin/index.test.js --test-name-pattern "question.asked"
node --test plugins/opencode-vibebar-plugin/index.test.js
```

Expected: PASS.

**Step 5: Commit**

```bash
git add plugins/opencode-vibebar-plugin/index.js plugins/opencode-vibebar-plugin/index.test.js
git commit -m "fix(opencode): preserve all question prompts"
```

---

### Task 2: Rebuild Ordered OpenCode Answers

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.test.js`
- Modify: `plugins/opencode-vibebar-plugin/index.js:460-487`

**Step 1: Write failing answer reconstruction tests**

Allow `makeFixture` to accept `ctx` and hook overrides so tests can inject a Question SDK client and a pre-resolved interaction response:

```js
async function makeFixture({ ctx = {}, interactionResponse } = {}) {
  // Keep the existing event arrays and defaults.
  // Resolve sendInteractionRequest with interactionResponse when supplied;
  // otherwise retain pendingInteractionResponse.promise.
  const plugin = await createPluginRuntime(
    {
      directory: "/tmp/vibebar-opencode-test",
      client: {},
      ...ctx,
    },
    // existing hooks
  );
  // return existing fixture values
}
```

Add a test whose decision contains ordered prompt answers and JSON-encoded multi-selection values:

```js
test("question reply reconstructs ordered answers for every prompt", async () => {
  const replies = [];
  const fixture = await makeFixture({
    ctx: {
      client: {
        question: {
          reply: async (parameters) => {
            replies.push(parameters);
            return {};
          },
        },
      },
    },
    interactionResponse: {
      response: {
        decision: {
          behavior: "select",
          metadata: {
            "answer.question.0": "直接实现",
            "selected_values.question.1": "[\"相关测试\",\"完整测试\"]",
          },
        },
      },
    },
  });

  await fixture.plugin.event(questionAskedEvent([
    {
      header: "工作模式",
      question: "接下来怎么做？",
      options: [{ label: "直接实现" }],
    },
    {
      header: "验证范围",
      question: "运行哪些检查？",
      multiple: true,
      options: [{ label: "相关测试" }, { label: "完整测试" }],
    },
  ]));
  await fixture.flushInteraction();

  assert.deepEqual(replies[0].answers, [
    ["直接实现"],
    ["相关测试", "完整测试"],
  ]);
  assert.deepEqual(fixture.interactionResponses, [
    { rawRequestID: "que_123", decision: undefined },
  ]);
});
```

Add separate tests for:

- a one-question top-level `decision.optionID` fallback;
- free text in `answer.question.0`;
- missing one of two answers returning failure and sending no ack;
- malformed JSON multi-selection falling back to a single literal value rather than throwing.

Use an explicit `flushInteraction` deferred in the fixture so tests await queue processing instead of relying on timers.

**Step 2: Run the focused test and verify it fails**

Run:

```bash
node --test plugins/opencode-vibebar-plugin/index.test.js --test-name-pattern "reconstructs ordered answers"
```

Expected: FAIL because `questionAnswersFromDecision` currently returns one answer or alphabetically sorts arbitrary `answer.*` keys without validating against `interaction.prompts`.

**Step 3: Implement ordered answer parsing**

Replace `questionAnswersFromDecision` with prompt-driven reconstruction:

```js
function decodedSelectedValues(raw) {
  if (!raw || typeof raw !== "string") return null;
  try {
    const values = JSON.parse(raw);
    if (!Array.isArray(values)) return null;
    const normalized = values.map((value) => String(value).trim()).filter(Boolean);
    return normalized.length > 0 ? normalized : null;
  } catch {
    const value = raw.trim();
    return value ? [value] : null;
  }
}

function answerForPrompt(decision, prompt) {
  const metadata = decision?.metadata || {};
  const answerKey = `answer.${prompt.id}`;
  const selectedValuesKey = `selected_values.${prompt.id}`;
  const selectedValues = decodedSelectedValues(metadata[selectedValuesKey]);
  if (selectedValues) return selectedValues;

  const answer = String(metadata[answerKey] || "").trim();
  return answer ? [answer] : null;
}

function questionAnswersFromDecision(decision, interaction) {
  if (!decision) return null;

  const prompts = interaction.prompts || [];
  if (prompts.length > 0) {
    const answers = prompts.map((prompt) => answerForPrompt(decision, prompt));
    if (answers.some((answer) => !answer)) return null;
    return answers;
  }

  const text = decision.text?.trim();
  if (text) return [[text]];

  if (decision.optionID) {
    const label = interaction.options?.find((option) => option.id === decision.optionID)?.label?.trim();
    if (label) return [[label]];
  }

  return null;
}
```

For a single normalized prompt, preserve compatibility with existing top-level `text` and `optionID` decisions when no `answer.<promptID>` metadata exists. Do not sort metadata keys; prompt order is the protocol order.

**Step 4: Run plugin tests**

Run:

```bash
node --test plugins/opencode-vibebar-plugin/index.test.js
```

Expected: PASS.

**Step 5: Commit**

```bash
git add plugins/opencode-vibebar-plugin/index.js plugins/opencode-vibebar-plugin/index.test.js
git commit -m "fix(opencode): submit complete question answers"
```

---

### Task 3: Encode Multi-Selection Without Delimiter Loss

**Files:**
- Modify: `Sources/VibeBarApp/SessionInteractionContentView.swift:180-217`
- Create: `Tests/VibeBarAppTests/InteractionDecisionMetadataTests.swift`

**Step 1: Extract a testable metadata builder and write failing tests**

Move only the pure metadata assembly from the SwiftUI view into an internal enum in the same source file so no new production file or public API is needed:

```swift
enum InteractionDecisionMetadataBuilder {
    static func build(
        interaction: PendingInteraction,
        prompts: [InteractionPrompt],
        answerKeys: [String],
        textAnswers: [String: String],
        selectedOptionIDs: [String: String],
        selectedOptionLabels: [String: String],
        selectedMultiValues: [String: Set<String>]
    ) -> [String: String] {
        // implementation added after the failing test
        [:]
    }
}
```

Create tests for ordered prompt keys and JSON multi-selection encoding:

```swift
import Foundation
import Testing
@testable import VibeBarApp
@testable import VibeBarCore

@Test func interactionDecisionMetadataEncodesMultiSelectionAsJSON() throws {
    let prompts = [
        InteractionPrompt(
            id: "question.0",
            title: "选择检查",
            options: [],
            allowsMultipleSelection: true
        ),
    ]
    let interaction = PendingInteraction(
        id: "opencode-que_123",
        sessionID: "plugin-opencode-test",
        tool: .opencode,
        kind: .question,
        message: "选择检查",
        prompts: prompts,
        requestedAt: Date()
    )

    let metadata = InteractionDecisionMetadataBuilder.build(
        interaction: interaction,
        prompts: prompts,
        answerKeys: ["question.0"],
        textAnswers: [:],
        selectedOptionIDs: [:],
        selectedOptionLabels: [:],
        selectedMultiValues: ["question.0": ["完整测试", "相关测试"]]
    )

    let raw = try #require(metadata["selected_values.question.0"])
    let values = try JSONDecoder().decode([String].self, from: Data(raw.utf8))
    #expect(values == ["完整测试", "相关测试"])
    #expect(metadata["answer.question.0"] == "完整测试, 相关测试")
}
```

Add tests showing single selections and free text retain their existing metadata keys.

**Step 2: Run the focused Swift test and verify it fails**

Run:

```bash
swift test --filter InteractionDecisionMetadataTests
```

Expected: FAIL because the builder does not yet exist or returns empty metadata.

**Step 3: Implement the builder and call it from the view**

Keep human-readable `answer.<key>` for existing consumers, but encode `selected_values.<key>` as a sorted JSON array:

```swift
if let values = selectedMultiValues[answerKey], !values.isEmpty {
    let sortedValues = values.sorted()
    let joined = sortedValues.joined(separator: ", ")
    metadata["answer.\(answerKey)"] = joined
    metadata["selected_values"] = joined
    if let data = try? JSONEncoder().encode(sortedValues),
       let json = String(data: data, encoding: .utf8) {
        metadata["selected_values.\(answerKey)"] = json
    }
}
```

Retain all current `prompt_id.*`, `option_id.*`, `comment`, and top-level `selected_values` behavior. Change `structuredMetadata()` to delegate to `InteractionDecisionMetadataBuilder.build(...)`.

**Step 4: Run focused tests and the App test target**

Run:

```bash
swift test --filter InteractionDecisionMetadataTests
swift test --filter VibeBarAppTests
```

Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/SessionInteractionContentView.swift Tests/VibeBarAppTests/InteractionDecisionMetadataTests.swift
git commit -m "fix(app): encode structured interaction selections"
```

---

### Task 4: Stop Optimistically Resolving Plugin Interactions

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift:363-376`
- Modify: `Tests/VibeBarAppTests/AppModelTests.swift`

**Step 1: Add a pure policy and failing tests**

Because `resolveInteraction` depends on the shared actor and AppKit sound, isolate the transport decision as a small internal policy:

```swift
nonisolated static func shouldResolveInteractionLocally(_ interaction: PendingInteraction) -> Bool {
    interaction.transportContext["source"] != "opencode-plugin"
}
```

Add two tests to `AppModelTests.swift`:

```swift
@Test func opencodePluginInteractionWaitsForPluginAcknowledgement() {
    let interaction = PendingInteraction(
        id: "opencode-que_123",
        sessionID: "plugin-opencode-test",
        tool: .opencode,
        kind: .question,
        message: "请选择",
        requestedAt: Date(),
        transportContext: ["source": "opencode-plugin"]
    )

    #expect(MonitorViewModel.shouldResolveInteractionLocally(interaction) == false)
}

@Test func synchronousInteractionMayStillResolveLocally() {
    let interaction = PendingInteraction(
        id: "other-request",
        sessionID: "other-session",
        tool: .codex,
        kind: .question,
        message: "请选择",
        requestedAt: Date()
    )

    #expect(MonitorViewModel.shouldResolveInteractionLocally(interaction))
}
```

**Step 2: Run the focused tests and verify they fail**

Run:

```bash
swift test --filter "opencodePluginInteractionWaitsForPluginAcknowledgement|synchronousInteractionMayStillResolveLocally"
```

Expected: FAIL because `shouldResolveInteractionLocally` does not exist.

**Step 3: Implement the minimal confirmation policy**

Add the policy next to `resolveInteraction` and guard the optimistic local update:

```swift
func resolveInteraction(_ interaction: PendingInteraction, decision: InteractionDecision) {
    Task { @MainActor [weak self] in
        let sessionPID = self?.sessions.first(where: { $0.id == interaction.sessionID })?.pid
        let success = await InteractionActionHandler.shared.submit(
            interaction: interaction,
            decision: decision,
            sessionPID: sessionPID
        )
        guard success else {
            NSSound.beep()
            return
        }
        guard Self.shouldResolveInteractionLocally(interaction) else {
            self?.refreshNow()
            return
        }
        self?.applyResolvedInteractionLocally(interaction, decision: decision)
    }
}

nonisolated static func shouldResolveInteractionLocally(_ interaction: PendingInteraction) -> Bool {
    interaction.transportContext["source"] != "opencode-plugin"
}
```

Do not special-case `.opencode` alone. Only plugin interactions use the deferred ack protocol; legacy or future transports must retain their defined behavior.

**Step 4: Run App tests**

Run:

```bash
swift test --filter VibeBarAppTests
```

Expected: PASS. Existing `InteractionActionHandlerTests` must continue proving that the original decision reaches the agent unchanged.

**Step 5: Commit**

```bash
git add Sources/VibeBarApp/AppModel.swift Tests/VibeBarAppTests/AppModelTests.swift
git commit -m "fix(app): wait for opencode reply acknowledgement"
```

---

### Task 5: Verify Failure and Reply-Event Races

**Files:**
- Modify: `plugins/opencode-vibebar-plugin/index.test.js`
- Modify only if tests expose a defect: `plugins/opencode-vibebar-plugin/index.js:598-689`

**Step 1: Add a failed-reply state test**

Inject a Question client whose `reply` returns an error and disable HTTP fallback with a fetch hook or a deliberately failing `serverUrl`. Assert:

```js
test("failed question reply stays pending and sends no running or ack", async () => {
  // Arrange a question decision and force both SDK and HTTP reply to fail.
  // Await the first reply attempt and scheduled retry registration.
  assert.deepEqual(fixture.interactionResponses, []);
  assert.equal(fixture.events.some((event) => event.status === "running"), false);
  assert.equal(fixture.scheduledTimeouts.length, 1);
});
```

Expose `fetch` through `hooks.fetch ?? globalThis.fetch` before this test so transport failure is deterministic and no real network request occurs.

**Step 2: Add a reply-event race test**

Hold the SDK reply Promise, emit `question.replied`, then resolve the Promise. Assert that:

- only one ack is sent for `que_123`;
- only one `running` transition is emitted;
- the interaction is not requeued;
- a later queued interaction remains intact.

```js
test("question.replied racing SDK completion resolves exactly once", async () => {
  // Start interaction and deliver the VibeBar decision.
  // Emit question.replied before resolving the SDK deferred.
  // Resolve the deferred and flush promises.
  assert.equal(
    fixture.interactionResponses.filter((item) => item.rawRequestID === "que_123").length,
    1,
  );
  assert.deepEqual(statusSequence(fixture.events), ["running"]);
});
```

**Step 3: Run the race tests and verify current behavior**

Run:

```bash
node --test plugins/opencode-vibebar-plugin/index.test.js --test-name-pattern "failed question reply|racing SDK completion"
```

Expected: the failure test should pass after Tasks 1-2. The race test may fail because both `completeResolvedInteraction` and `question.replied` can acknowledge and emit `running`.

**Step 4: Make completion idempotent if required**

Use the existing `resolvedInteractionIDs` as the single completion gate. Add a helper that returns whether this call won resolution:

```js
function markInteractionResolved(interactionID) {
  if (!interactionID || resolvedInteractionIDs.has(interactionID)) return false;
  resolvedInteractionIDs.add(interactionID);
  removeInteractionID(interactionID);
  return true;
}
```

Adjust `removeInteractionID` so it only removes active/queued entries and does not independently add to `resolvedInteractionIDs`. Gate ack and `running` emission in both successful reply processing and replied/rejected event handlers with `markInteractionResolved(makeInteractionID(requestID))`.

Preserve FIFO processing: resolving the active item must call `processInteractionQueue`, but must not delete the next item.

**Step 5: Run all plugin tests**

Run:

```bash
node --check plugins/opencode-vibebar-plugin/index.js
node --test plugins/opencode-vibebar-plugin/index.test.js
```

Expected: PASS with no duplicate ack or `running` event.

**Step 6: Commit**

```bash
git add plugins/opencode-vibebar-plugin/index.js plugins/opencode-vibebar-plugin/index.test.js
git commit -m "fix(opencode): make question completion idempotent"
```

---

### Task 6: Full Regression and Manual Verification

**Files:**
- Modify only if behavior changed from the confirmed design: `docs/plans/2026-08-23-opencode-question-reply-state-design.md`

**Step 1: Run all automated checks**

Run:

```bash
node --check plugins/opencode-vibebar-plugin/index.js
node --test plugins/opencode-vibebar-plugin/index.test.js
swift test --filter VibeBarAppTests
swift test
```

Expected: all commands exit `0`. Do not treat existing unrelated failures as passing; record and isolate them before continuing.

**Step 2: Verify single-question reply manually**

1. Run `swift run vibebar-agent --verbose`.
2. Run `VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp`.
3. Start OpenCode with the local VibeBar plugin enabled.
4. Trigger one Question with two options.
5. Select an option in VibeBar.
6. Confirm OpenCode logs one `replied requestID=... answers=...` entry and resumes.
7. Confirm VibeBar does not show a false `running -> awaiting_input` transition.

**Step 3: Verify multi-question reply manually**

Trigger one OpenCode Question request containing two questions, including one multiple-selection question. Confirm:

- VibeBar displays both prompts;
- all required answers can be entered before submission;
- OpenCode logs one ordered two-element `answers` array;
- the original OpenCode request disappears and execution resumes once.

**Step 4: Verify transport failure manually**

Temporarily make the plugin reply transport fail using a test-only environment or injected local build; do not change user OpenCode configuration destructively. Confirm:

- VibeBar remains `awaiting_input`;
- the pending interaction remains visible;
- no success ack is written;
- restoring transport and retrying resolves the same request once.

**Step 5: Review the final diff**

Run:

```bash
git status --short
git diff --check
git diff -- plugins/opencode-vibebar-plugin/index.js plugins/opencode-vibebar-plugin/index.test.js Sources/VibeBarApp/AppModel.swift Sources/VibeBarApp/SessionInteractionContentView.swift Tests/VibeBarAppTests/AppModelTests.swift Tests/VibeBarAppTests/InteractionDecisionMetadataTests.swift docs/plans/2026-08-23-opencode-question-reply-state-design.md docs/plans/2026-08-23-opencode-question-reply-state.md
```

Expected: only intended files are changed, `git diff --check` exits `0`, and no generated files or local paths were added.

**Step 6: Commit verification/documentation changes if any**

If verification required a design-document correction:

```bash
git add docs/plans/2026-08-23-opencode-question-reply-state-design.md docs/plans/2026-08-23-opencode-question-reply-state.md
git commit -m "docs(opencode): finalize question reply verification"
```

If no documentation changed, do not create an empty commit.
