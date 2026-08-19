# Pi Family Extension Import Path Fix Design

**Date:** 2026-08-19

## Goal

Restore Pi and Oh My Pi extension loading after VibeBar installs each selected adapter and the shared runtime into one managed directory.

## Root Cause

The source adapters live in child directories and import `../runtime.js`. The installer flattens the selected adapter and `runtime.js` into `<extensions>/vibebar/`, where that relative import resolves outside the managed directory and fails.

## Design

- Change both Pi-family adapter imports to `./runtime.js`.
- Keep the installer layout unchanged: it atomically installs `index.ts`, `runtime.js`, and the managed marker in one directory.
- Add installer assertions that installed adapters refer to the colocated runtime.
- Do not add transcript parsing or UI-level naming fallbacks. Once the extension loads, existing event metadata supplies the title and user prompt.

## Validation

- Run the extension's Node test suite.
- Run the focused `PiFamilyExtensionInstallerTests` suite.
- Run the full Swift test suite if the focused tests pass.
