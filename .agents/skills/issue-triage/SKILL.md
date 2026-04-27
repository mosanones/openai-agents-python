# Issue Triage Skill

Automatically triages new GitHub issues by analyzing their content, applying appropriate labels, assigning priority, and routing to the correct team members.

## What This Skill Does

1. **Analyzes issue content** — Reads the issue title, body, and any attached code/logs
2. **Applies labels** — Assigns relevant labels (bug, enhancement, documentation, question, etc.)
3. **Sets priority** — Determines priority level (P0-critical, P1-high, P2-medium, P3-low) based on impact and urgency signals
4. **Checks for duplicates** — Searches existing issues for potential duplicates and links them
5. **Requests missing info** — Comments on issues that are missing reproduction steps, environment info, or other required details
6. **Assigns reviewers** — Routes to appropriate maintainers based on affected area (core, docs, examples, CI)
7. **Adds to project board** — Optionally adds the issue to the relevant GitHub project milestone

## Trigger

This skill runs automatically when:
- A new issue is opened
- An issue is edited (re-triages if labels are missing)
- Manually triggered via workflow dispatch

## Configuration

The skill reads from `.agents/skills/issue-triage/config.yaml` for:
- Label taxonomy
- Team routing rules
- Required fields per issue template
- Duplicate detection threshold

## Inputs

| Variable | Description |
|---|---|
| `GITHUB_TOKEN` | Token with issues read/write permissions |
| `ISSUE_NUMBER` | The issue number to triage |
| `REPO` | Repository in `owner/repo` format |
| `OPENAI_API_KEY` | Used for semantic analysis of issue content |

## Outputs

- Labels applied to the issue
- A triage comment posted on the issue (if action required)
- Duplicate links added as issue references
- Console summary of actions taken

## Label Taxonomy

### Type
- `bug` — Something isn't working
- `enhancement` — New feature or improvement request
- `documentation` — Docs improvement or correction
- `question` — General question or support request
- `chore` — Maintenance, refactoring, or tooling

### Priority
- `P0-critical` — Production outage or data loss
- `P1-high` — Major feature broken, no workaround
- `P2-medium` — Feature degraded, workaround available
- `P3-low` — Minor issue or cosmetic

### Area
- `area/core` — Core agent runtime
- `area/tools` — Tool integrations
- `area/tracing` — Tracing and observability
- `area/docs` — Documentation
- `area/examples` — Example scripts
- `area/ci` — CI/CD infrastructure

## Example Output

```
[issue-triage] Analyzing issue #142: "Agent loop hangs when tool returns None"
[issue-triage] Detected type: bug
[issue-triage] Detected area: area/core
[issue-triage] Assigned priority: P1-high (keyword: "hangs", no workaround mentioned)
[issue-triage] No duplicate found above threshold 0.85
[issue-triage] Missing: reproduction steps — posting comment
[issue-triage] Labels applied: bug, P1-high, area/core, needs-repro
[issue-triage] Done.
```
