# Project Memory

## Build Workflow (CRITICAL)

After creating new Swift files or modifying existing ones:

1. **Regenerate Xcode project:** `xcodegen generate` (spec at `/Users/alexisrondeau/Workshop/tada/project.yml`)
   - Schemes are auto-generated from `project.yml` — NEVER edit `.xcscheme` files manually
   - If you add a new target, add it to `project.yml` targets section and regenerate
2. **Run tests:** `./scripts/test`
   - Runs both unit tests (TadaTests) and integration tests (TadaIntegrationTests)
3. **Clean build with xcodebuild:** `xcodebuild clean build -project Tada.xcodeproj -scheme Tada -destination 'platform=macOS'`
   - `swift build` is NOT sufficient — it auto-discovers `.swift` files via Package.swift but Xcode needs explicit project membership
4. **If build succeeds:** Relaunch the app with `open -a Tada` to confirm it runs

## Behavioral Guidelines (from CLAUDE.md)

- **Think before coding** — state assumptions, push back when warranted
- **Simplicity first** — minimum code that solves the problem. If 200 lines could be 50, rewrite it
- **Surgical changes** — touch only what you must. Don't refactor things that aren't broken
- **Goal-driven execution** — define success criteria, loop until verified

## Anti-Patterns to Avoid

- **Planning loops** — Don't keep re-planning the same steps. One plan, then execute.
- **Scope creep** — Don't add new concerns mid-task. Commit to one change at a time.
- **No verification** — Always verify with actual compilation, not just reasoning
