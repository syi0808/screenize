---
name: github-planner
description: Fetch a GitHub issue and create a detailed implementation plan. Use when given a GitHub issue URL or number to analyze the issue, explore relevant codebase areas, and produce a step-by-step implementation plan with file changes, architecture considerations, and risk assessment.
user_invocable: true
---

# GITHUB ISSUE IMPLEMENTATION PLANNER

<objective>

Fetch a GitHub issue, analyze its requirements, explore the relevant codebase, and produce a comprehensive implementation plan.

**When to use**: Execute `/plan-issue` with a GitHub issue URL or number to generate an implementation plan before starting work.

</objective>

<workflow>

## Step 1: Fetch Issue

Run the fetch script to retrieve issue details:

```bash
uv run .claude/skills/github-planner/scripts/fetch_issue.py <issue_url_or_number>
```

Accepts:
- Full URL: `https://github.com/owner/repo/issues/123`
- Short URL: `owner/repo#123`
- Issue number (uses current repo): `123` or `#123`

The script outputs structured JSON with title, body, labels, comments, and metadata.

## Step 2: Analyze Issue

Parse the fetched issue content and identify:

1. **Problem statement** - What needs to be solved
2. **Proposed solution** - If described in the issue
3. **Acceptance criteria** - Explicit or inferred requirements
4. **Scope boundaries** - What is and isn't included

## Step 3: Explore Codebase

Based on the analysis, explore relevant parts of the codebase:

1. Use Glob/Grep to find files related to the issue's domain
2. Read key files to understand current architecture
3. Identify integration points and dependencies
4. Check for existing patterns that the implementation should follow
5. Reference `CLAUDE.md` for project architecture and conventions

## Step 4: Generate Implementation Plan

Write the plan to `private-docs/plans/<issue-number>-<slug>.md` using the template:

```bash
uv run .claude/skills/github-planner/scripts/create_plan.py \
  --issue <number> \
  --title "<issue-title-slug>"
```

Fill the generated template with:

- **Overview**: Issue summary and goals
- **Architecture Analysis**: How changes fit into existing architecture
- **Implementation Steps**: Ordered tasks with specific file changes
- **Files to Modify/Create**: Exhaustive list with descriptions
- **Risk Assessment**: Potential issues, edge cases, breaking changes
- **Testing Strategy**: How to verify the implementation

## Step 5: Present Plan

After writing the plan file, present a concise summary to the user:

1. Key architectural decisions
2. Number of files affected
3. Implementation order
4. Any open questions or ambiguities from the issue

</workflow>

<standards>

- **Language**: All plans MUST be written in English (per CLAUDE.md)
- **Specificity**: Reference exact file paths and function names
- **Actionable**: Each step should be independently implementable
- **Architecture-aware**: Respect existing patterns from CLAUDE.md
- **Scope-bounded**: Do not plan beyond what the issue requests

</standards>

<references>

- [Plan template](references/plan-template.md) - Markdown template for implementation plans

</references>
