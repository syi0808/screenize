# /// script
# requires-python = ">=3.10"
# ///
"""Create an implementation plan markdown file from a GitHub issue."""

import argparse
import re
import sys
from datetime import datetime
from pathlib import Path


def slugify(text: str) -> str:
    """Convert text to URL-friendly slug."""
    text = text.lower().strip()
    text = re.sub(r"[^\w\s-]", "", text)
    text = re.sub(r"[\s_]+", "-", text)
    text = re.sub(r"-+", "-", text)
    return text[:60].rstrip("-")


def main():
    parser = argparse.ArgumentParser(description="Create implementation plan file")
    parser.add_argument("--issue", "-i", required=True, help="Issue number")
    parser.add_argument("--title", "-t", required=True, help="Issue title for slug")
    args = parser.parse_args()

    slug = slugify(args.title)
    filename = f"{args.issue}-{slug}.md"

    plans_dir = Path("private-docs/plans")
    plans_dir.mkdir(parents=True, exist_ok=True)

    filepath = plans_dir / filename

    if filepath.exists():
        print(f"Plan file already exists: {filepath}", file=sys.stderr)
        print(f"Path: {filepath}")
        sys.exit(0)

    today = datetime.now().strftime("%Y-%m-%d")

    template = f"""# Implementation Plan: [TITLE]

**Issue**: #{args.issue}
**Labels**: [labels]
**Created**: [issue date]
**Plan generated**: {today}

---

## Overview

[2-3 sentence summary]

## Problem Analysis

### Current Behavior
[What currently happens or what is missing]

### Desired Behavior
[What should happen after implementation]

### Acceptance Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]

## Architecture Analysis

### Affected Modules
| Module | Role | Impact |
|--------|------|--------|
| | | |

### Integration Points
[How the change connects to existing systems]

### Design Decisions
[Key architectural choices and rationale]

## Implementation Steps

### Step 1: [Title]
**Files**: `path/to/file.swift`
**Description**: [What to do and why]
**Details**:
- [Specific change 1]
- [Specific change 2]

## Files to Modify

| File | Action | Description |
|------|--------|-------------|
| | | |

## Risk Assessment

### Potential Issues
- [Risk]: [Mitigation]

### Edge Cases
- [Edge case]

### Breaking Changes
- None

## Testing Strategy

- [ ] Build verification
- [ ] [Manual test scenario]

## Open Questions

- [Any ambiguities]
"""

    filepath.write_text(template, encoding="utf-8")
    print(f"Path: {filepath}")


if __name__ == "__main__":
    main()
