# AGENTS.md - VibeBar Development Guide

**Swift 6.2 | macOS 13+ | Swift Package Manager**

**Targets**: `VibeBarCore` (library), `VibeBarApp` (menu bar), `VibeBarCLI` (`vibebar`), `VibeBarAgent` (socket server)

---

## Build & Run Commands

```bash
# Build
swift build
swift build -c release

# Run targets
swift run VibeBarApp                           # Menu bar app
VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp      # With dock icon (debug)

swift run vibebar claude                       # CLI wrapper
swift run vibebar codex -- --model gpt-5-codex # Pass args after --
swift run vibebar-agent --verbose              # Agent server

# Test (no test suite yet)
swift test
swift test --filter Pattern
```

---

## Code Style

### Conventions
- Swift 6.2 with strict concurrency checking
- macOS 13.0+ minimum deployment target
- Mark types `Sendable`; use `@MainActor` for AppKit/SwiftUI
- No SwiftLint or SwiftFormat configuration

### Naming
- Types/Enums: `PascalCase` (e.g., `ToolKind`, `SessionSnapshot`)
- Variables/functions: `camelCase` (e.g., `sessionID`, `displayName`)
- Files: Match primary type name (`Models.swift`, `Aggregation.swift`)

### Access Control
- `public` for VibeBarCore shared APIs
- `internal` (default) for target-internal code
- `private` / `fileprivate` for implementation details

### Import Order
```swift
import AppKit       // Framework imports first (alphabetical)
import Combine
import Darwin
import Foundation
import SwiftUI

import VibeBarCore  // Project imports last
```

### Types

**Enums**: Raw values, protocol conformance, computed properties
```swift
public enum ToolKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claude-code"
    public var id: String { rawValue }
    public var displayName: String { ... }
}
```

**Static Builders**:
```swift
public enum SummaryBuilder {
    public static func build(sessions: [SessionSnapshot]) -> GlobalSummary { ... }
}
```

**Structs**: required → optionals → dates → collections
```swift
public struct SessionSnapshot: Codable, Identifiable, Sendable {
    public var id: String
    public var pid: Int32
    public var parentPID: Int32?
    public var startedAt: Date
    public var command: [String]
    public init(...) { ... }
}
```

### Error Handling & CLI
- Use `do-catch` with `fputs` to `stderr` for CLI errors
- Use Chinese error messages for CLI output
- Exit codes: `0` success, `1` general error, `2` usage error, `3` unavailable
- Use `Never` return type for `exec` functions

```swift
do {
    try operation()
} catch {
    fputs("vibebar: 无法创建目录: \(error.localizedDescription)\n", stderr)
    return 1
}

private func execTool() -> Never {
    execvp(executable, ptr.baseAddress)
    _exit(127)
}
```

### AppKit & SwiftUI
```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController()
    }
}

struct MenuContentView: View {
    @ObservedObject var model: MonitorViewModel
    @ObservedObject private var l10n = L10n.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { ... }
            .padding(12)
            .frame(width: 420)
    }
}
```

### Concurrency
- Use `async/await` for async operations
- Mark concurrent-safe types as `Sendable`
- Use `@MainActor` for UI updates and AppKit classes

### File Organization
Order: Imports → Enums → Structs → Classes → Extensions

---

## Project Patterns

**State Priority**: `running` > `awaitingInput` > `idle` > `stopped` > `unknown`

**Storage**:
- Sessions: `~/Library/Application Support/VibeBar/sessions/*.json`
- Agent socket: `~/Library/Application Support/VibeBar/runtime/agent.sock`
- Atomic writes: temp file first, then `FileManager.replaceItemAt`

**Agent Events (NDJSON)**:
```json
{"source":"claude-plugin","tool":"claude-code","session_id":"xxx","event_type":"session_started"}
```

**Localization**: Use `L10n.shared.string(.key)` for UI strings

---

## Common Tasks

**Add New Tool**:
1. Add case to `ToolKind` in `Models.swift`
2. Update `displayName`, `executable`, `fromCLIArgument()`, `detect()`
3. Add regex patterns in `PromptDetector`

**Modify Aggregation**:
1. Edit `SummaryBuilder` in `Aggregation.swift`
2. Update `resolveOverallState()` priority logic

---

## Limitations
- No automated test suite
- No SwiftLint/SwiftFormat
- "Awaiting input" detection uses regex heuristics
