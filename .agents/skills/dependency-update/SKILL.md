# Dependency Update Skill

This skill automates the process of checking for outdated dependencies, evaluating compatibility, and generating pull requests with safe dependency updates.

## Overview

The dependency update skill helps maintain project health by:
- Scanning `pyproject.toml`, `requirements*.txt`, and other dependency files
- Identifying outdated packages using PyPI API
- Checking changelogs and release notes for breaking changes
- Running the test suite to verify compatibility
- Creating a structured PR with update details

## Trigger

This skill can be triggered:
- On a schedule (e.g., weekly)
- Manually via workflow dispatch
- When a security advisory is published for a dependency

## Steps

1. **Scan** — Identify all dependency files in the repository
2. **Check** — Query PyPI for latest versions of each package
3. **Evaluate** — Determine which updates are safe (patch/minor) vs risky (major)
4. **Test** — Install updated dependencies and run `pytest` to verify nothing breaks
5. **Report** — Generate a summary of changes with links to changelogs
6. **PR** — Open a pull request with the updates grouped by risk level

## Configuration

The skill reads configuration from `.agents/skills/dependency-update/config.yaml` if present.

```yaml
# Example config
update_strategy: conservative  # conservative | aggressive
group_updates: true             # Group all updates into one PR
exclude_packages:               # Packages to skip
  - some-pinned-package
major_updates: false            # Whether to include major version bumps
```

## Output

The skill produces:
- A PR (or commit) with updated dependency files
- A comment on the PR summarizing what changed and why it is safe
- A JSON artifact at `.agents/artifacts/dependency-update-report.json` with full details

## Safety Guardrails

- Never updates a package if tests fail after the update
- Never bumps a major version unless `major_updates: true` is set
- Always pins to an exact version that was tested, not a range
- Skips packages listed in `exclude_packages`
- Leaves a clear audit trail in the PR description

## Agent Instructions

When running this skill:
1. Start by reading all dependency files to build a complete picture
2. Use the PyPI JSON API (`https://pypi.org/pypi/{package}/json`) to fetch latest versions
3. Compare current vs latest, categorize by semver bump type
4. For each candidate update, check if a CHANGELOG or GitHub releases page exists
5. Run tests after applying updates — do NOT open a PR if tests fail
6. Write a clear PR body using the template in `references/pr-template.md`
