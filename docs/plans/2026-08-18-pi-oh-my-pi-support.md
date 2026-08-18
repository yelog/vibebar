# Pi and Oh My Pi Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Pi and Oh My Pi as separate VibeBar tools with real-time extension events, session metadata, managed extension installation, and process-scan fallback.

**Architecture:** A dependency-free bundled extension maps Pi/OMP lifecycle events into the existing `AgentEvent` socket envelope. Swift models, plugin management, and monitor merging treat extension sessions as authoritative and process scans as fallback. Pi and OMP share implementation infrastructure but retain separate identities and installation roots.

**Tech Stack:** Swift 6.2, Swift Package Manager, Swift Testing, Foundation Unix sockets, TypeScript/JavaScript extensions, Node test runner

---

## Scope Guard

This plan does not add `UsageSource` cases, usage loaders, pending interactions, or response transports. Do not parse Pi/OMP JSONL as a primary detector in this change.

### Task 1: Add Pi and OMP domain identities

**Files:**
- Modify: `Sources/VibeBarCore/Models.swift:3-146`
- Modify: `Package.swift:55-63`
- Create: `Sources/VibeBarApp/Resources/pi.png`
- Create: `Sources/VibeBarApp/Resources/ohMyPi.png`
- Create: `Tests/VibeBarCoreTests/ToolKindTests.swift`

**Step 1: Write failing ToolKind tests**

Cover:

```swift
#expect(ToolKind.fromCLIArgument("pi") == .pi)
#expect(ToolKind.fromCLIArgument("omp") == .ohMyPi)
#expect(ToolKind.fromCLIArgument("oh-my-pi") == .ohMyPi)
#expect(ToolKind.detect(command: "/opt/homebrew/bin/pi", args: "pi") == .pi)
#expect(ToolKind.detect(command: "/opt/homebrew/bin/omp", args: "omp") == .ohMyPi)
#expect(ToolKind.detect(command: "/usr/bin/env", args: "pi --model x") == .pi)
#expect(ToolKind.detect(command: "/usr/bin/env", args: "omp --profile work") == .ohMyPi)
```

Also assert display names, short names, executable names, icon resource names, and that `pi` does not match `omp` or unrelated argument text.

**Step 2: Verify the tests fail**

Run: `swift test --filter ToolKindTests`

Expected: compilation fails because `.pi` and `.ohMyPi` do not exist.

**Step 3: Implement the two cases**

Add:

```swift
case pi = "pi"
case ohMyPi = "oh-my-pi"
```

Complete every exhaustive switch in `ToolKind`, add CLI aliases, and recognize only command basenames or the existing first-two-token runtime pattern. Do not use broad substring matching.

**Step 4: Add and register icons**

Add distinct PNG assets and `.process` entries in `Package.swift`. Preserve the existing SF Symbol fallback behavior.

**Step 5: Verify the task**

Run: `swift test --filter ToolKindTests`

Expected: PASS.

Run: `swift build --target VibeBarApp`

Expected: PASS with all new exhaustive switches handled.

**Suggested commit, only when commits are requested:** `feat(core): add pi and oh-my-pi tool identities`

### Task 2: Add detection defaults and migrate existing configurations

**Files:**
- Modify: `Sources/VibeBarCore/CLISettingsConfiguration.swift:80-125,231-357`
- Modify: `Tests/VibeBarCoreTests/CLISettingsConfigurationTests.swift`

**Step 1: Write failing configuration tests**

Assert:

```swift
#expect(CLIToolConfiguration.defaultMethods(for: .pi) == [.plugin, .processScan])
#expect(CLIToolConfiguration.defaultMethods(for: .ohMyPi) == [.plugin, .processScan])
#expect(CLIToolConfiguration.availableMethods(for: .pi) == [.plugin, .processScan])
#expect(CLIToolConfiguration.availableMethods(for: .ohMyPi) == [.plugin, .processScan])
#expect(CLIToolConfiguration.hasPluginSupport(for: .pi))
#expect(CLIToolConfiguration.hasPluginSupport(for: .ohMyPi))
```

Add a migration fixture representing persisted version 6 settings without the new dictionary keys. Assert the loaded result preserves all existing tool preferences and inserts default configurations for both new tools.

**Step 2: Verify failure**

Run: `swift test --filter CLISettingsConfigurationTests`

Expected: new cases are absent from defaults/migration.

**Step 3: Implement defaults and migration version 7**

- Return `[.plugin, .processScan]` for both tools.
- Include both in `hasPluginSupport`.
- Add missing configurations without overwriting existing entries.
- Advance `cliConfigMigrationVersion` to 7 only after both entries are populated.

**Step 4: Verify the task**

Run: `swift test --filter CLISettingsConfigurationTests`

Expected: PASS.

**Suggested commit, only when commits are requested:** `feat(settings): configure pi family detection defaults`

### Task 3: Build the shared Pi-family extension runtime

**Files:**
- Create: `plugins/pi-vibebar-extension/package.json`
- Create: `plugins/pi-vibebar-extension/runtime.js`
- Create: `plugins/pi-vibebar-extension/pi/index.ts`
- Create: `plugins/pi-vibebar-extension/omp/index.ts`
- Create: `plugins/pi-vibebar-extension/runtime.test.js`
- Modify: `.github/workflows/plugins-ci.yml`

**Step 1: Write failing runtime tests**

Use injected transport, clock, and scheduler functions. Cover:

- Pi emits `source: "pi-extension"`, `tool: "pi"`, and `command: ["pi"]`.
- OMP emits `source: "oh-my-pi-extension"`, `tool: "oh-my-pi"`, and `command: ["omp"]`.
- `session_start` emits idle with session ID, title, cwd, transcript path, PID, parent PID, and terminal metadata.
- `input` emits running with `last_user_message` and `current_task`.
- tool start/update emits a bounded tool summary.
- Pi `agent_settled` and OMP `session_stop` emit idle.
- `session_shutdown` emits `session_ended` and clears pending summary work.
- multiple `message_update` calls in 500 ms produce one trailing event containing the latest bounded summary.
- rejected socket connections resolve without throwing.

**Step 2: Verify failure**

Run: `node --test plugins/pi-vibebar-extension/runtime.test.js`

Expected: FAIL because the runtime does not exist.

**Step 3: Implement a dependency-free runtime factory**

Expose a factory shaped like:

```javascript
export function createVibeBarExtension(options) {
  return function register(pi) {
    // Register common events and the product-specific settled event.
  };
}
```

Parameters must include `source`, `tool`, `executable`, and `settledEvent`. Keep transport and scheduling injectable for tests.

Send the existing envelope:

```json
{
  "kind": "event",
  "event": {
    "version": 1,
    "source": "pi-extension",
    "tool": "pi",
    "session_id": "...",
    "event_type": "status_changed",
    "status": "running"
  }
}
```

Prefer runtime APIs for session ID/name/path, but use guarded feature detection so a missing optional accessor does not abort extension loading.

**Step 4: Add thin adapters**

- Pi adapter: settled event `agent_settled`.
- OMP adapter: settled event `session_stop`.
- Both import only the local runtime; do not depend on either product package at runtime.

**Step 5: Add syntax and test checks to CI**

Run:

```bash
node --check plugins/pi-vibebar-extension/runtime.js
node --test plugins/pi-vibebar-extension/runtime.test.js
```

Expected: PASS.

**Suggested commit, only when commits are requested:** `feat(plugins): emit pi family lifecycle events`

### Task 4: Implement managed extension installation

**Files:**
- Create: `Sources/VibeBarCore/PiFamilyExtensionInstaller.swift`
- Create: `Tests/VibeBarCoreTests/PiFamilyExtensionInstallerTests.swift`
- Modify: `component-versions.json`

**Step 1: Write failing installer tests**

Inject home directory, plugin source directory, CLI existence provider, and file manager-facing paths. Cover:

1. Pi target: `~/.pi/agent/extensions/vibebar`.
2. OMP default target: `~/.omp/agent/extensions/vibebar`.
3. OMP targets include each existing `~/.omp/profiles/*/agent` directory.
4. Empty/non-directory profile entries are ignored.
5. Install copies the selected adapter as `index.ts`, shared runtime, marker, and version.
6. Detection distinguishes CLI missing, not installed, installed, partial installation, and old version.
7. Reinstall repairs partial targets and adds a newly created profile.
8. Uninstall removes only directories with the exact managed marker.
9. Uninstall preserves an unmarked `vibebar` directory and unrelated extensions.
10. A staging failure leaves the previous managed installation intact.

**Step 2: Verify failure**

Run: `swift test --filter PiFamilyExtensionInstallerTests`

Expected: FAIL because the installer does not exist.

**Step 3: Implement installer types**

Use a product enum or configuration value containing:

```swift
tool: ToolKind
executable: String
adapterDirectoryName: String
destinationRoots: [URL]
```

Resolve source files from `VibeBarPaths.pluginsDirectory/pi-vibebar-extension`. Read the bundled version from `component-versions.json` through the existing component-version infrastructure; add `piFamilyExtensionVersion` to the manifest.

**Step 4: Implement atomic managed-directory replacement**

- Stage a complete directory next to the destination.
- Validate required files before publication.
- Move the prior managed directory aside, publish staging, then remove backup.
- On failure, restore the prior directory.
- Never replace or delete an unmarked destination.

**Step 5: Verify the task**

Run: `swift test --filter PiFamilyExtensionInstallerTests`

Expected: PASS.

**Suggested commit, only when commits are requested:** `feat(core): manage pi family extensions`

### Task 5: Integrate plugin status and settings actions

**Files:**
- Modify: `Sources/VibeBarCore/PluginDetector.swift:3-265`
- Modify: `Sources/VibeBarApp/AppModel.swift:340-348,602-782`
- Modify: `Sources/VibeBarApp/CLISettingsView.swift:745-1145`
- Modify: `Sources/VibeBarCore/L10nStrings.swift`
- Create: `Tests/VibeBarCoreTests/PluginDetectorTests.swift`

**Step 1: Write failing plugin orchestration tests**

Test `PluginStatusReport.visibleItems` ordering and visibility for Claude, Codex-independent existing entries, OpenCode, Pi, and OMP. Inject installer results so Pi and OMP can independently be missing, installed, partial, or update available.

**Step 2: Verify failure**

Run: `swift test --filter PluginDetectorTests`

Expected: FAIL because the report has no Pi-family fields.

**Step 3: Extend plugin reporting**

- Add Pi and OMP statuses to `PluginStatusReport`.
- Detect both concurrently in `detectAll()`.
- Delegate install/update/uninstall to `PiFamilyExtensionInstaller`.
- Map a partial OMP installation to an actionable status with a localized detail message; do not silently label it installed.

**Step 4: Complete AppModel switches**

Add `.pi` and `.ohMyPi` to:

- `pluginStatus(for:)`;
- `installPlugin(tool:)`;
- `uninstallPlugin(tool:)`;
- `updatePlugin(tool:)`;
- `bundledPluginVersion(for:)`;
- plugin update prompt bookkeeping.

**Step 5: Reuse the settings plugin row**

Update `methodDescription` for both tools and show the OMP profile synchronization detail when relevant. Do not add a new settings tab.

**Step 6: Verify the task**

Run: `swift test --filter PluginDetectorTests`

Expected: PASS.

Run: `swift build --target VibeBarApp`

Expected: PASS.

**Suggested commit, only when commits are requested:** `feat(app): expose pi extension management`

### Task 6: Accept Pi-family event sources

**Files:**
- Modify: `Sources/VibeBarCore/AgentEvents.swift`
- Modify: `Sources/VibeBarCore/AgentEventReducer.swift`
- Modify: `Tests/VibeBarCoreTests/AgentMessageTests.swift`
- Modify: `Tests/VibeBarCoreTests/AgentEventReducerTests.swift`

**Step 1: Write failing decoding and reduction tests**

Decode representative events for both new source strings. Assert:

- event envelope decoding succeeds;
- composite session IDs remain distinct between Pi and OMP even if raw session IDs match;
- explicit running/idle status wins;
- `session_ended` requests deletion;
- title, last user message, current task, running summary, and transcript path metadata survive decoding.

**Step 2: Verify failure**

Run: `swift test --filter AgentMessageTests`

Expected: decoding fails for unknown source enum values.

**Step 3: Add source cases and rely on the generic reducer**

Add:

```swift
case piExtension = "pi-extension"
case ohMyPiExtension = "oh-my-pi-extension"
```

Only add reducer special cases if a failing test demonstrates generic explicit-status handling is insufficient.

**Step 4: Verify the task**

Run: `swift test --filter AgentMessageTests`

Run: `swift test --filter AgentEventReducerTests`

Expected: PASS.

**Suggested commit, only when commits are requested:** `feat(agent): accept pi family events`

### Task 7: Merge extension and process sessions without duplicates

**Files:**
- Modify: `Sources/VibeBarApp/AppModel.swift:550-600,1500-1700`
- Modify: `Tests/VibeBarAppTests/AppModelTests.swift`

**Step 1: Write failing merge tests**

Cover both tools:

1. Plugin and process sessions with the same PID become one session.
2. Plugin state, title, user message, and running summary win.
3. Process cwd, start time, and terminal context fill missing plugin fields.
4. A stable Pi-family session ID correlates a PID change without duplicating the session.
5. Equal raw session IDs from Pi and OMP remain separate because their source prefixes differ.
6. Unrelated sessions with no safe PID or stable-ID correlation remain separate.
7. Disabling `.plugin` excludes persisted realtime sessions while `.processScan` still works.

**Step 2: Verify failure**

Run: `swift test --filter AppModelTests`

Expected: realtime method and stable-ID merge cases fail.

**Step 3: Enable realtime configuration**

Update `realtimeEventMethod(for:)`:

```swift
case .claudeCode, .opencode, .pi, .ohMyPi:
    return .plugin
```

**Step 4: Generalize stable plugin session correlation**

Extend the current Codex-specific ID correlation with a narrowly scoped helper that understands:

- `plugin-pi-extension-<session-id>`;
- `plugin-oh-my-pi-extension-<session-id>`.

Keep tool identity in the lookup key. Do not merge solely on the raw suffix.

**Step 5: Preserve source precedence**

Plugin fields are primary. Process scan contributes only missing process/terminal fields. Add no Pi-specific presentation rules unless tests show the shared formatter is insufficient.

**Step 6: Verify the task**

Run: `swift test --filter AppModelTests`

Expected: PASS.

Run: `swift test --filter SessionDisplayFormatterTests`

Expected: PASS without regressions to existing tools.

**Suggested commit, only when commits are requested:** `feat(app): merge pi extension sessions with process fallback`

### Task 8: Package resources and document support

**Files:**
- Modify: `component-versions.json`
- Modify: `scripts/build/package-app.sh:40-65`
- Modify: `plugins/README.md`
- Create: `plugins/pi-vibebar-extension/README.md`
- Modify: `README.md`
- Modify: `README_zh.md`
- Modify: `README_ja.md`
- Modify: `README_ko.md`

**Step 1: Extend component version validation**

Add `piFamilyExtensionVersion` and validate it against `plugins/pi-vibebar-extension/package.json` in `package-app.sh`, matching the existing Claude/OpenCode checks. The existing whole-directory copy at `scripts/build/package-app.sh:41` will then include the extension.

**Step 2: Document installation behavior**

Document:

- Pi and OMP are separate VibeBar tools;
- direct `pi` and `omp` launches are supported;
- extension and process-scan detection methods;
- OMP installation covers the default profile and profiles existing at install time;
- users should run update after creating a new profile;
- Usage and interaction replies are not yet supported.

**Step 3: Verify package metadata and scripts**

Run: `node --check plugins/pi-vibebar-extension/runtime.js`

Run: `bash -n scripts/build/package-app.sh`

Expected: PASS.

Run the repository's normal local packaging command if signing prerequisites are available. Otherwise record that packaging was not executed and why.

**Suggested commit, only when commits are requested:** `docs: document pi and oh-my-pi integration`

### Task 9: Run regression and manual acceptance

**Files:**
- Verify only; modify implementation files only for failures attributable to this feature.

**Step 1: Run extension tests**

Run:

```bash
node --check plugins/pi-vibebar-extension/runtime.js
node --test plugins/pi-vibebar-extension/runtime.test.js
```

Expected: PASS.

**Step 2: Run focused Swift tests**

Run:

```bash
swift test --filter ToolKindTests
swift test --filter CLISettingsConfigurationTests
swift test --filter PiFamilyExtensionInstallerTests
swift test --filter PluginDetectorTests
swift test --filter AgentMessageTests
swift test --filter AgentEventReducerTests
swift test --filter AppModelTests
swift test --filter SessionDisplayFormatterTests
```

Expected: PASS.

**Step 3: Run full regression**

Run: `swift test`

Expected: PASS.

Run: `swift build`

Expected: PASS.

**Step 4: Perform manual Pi acceptance**

1. Install the Pi extension from VibeBar settings.
2. Start `vibebar-agent --verbose` and VibeBar.
3. Launch `pi` directly.
4. Submit a prompt and trigger at least one tool call.
5. Confirm idle -> running -> idle transitions, title, last user message, summary, cwd, and terminal navigation.
6. Disable plugin detection and confirm process-scan fallback still displays the session.

**Step 5: Perform manual OMP acceptance**

Repeat with:

```bash
omp
omp --profile <existing-profile>
```

Confirm both default and named-profile sessions report as Oh My Pi and do not appear as Pi.

**Step 6: Verify degradation paths**

- Stop `vibebar-agent` while Pi/OMP is running; host agents must remain unaffected.
- Uninstall each extension; unrelated extension files must remain.
- Create a new OMP profile, verify status becomes partial/actionable after refresh, run update, and verify the profile receives the extension.

**Suggested commit, only when commits are requested:** `test: cover pi and oh-my-pi integration`

## Completion Criteria

- Pi and OMP appear independently in settings, menu, notch, summaries, and notifications.
- Direct launches report realtime sessions when the managed extension is installed.
- Process scanning remains a functional fallback.
- Extension state and metadata win over process heuristics without duplicate cards.
- Pi default installation and OMP default/existing-profile installations are managed safely.
- All focused tests, full `swift test`, and `swift build` pass.
- No Usage or interaction-reply behavior is introduced.
