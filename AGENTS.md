# AGENTS.md - VibeBar Development Guide

## Project Overview

VibeBar is a macOS menu bar status monitoring application that tracks TUI session states for Claude Code, Codex, and OpenCode CLI tools.

**Language**: Swift 6.2 | **Platform**: macOS 13+ | **Package Manager**: Swift Package Manager

**Project Structure**:
- `VibeBarCore` - Shared models, session storage, process scanning, aggregation logic
- `VibeBarApp` - Menu bar application with status item
- `VibeBarCLI` - PTY wrapper for transparent CLI interception
- `VibeBarAgent` - Local socket server for plugin events

---

## Build & Run Commands

```bash
# Build
swift build                    # Build all targets
swift build -c release         # Release build

# Run menu bar app
swift run VibeBarApp           # Launch menu bar app (blocking)
VIBEBAR_DEBUG_DOCK=1 swift run VibeBarApp  # Run with dock icon (debug)

# Run CLI wrappers
swift run vibebar claude       # Run CLI wrapper
swift run vibebar codex -- --model gpt-5-codex  # Pass through args

# Run agent
swift run vibebar-agent --verbose     # Start agent with verbose logging
swift run vibebar-agent --print-socket-path  # Print socket path

# Test (no test suite exists yet)
swift test                     # Run all tests
swift test --filter TestName   # Run specific test
```

---

## Code Style Guidelines

### General Conventions
- **Swift Version**: Swift 6.2 with strict concurrency
- **Minimum Deployment**: macOS 13.0
- **Thread Safety**: Mark all shared types as `Sendable`; use `@MainActor` for AppKit classes

### Naming
- **Types/Enums**: `PascalCase` (e.g., `ToolKind`, `SessionSnapshot`)
- **Properties/Variables**: `camelCase` (e.g., `sessionID`, `lastOutputAt`)
- **Files**: Match type name (e.g., `Models.swift`, `Aggregation.swift`)
- **Private enums for namespacing**: Use `private enum` for constants (e.g., `StatusColors`)

### Access Control
- `public` for library-exposed APIs in `VibeBarCore`
- `internal` (default) for internal implementation
- `private` for implementation details
- `fileprivate` for helpers within a single file

### Imports Order
System frameworks → Third-party → Internal modules:
```swift
import AppKit
import Combine
import Foundation
import VibeBarCore
```

### Types & Protocols
```swift
// Enums with raw values and protocols
public enum ToolKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claude-code"
    public var id: String { rawValue }
}

// Structs with explicit public init
public struct SessionSnapshot: Codable, Identifiable, Sendable {
    public var id: String
    public init(id: String) { self.id = id }
}

// Namespacing with private enum
private enum StatusColors {
    static func activity(_ state: ToolActivityState) -> NSColor { ... }
}
```

### Error Handling
- Use `do-catch` for recoverable errors
- Write errors to `stderr` using `fputs()` in CLI tools
- Return exit codes: 0=success, 1=error, 2=usage error, 3=environment error

```swift
do {
    try operation()
} catch {
    fputs("vibebar: error: \(error.localizedDescription)\n", stderr)
    return 1
}
```

### AppKit & SwiftUI Patterns
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
        .padding(12)
        .frame(width: 420)
    }
}
```

### Concurrency
- Use `async/await` where applicable
- Mark types `Sendable` for cross-actor safety
- Use `@MainActor` for UI updates
- Prefer `Task` over `DispatchQueue`
- Use `Timer.scheduledTimer` with `[weak self]` for periodic updates

### File Organization
Order: Imports → Enums → Structs → Classes → Extensions

### Comments
- Use Chinese comments for user-facing text
- Document public APIs with doc comments

---

## Project-Specific Patterns

### Session State Priority
`ToolOverallState`: running > awaitingInput > idle > stopped > unknown

### File Storage
- Session files: `~/Library/Application Support/VibeBar/sessions/*.json`
- Use atomic write: write to temp first, then move

```swift
let temp = destination.appendingPathExtension("tmp")
try data.write(to: temp, options: .atomic)
try FileManager.default.moveItem(at: temp, to: destination)
```

### State Detection (Wrapper)
- **Running**: Output activity within 0.8s
- **Awaiting Input**: Regex match on prompt patterns, latched until user input
- **Idle**: Process alive but no recent activity

---

## Common Tasks

### Adding a New Tool
1. Add case to `ToolKind` enum in `Models.swift`
2. Update `displayName`, `executable`, `fromCLIArgument()`, `detect()`
3. Add prompt detection patterns in `PromptDetector`

### Modifying Status Aggregation
1. Edit `SummaryBuilder` in `Aggregation.swift`
2. Update `resolveOverallState()` for new priority rules

---

## Known Limitations
- No automated tests
- No SwiftLint/SwiftFormat configuration
- "Awaiting input" and "completed" states have lower accuracy without PTY wrapper
- Prompt detection uses heuristic regex patterns
