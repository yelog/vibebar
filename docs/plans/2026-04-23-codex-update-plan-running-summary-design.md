# Codex Update Plan Running Summary Design

**Problem:** Codex session cards in project grouping can show no third line while the rollout already contains a concrete in-progress plan step from `update_plan`.

**Decision:** Extract the current `in_progress` step from Codex rollout `response_item.function_call` events where `name == "update_plan"`, store it as `SessionSnapshot.runningSummary`, and let the existing three-line UI render it without changing display rules.

**Scope:**

- Parse `update_plan.arguments` in `Sources/VibeBarCore/CodexSessionDetector.swift`
- Add rollout summary state for the extracted running summary
- Populate `SessionSnapshot.runningSummary` from the parsed in-progress step
- Add detector tests covering valid, absent, and invalid `update_plan` payloads

**Out of Scope:**

- Changing hook payload formats or `vibebar-agent` Codex hook reduction
- Reworking session row layout, grouping behavior, or directory fallback rules
- Guessing running summaries from tool names, notes, or completed/pending plan steps

**Data Flow:**

- When `summarizeRollout(fileURL:)` sees `response_item` with `payload.type == "function_call"`
- If `payload.name == "update_plan"`, parse `payload.arguments` as JSON
- Read `plan[]`, find the first item with `status == "in_progress"`, and normalize its `step`
- Persist that value on `RolloutSummary`
- In `makeSessionSnapshot(...)`, copy the value into `SessionSnapshot.runningSummary`
- Existing UI code in `SessionDisplayFormatter` and `SessionCompactDetailLineBuilder` continues to render row 3 from `runningSummary`

**Fallback Rules:**

- If `update_plan` is missing, keep current behavior
- If `arguments` is invalid JSON, ignore it and continue
- If no `in_progress` step exists, do not synthesize a summary from `completed` or `pending`
- Empty or whitespace-only steps are treated as absent

**Validation:**

- Detector test confirms `runningSummary` is populated from an `in_progress` plan step
- Detector test confirms `runningSummary` stays `nil` when the plan has no `in_progress` step
- Detector test confirms invalid `arguments` JSON does not break detection or session metadata
