# Pi Family Extension Import Path Fix Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Ensure installed Pi and Oh My Pi VibeBar extensions import their colocated shared runtime and therefore report session titles.

**Architecture:** The installer deliberately flattens one product adapter and `runtime.js` into the managed `vibebar` directory. Both adapters must therefore import `./runtime.js`; an installer test verifies the installed entry has this import for Pi and OMP targets.

**Tech Stack:** Swift 6.2, Swift Testing, Node.js test runner.

---

### Task 1: Cover the Flattened Adapter Layout

**Files:**
- Modify: `Tests/VibeBarCoreTests/PiFamilyExtensionInstallerTests.swift`

**Step 1: Write the failing test**

Add a test that installs `.pi` and `.ohMyPi` into isolated fixture homes, then reads each generated `vibebar/index.ts` and expects:

```swift
#expect(contents.contains("from \"./runtime.js\""))
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter PiFamilyExtensionInstallerTests`

Expected: failure because both source adapters use `../runtime.js`.

**Step 3: Keep the test focused**

Assert the existing managed directory still includes both `index.ts` and `runtime.js`, and test both product adapter selections rather than testing a synthetic copy layout.

**Step 4: Re-run the focused suite**

Run: `swift test --filter PiFamilyExtensionInstallerTests`

Expected: the new test remains the only expected failure until Task 2.

### Task 2: Correct Both Entry Imports

**Files:**
- Modify: `plugins/pi-vibebar-extension/pi/index.ts:1`
- Modify: `plugins/pi-vibebar-extension/omp/index.ts:1`

**Step 1: Apply the minimal implementation**

Replace the parent-directory import in both adapters:

```ts
import { createVibeBarExtension } from "./runtime.js";
```

No installer code changes are required because it already installs both files adjacent to one another.

**Step 2: Run the installer suite**

Run: `swift test --filter PiFamilyExtensionInstallerTests`

Expected: PASS.

**Step 3: Check JavaScript syntax and runtime behavior**

Run: `node --check plugins/pi-vibebar-extension/runtime.js`

Expected: exit code 0.

Run: `node --test plugins/pi-vibebar-extension/runtime.test.js`

Expected: all tests pass.

### Task 3: Run Regression Verification

**Files:**
- Verify only: all modified files

**Step 1: Run the Swift suite**

Run: `swift test`

Expected: PASS.

**Step 2: Inspect the final diff**

Run: `git diff -- plugins/pi-vibebar-extension/pi/index.ts plugins/pi-vibebar-extension/omp/index.ts Tests/VibeBarCoreTests/PiFamilyExtensionInstallerTests.swift docs/plans/2026-08-19-pi-family-extension-import-path-design.md docs/plans/2026-08-19-pi-family-extension-import-path-implementation.md`

Expected: only the adjacent-runtime imports, the regression test, and planning documents are changed.

**Step 3: Commit**

Only if requested by the user:

```bash
git add plugins/pi-vibebar-extension/pi/index.ts plugins/pi-vibebar-extension/omp/index.ts Tests/VibeBarCoreTests/PiFamilyExtensionInstallerTests.swift docs/plans/2026-08-19-pi-family-extension-import-path-design.md docs/plans/2026-08-19-pi-family-extension-import-path-implementation.md
git commit -m "fix(plugins): load pi extensions from managed directory"
```
