# Contributing to Screenize

Thank you for your interest in contributing to Screenize. This guide explains how to report issues, suggest improvements, and submit code changes.

## Code of Conduct

Please be respectful and constructive in all interactions. We are committed to providing a welcoming and inclusive experience for everyone.

## How to Contribute

### Reporting Bugs

1. Search [existing issues](../../issues) to check if the bug has already been reported
2. If not, open a new issue with:
   - Steps to reproduce the bug
   - Expected behavior vs. actual behavior
   - Your environment (macOS version, Xcode version)
   - Screenshots or screen recordings if applicable

### Suggesting Enhancements

1. Search [existing issues](../../issues) for similar suggestions
2. Open a new issue describing:
   - The problem or use case
   - Your proposed solution
   - Alternatives you considered

### Pull Requests

1. Fork the repository
2. Create a feature branch from `main` (`git checkout -b feature/your-feature`)
3. Make your changes
4. Run the linter and ensure the project builds without errors
5. Write clear commit messages (see Style Guide below)
6. Push to your fork and open a pull request
7. Fill in the PR description explaining what changed and why

## Development Setup

```bash
git clone https://github.com/YOUR_USERNAME/screenize.git
cd screenize
open Screenize.xcodeproj
```

Build with Cmd+B in Xcode. Run with Cmd+R.

**Permissions:** Screenize requires Screen Recording, Microphone, and Accessibility permissions. If permissions break during development, reset them:

```bash
tccutil reset ScreenCapture com.screenize.Screenize
tccutil reset Microphone com.screenize.Screenize
```

## Style Guide

### Code Style

This project uses [SwiftLint](https://github.com/realm/SwiftLint) for linting. Run the linter before submitting:

```bash
./scripts/lint.sh
```

To auto-fix violations where possible:

```bash
./scripts/lint.sh --fix
```

Configuration is defined in `.swiftlint.yml`. Key conventions in this codebase:

- Use `@MainActor` on all major state classes
- Use `Manager` / `Coordinator` suffixes for orchestration classes
- Use `Sendable` types and dispatch queues for thread safety
- Use normalized coordinates (0–1 range) for mouse positions
- Keep keyframes sorted by time within tracks

### Commit Messages

- Use the imperative mood: "Add feature" not "Added feature"
- Keep the first line under 72 characters
- Reference issue numbers when applicable: `Fix #123`

## Testing

This project does not yet have an automated test suite. When adding new functionality, consider including tests. Contributions that improve test coverage are welcome.
