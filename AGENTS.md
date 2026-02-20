# AGENTS.md - VibeBar Development Guide

## Project Overview

VibeBar is a macOS menu bar status monitoring application that tracks TUI session states for Claude Code, Codex, and OpenCode CLI tools.

**Language**: Swift 6.2 | **Platform**: macOS 13+ | **Package Manager**: Swift Package Manager

**Project Structure**:
- `VibeBarCore` - Shared models, session storage, process scanning, aggregation logic
- `VibeBarApp` - Menu bar application with status item
- `VibeBarCLI` - PTY wrapper for transparent CLI interception

---

## Build & Run Commands

```bash
# Build
swift build                    # Build all targets
swift build -c release         # Release build

# Run
swift run VibeBarApp           # Launch menu bar app (blocking)
swift run vibebar claude       # Run CLI wrapper
swift run vibebar codex -- --model gpt-5-codex  # Pass through args

# Test (no test suite exists yet)
swift test
```

---

## Code Style Guidelines

### General Conventions

1. **Swift Version**: Use Swift 6.2 features including strict concurrency
2. **Minimum Deployment**: macOS 13.0
3. **Thread Safety**: Mark all shared types as `Sendable`; use `@MainActor` for AppKit classes

### Naming

- **Types/Enums**: `PascalCase` (e.g., `ToolKind`, `SessionSnapshot`)
- **Properties/Variables**: `camelCase` (e.g., `sessionID`, `lastOutputAt`)
- **Files**: Match type name (e.g., `Models.swift`, `Aggregation.swift`)

### Access Control

- Use `public` for library-exposed APIs in `VibeBarCore`
- Use `internal` (default) for internal implementation
- Use `private` for implementation details

### Imports

Order: System frameworks → Third-party → Internal modules
```swift
import Foundation              // Core utilities
import AppKit                 // macOS UI
import Darwin                 // C interop (termios, signal)
import VibeBarCore           // Internal shared module
```

### Types & Protocols

```swift
public enum ToolKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claude-code"
}

public struct SessionSnapshot: Codable, Identifiable, Sendable {
    public var id: String
    public init(id: String, /* ... */) { /* ... */ }
}
```

### Error Handling

- Use `do-catch` for recoverable errors
- Write errors to `stderr` using `fputs()` in CLI tools
- Return exit codes: 0=success, 1=error, 2=usage error

```swift
do {
    try operation()
} catch {
    fputs("vibebar: error: \(error.localizedDescription)\n", stderr)
    return 1
}
```

### AppKit Patterns

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusController: StatusItemController?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusItemController()
    }
}
```

### Concurrency

- Use `async/await` where applicable
- Mark types `Sendable` for cross-actor safety
- Use `@MainActor` for UI updates
- Prefer actors or `Task` over `DispatchQueue`

### File Organization

Each file should focus on a single concern. Order: Imports → Enums → Structs → Classes → Extensions

### Comments

- Use Chinese comments (project uses Chinese for user-facing text)
- Document public APIs with doc comments

```swift
/// 从命令行参数推断工具类型
public static func fromCLIArgument(_ value: String) -> ToolKind? { ... }
```

---

## Project-Specific Patterns

### Session State Priority

`ToolOverallState`: running > awaitingInput > completed > idle > stopped

### File Storage

- Session files: `~/Library/Application Support/VibeBar/sessions/*.json`
- Use `VibeBarPaths.ensureDirectories()` before file operations

### PTY Wrapper (VibeBarCLI)

- Uses `forkpty()` for terminal emulation
- Writes state snapshots every 0.5s
- Handles `SIGWINCH` for window size forwarding

---

## Common Tasks

### Adding a New Tool

1. Add case to `ToolKind` enum in `Models.swift`
2. Update `displayName`, `executable`, `fromCLIArgument()`, `detect()`
3. Add prompt detection pattern in `PromptDetector` (CLI)

### Modifying Status Aggregation

1. Edit `SummaryBuilder` in `Aggregation.swift`
2. Update `resolveOverallState()` for new priority rules

---

## Known Limitations

- No automated tests
- No SwiftLint/SwiftFormat configuration
- "Awaiting input" and "completed" states have lower accuracy without PTY wrapper
- Prompt detection uses heuristic regex patterns
