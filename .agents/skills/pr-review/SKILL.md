# PR Review Skill

This skill automates pull request review by analyzing code changes, checking for common issues, and providing structured feedback.

## Overview

The PR Review skill performs the following tasks:

1. **Diff Analysis** — Parses the PR diff to understand what changed
2. **Code Quality Checks** — Identifies potential bugs, style issues, and anti-patterns
3. **Test Coverage** — Verifies that new code paths are covered by tests
4. **Documentation Check** — Ensures public APIs and significant changes are documented
5. **Summary Generation** — Produces a structured review comment with findings

## Usage

This skill is triggered automatically on pull requests or can be invoked manually.

### Inputs

| Variable | Description | Required |
|---|---|---|
| `PR_NUMBER` | The pull request number to review | Yes |
| `REPO` | Repository in `owner/repo` format | Yes |
| `GITHUB_TOKEN` | GitHub token with PR read/write access | Yes |
| `OPENAI_API_KEY` | OpenAI API key for analysis | Yes |
| `REVIEW_LEVEL` | One of `light`, `standard`, `deep` (default: `standard`) | No |

### Outputs

- A structured review comment posted to the PR
- Exit code `0` on success, non-zero on failure

## Review Levels

### `light`
- Checks for syntax errors and obvious bugs
- Verifies no secrets or credentials are committed
- Flags missing tests for new functions

### `standard` (default)
- All `light` checks
- Code style and readability feedback
- Logic flow analysis
- Dependency change review

### `deep`
- All `standard` checks
- Security vulnerability scanning
- Performance implications
- Architecture and design pattern review
- Cross-file impact analysis

## Configuration

Place a `.pr-review.yaml` in the repository root to customize behavior:

```yaml
review_level: standard
ignore_paths:
  - "*.lock"
  - "dist/**"
  - "*.generated.*"
require_tests: true
require_docs: false
max_diff_lines: 2000
```

## Agent Configuration

See `agents/openai.yaml` for the agent model and settings used during review.
