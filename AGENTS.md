# AGENTS.md
Guidance for autonomous coding agents working in this repository.

## Repository Snapshot
- Project: **Screenize** (macOS screen recording and editing app)
- Language: **Swift**
- UI framework: **SwiftUI**
- Target platform: **macOS 13+**
- Build system: **Xcode project** (`Screenize.xcodeproj`)
- External dependency: **Sparkle** (via Swift Package Manager)

## Mandatory Agent Workflow
Follow this sequence for each meaningful work unit:
1. **START**: run the `work-context-finder` agent to check prior related work.
2. **WORK**: implement the task.
3. **FINISH**: execute `/log-work` using the `work-logger` skill.

Notes:
- This workflow is defined in `CLAUDE.md` and should be treated as repository policy.
- All generated logs/summaries/tags for vector DB workflows must be in English.

## Build, Lint, and Test Commands
Run all commands from repository root (`/Users/sung-yein/Workspace/screenize`).

### Build
```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -configuration Debug build
```

### Lint
```bash
./scripts/lint.sh
```
Auto-fix lint violations where possible:
```bash
./scripts/lint.sh --fix
```

### Smart Generation Quality Report (Direction 1)
Generate benchmark quality metrics and gate checks:
```bash
./scripts/smart-generation-quality-report.sh
```
Enforce gates (blocking mode):
```bash
./scripts/smart-generation-quality-report.sh --enforce-gates
```

### Tests (Current Status + How To Run)
Current repository status:
- There is currently **no test target** configured in `Screenize.xcodeproj`.
- There are currently **no `*Tests*` files/directories** in the repo.
- Primary verification today is **successful build + lint**.

When tests are added, use these command patterns:

Run all tests for a scheme:
```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' test
```

Run a single test class:
```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/MyFeatureTests test
```

Run a single test method:
```bash
xcodebuild -project Screenize.xcodeproj -scheme Screenize -destination 'platform=macOS' -only-testing:ScreenizeTests/MyFeatureTests/testExample test
```

Tip: if scheme/target names differ, inspect with:
```bash
xcodebuild -list -project Screenize.xcodeproj
```

### Permission Reset Helpers (Local Dev)
If screen/microphone permission state is broken:
```bash
tccutil reset ScreenCapture com.screenize.Screenize
tccutil reset Microphone com.screenize.Screenize
```

## Code Style and Conventions

### Language and Documentation
- Write **all code, comments, commit messages, and docs in English**.
- Keep comments focused on non-obvious intent or constraints.

### Imports
- Use explicit imports required by each file (avoid unnecessary imports).
- Keep import blocks clean and grouped at the file top.
- Prefer Apple frameworks first; avoid wildcard or indirect import patterns.

### Formatting and Lint Rules
This repo uses SwiftLint (`.swiftlint.yml`) with key limits:
- `line_length`: warning 140, error 200
- `file_length`: warning 600, error 1000
- `function_body_length`: warning 80, error 150
- `type_body_length`: warning 400, error 600
- `function_parameter_count`: warning 8, error 12
- `nesting`: type level 2, function level 5
- `force_cast`: warning only (required in some AXValue APIs)
- `force_try`: error

General formatting expectations:
- Use clear `// MARK:` sectioning in larger files.
- Keep methods small and focused.
- Respect existing spacing and brace style already used in nearby code.

### Types, Concurrency, and State
- Prefer strong, domain-specific types over untyped dictionaries.
- Use `@MainActor` for major app/state classes and UI-facing state.
- Use `Sendable` and safe queue/concurrency boundaries where relevant.
- Use async/await patterns consistently with existing code.
- Keep singleton usage aligned with existing architecture (`AppState.shared`, `ProjectManager.shared`).

### Naming Conventions
- Use descriptive Swift names in standard Apple style.
- Use `Manager` / `Coordinator` suffixes for orchestration components.
- Keep keyframe/timeline terms consistent with domain model naming.
- Use imperative, behavior-first function names for actions.

### Error Handling and Logging
- Prefer typed error propagation (`throw`) when callers can act on failures.
- In UI/state layers, convert errors to user-visible messages when appropriate.
- Avoid silent failure unless intentionally best-effort.
- Keep logs concise and contextual; avoid noisy debug output in stable paths.

### Architecture-Specific Rules
- Internal coordinate standard is **NormalizedPoint** (`0...1`, bottom-left origin).
- Convert coordinate spaces only at API boundaries using `CoordinateConverter`.
- Keep timeline keyframes sorted by time within tracks.
- Preserve three-phase flow: recording -> editor -> export.

### File and Project System Expectations
- Project package format is `.screenize` with `project.json` and `recording/` media.
- Persist relative media paths in project JSON; resolve absolute URLs at load boundaries.

## Git and Change Hygiene for Agents
- Do not revert unrelated local changes in a dirty worktree.
- Keep edits scoped to the requested task.
- Prefer small, reviewable diffs.
- Use imperative commit messages when committing (if requested).

## Cursor / Copilot Rule Files
Checked paths:
- `.cursor/rules/`
- `.cursorrules`
- `.github/copilot-instructions.md`

Current status:
- No Cursor rules or Copilot instruction files were found in this repository.

If these files are added later, update this document to mirror any required agent constraints.
