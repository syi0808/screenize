# Implementation Plan Template

Use this template when generating implementation plans from GitHub issues.

```markdown
# Implementation Plan: [Issue Title]

**Issue**: #[number] - [title]
**Labels**: [labels]
**Created**: [date]
**Plan generated**: [date]

---

## Overview

[2-3 sentence summary of the issue and what needs to be accomplished]

## Problem Analysis

### Current Behavior
[What currently happens or what is missing]

### Desired Behavior
[What should happen after implementation]

### Acceptance Criteria
- [ ] [Criterion 1]
- [ ] [Criterion 2]
- [ ] [Criterion 3]

## Architecture Analysis

### Affected Modules
| Module | Role | Impact |
|--------|------|--------|
| [module] | [what it does] | [how it's affected] |

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

### Step 2: [Title]
...

## Files to Modify

| File | Action | Description |
|------|--------|-------------|
| `path/to/file.swift` | Modify | [What changes] |
| `path/to/new.swift` | Create | [What it contains] |

## Risk Assessment

### Potential Issues
- [Risk 1]: [Mitigation]
- [Risk 2]: [Mitigation]

### Edge Cases
- [Edge case 1]
- [Edge case 2]

### Breaking Changes
- [None / List of breaking changes]

## Testing Strategy

- [ ] [Build verification]
- [ ] [Manual test scenario 1]
- [ ] [Manual test scenario 2]

## Open Questions

- [Any ambiguities or decisions that need user input]
```
