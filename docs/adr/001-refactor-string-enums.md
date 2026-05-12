# ADR-001: Refactor String State to Swift Enums

**Date:** 2026-05-11  
**Status:** Implemented  
**Context:** All task/sub-task state is stored as `String` literals (`"active"`, `"completed"`, `"discovery"`, etc.). This means typos compile fine and switch statements can never be exhaustive.

## Decision
Replace all string state with Swift enums:
- `TodoTask.status` → `TaskStatus` (`.active`, `.completed`, `.archived`)
- `TodoTask.phase` → `TaskPhase` (`.discovery`, `.execution`)
- `TodoTask.planningStatus` → `PlanningStatus` (`.idle`, `.planningDiscovery`, `.planningExecution`)
- `SubTask.status` → `SubTaskStatus` (`.pending`, `.current`, `.completed`, `.skipped`)
- `SubTask.phase` → `TaskPhase` (reuse)

SwiftData requires stored properties to be compatible with its persistence model. Swift enums with raw `String` values work fine with SwiftData — they're stored as the underlying string.

## Consequences
- **Positive:** Compile-time safety, exhaustive switches, self-documenting code
- **Negative:** Migration of existing SwiftData objects (strings already stored will map correctly via raw value)
- **Risk:** Low — SwiftData handles `String`-backed enums transparently
