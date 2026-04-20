# Codex Session Name Semantics Design

**Problem:** Codex session cards can incorrectly show the latest user message as the session name even when the session already has an explicit `session name`.

**Decision:** Treat Codex `title` as explicit-only metadata. User prompts must not populate `title`. Instead, Codex cards should render three distinct lines:

- Line 1: explicit session name, otherwise `未命名会话`
- Line 2: latest user message
- Line 3: agent running summary, falling back to a non-title current task when needed

**Scope:**

- `CodexSessionDetector` should only set `title` from `thread_name`
- `vibebar-agent` Codex hook event reduction should only set `title` from explicit title keys
- Codex merge/display behavior should preserve explicit names and avoid using prompts as title fallback

**Out of Scope:**

- Changing naming behavior for OpenCode, Claude Code, Gemini, or other tools
- Reworking the three-line layout itself

**Validation:**

- Detector tests confirm unnamed Codex sessions keep `title == nil`
- App merge tests confirm explicit session names override derived/plugin titles
- Display formatter tests confirm unnamed Codex sessions show `未命名会话`, last user input on row 2, and agent progress on row 3
