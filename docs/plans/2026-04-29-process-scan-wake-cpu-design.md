# Process Scan Wake CPU Design

## Problem

After macOS wakes from sleep, VibeBar can show high CPU usage and many short-lived `ps` processes. The current refresh path runs a full `/bin/ps -axo ...` for every detection context, while terminal context enrichment can run `/bin/ps eww -p <pid> ...` per candidate process. Runtime caches expire during sleep, so wake often starts from a cold cache. App polling, menu resume refreshes, and agent events can also request process snapshots at the same time.

## Goals

- Prevent concurrent or back-to-back process snapshots from spawning many duplicate `ps` commands.
- Avoid stuck `ps` or `lsof` child processes after wake or under load.
- Debounce refresh after system wake without changing session merge semantics.
- Keep changes minimal and low-risk.

## Design

Add a short-lived thread-safe cache and single-flight guard around `DetectorSupport.makeContext()`. Calls within a small TTL, initially 1 second, reuse the same process snapshot. Calls while a snapshot is already loading wait for the same load instead of launching another `/bin/ps`.

Wrap external process execution used by `DetectorSupport` with a timeout helper. `ps` and `lsof` calls should return empty results when they exceed the timeout instead of waiting indefinitely. This bounds child process lifetime and prevents refresh tasks from piling up behind slow external commands.

Add wake handling in `MonitorViewModel`. Observe `NSWorkspace.didWakeNotification`, cancel any pending wake refresh task, then schedule one delayed refresh after a short debounce. This lets macOS settle and prevents immediate repeated refreshes from the regular timer and manual resume path.

## Non-Goals

- Do not change detection method defaults or session merge behavior.
- Do not lower the active polling interval in this change.
- Do not refactor process detection to a new OS API.
- Do not change usage analytics refresh behavior in this minimal fix.

## Verification

- Build with `swift build`.
- Run existing tests with `swift test` if practical.
- Manually verify that repeated concurrent refreshes no longer create multiple full `ps -axo` processes.
- Manually verify wake path schedules a delayed refresh rather than an immediate burst.
