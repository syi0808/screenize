# Contributing to Screenize

Thanks for considering a contribution! Whether it's a bug report, feature idea, or pull request — it all helps.

## Code of Conduct

Be respectful and constructive. We want this to be a welcoming space for everyone.

## Ways to Contribute

### Found a Bug?

1. Search [existing issues](../../issues) first — someone might have reported it already
2. If not, open a new issue with:
   - Steps to reproduce
   - What you expected vs. what happened
   - Your macOS and Xcode versions
   - Screenshots or screen recordings if they help

### Have an Idea?

1. Check [existing issues](../../issues) for similar suggestions
2. Open a new issue describing:
   - The problem or use case you're solving
   - Your proposed approach
   - Alternatives you considered

### Want to Submit Code?

1. Fork the repo
2. Create a branch from `main` (`git checkout -b feature/your-feature`)
3. Make your changes
4. Run the linter and make sure it builds
5. Push to your fork and open a pull request
6. Describe what changed and why in the PR

## Development Setup

```bash
git clone https://github.com/YOUR_USERNAME/screenize.git
cd screenize
open Screenize.xcodeproj
```

`Cmd+B` to build, `Cmd+R` to run.

**If permissions break during development:**

```bash
tccutil reset ScreenCapture com.screenize.Screenize
tccutil reset Microphone com.screenize.Screenize
```

## Style Guide

### Code

We use [SwiftLint](https://github.com/realm/SwiftLint). Run it before submitting:

```bash
./scripts/lint.sh          # Check
./scripts/lint.sh --fix    # Auto-fix
```

Key conventions:
- `@MainActor` on all major state classes
- `Manager` / `Coordinator` suffixes for orchestration classes
- `Sendable` types and dispatch queues for thread safety
- Normalized coordinates (0–1) for mouse positions
- Keyframes sorted by time within tracks

### Commits

- Imperative mood: "Add feature" not "Added feature"
- First line under 72 characters
- Reference issues when applicable: `Fix #123`

## Testing

There's no automated test suite yet. If you're adding new functionality, consider including tests — contributions that improve test coverage are especially welcome.
