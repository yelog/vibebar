# AGENTS.md - VibeBar Development Guide

**Swift 6.2 | macOS 13+ | Swift Package Manager**

**Structure**: `VibeBarCore` (shared models), `VibeBarApp` (menu bar), `VibeBarCLI` (PTY wrapper), `VibeBarAgent` (socket server)

---

## Build & Run Commands

```bash
# Build
swift build && swift build -c release

# Run
swift run VibeBarApp                           # Menu bar app
VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp      # With dock icon

swift run vibebar claude                       # CLI wrapper
swift run vibebar codex -- --model gpt-5-codex # Pass through args

swift run vibebar-agent --verbose              # Agent server

# Test (no test suite yet)
swift test
swift test --filter TestName
```

---

## Code Style

### Conventions
- Swift 6.2 with strict concurrency
- macOS 13.0 minimum
- Mark types `Sendable`; use `@MainActor` for AppKit
- No SwiftLint/SwiftFormat

### Naming
- Types/Enums: `PascalCase` (e.g., `ToolKind`)
- Variables: `camelCase` (e.g., `sessionID`)
- Files: Match type name (`Models.swift`)

### Access Control
- `public` for VibeBarCore APIs
- `internal` (default)
- `private` / `fileprivate` for details

### Imports Order
```swift
import AppKit
import Darwin
import Foundation
import VibeBarCore
```

### Types & Error Handling
```swift
// Enums: raw values, protocols, computed properties
public enum ToolKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claude-code"
    public var id: String { rawValue }
    public var displayName: String { ... }
}

// Static builders in enums
public enum SummaryBuilder {
    public static func build(sessions: [SessionSnapshot], now: Date = Date()) -> GlobalSummary { ... }
}

// Structs: required → optionals → dates → collections
public struct SessionSnapshot: Codable, Identifiable, Sendable {
    public var id: String
    public var tool: ToolKind
    public var pid: Int32
    public var parentPID: Int32?
    public var status: ToolActivityState
    public var source: SessionSource
    public var startedAt: Date
    public var updatedAt: Date
    public var lastOutputAt: Date?
    public var command: [String]
    public init(...) { ... }
}

// Error handling: do-catch, fputs to stderr, exit codes 0/1/2/3
// Chinese error messages for CLI output
// Use Never return for exec functions
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

### CLI Patterns
```swift
private struct CLIConfig { let tool: ToolKind; let passthrough: [String] }
private func parseCLI(arguments: [String]) -> CLIConfig? {
    guard arguments.count >= 2,
          let tool = ToolKind.fromCLIArgument(arguments[1]) else { return nil }
    var rest = Array(arguments.dropFirst(2))
    if rest.first == "--" { rest.removeFirst() }
    return CLIConfig(tool: tool, passthrough: rest)
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
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { ... }
            .padding(12).frame(width: 420)
    }
}
```

### Concurrency & File Organization
- Use `async/await`, mark `Sendable`, use `@MainActor` for UI
- Order: Imports → Enums → Structs → Classes → Extensions

---

## Project Patterns

**Session Priority**: running > awaitingInput > idle > stopped > unknown

**Storage**:
- Sessions: `~/Library/Application Support/VibeBar/sessions/*.json`
- Agent socket: `~/Library/Application Support/VibeBar/runtime/agent.sock`
- Atomic write: temp file first, then move

**Agent Events (NDJSON)**:
```json
{"source":"claude-plugin","tool":"claude-code","session_id":"xxx","event_type":"session_started"}
```

---

## Common Tasks

**Add New Tool**: 1) Add case to `ToolKind` in `Models.swift`, 2) Update `displayName/executable/fromCLIArgument/detect()`, 3) Add prompt patterns in `PromptDetector`

**Modify Aggregation**: Edit `SummaryBuilder` in `Aggregation.swift`, update `resolveOverallState()`

---

## Limitations
- No automated tests
- No SwiftLint/SwiftFormat
- "Awaiting input" detection uses heuristics
