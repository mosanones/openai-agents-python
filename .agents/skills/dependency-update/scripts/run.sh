#!/usr/bin/env bash
# Dependency Update Skill
# Automatically checks for outdated dependencies and creates a PR with updates.

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../../.." && pwd)"
BRANCH_PREFIX="deps/auto-update"
DATE_TAG="$(date +%Y%m%d)"
UPDATE_BRANCH="${BRANCH_PREFIX}-${DATE_TAG}"
COMMIT_MSG="chore: auto-update dependencies (${DATE_TAG})"

# ─── Helpers ──────────────────────────────────────────────────────────────────
log()  { echo "[dependency-update] $*"; }
warn() { echo "[dependency-update] WARNING: $*" >&2; }
die()  { echo "[dependency-update] ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" &>/dev/null || die "Required command not found: $1"
}

# ─── Pre-flight checks ────────────────────────────────────────────────────────
require_cmd git
require_cmd python3
require_cmd pip

# Optional: gh CLI for PR creation
GH_AVAILABLE=false
if command -v gh &>/dev/null; then
  GH_AVAILABLE=true
fi

# ─── Move to repo root ────────────────────────────────────────────────────────
cd "${REPO_ROOT}"
log "Working directory: ${REPO_ROOT}"

# ─── Detect package manager ───────────────────────────────────────────────────
if [[ -f "pyproject.toml" ]]; then
  PKG_MANAGER="pyproject"
elif [[ -f "requirements.txt" ]]; then
  PKG_MANAGER="pip"
else
  die "No recognised package manifest found (pyproject.toml or requirements.txt)."
fi
log "Detected package manager style: ${PKG_MANAGER}"

# ─── Gather outdated packages ─────────────────────────────────────────────────
log "Checking for outdated packages…"
OUTDATED_JSON="$(pip list --outdated --format=json 2>/dev/null || echo '[]')"

if [[ "${OUTDATED_JSON}" == "[]" ]]; then
  log "All dependencies are up-to-date. Nothing to do."
  exit 0
fi

log "Outdated packages found:"
echo "${OUTDATED_JSON}" | python3 -c "
import json, sys
pkgs = json.load(sys.stdin)
for p in pkgs:
    print(f'  {p[\"name\"]}: {p[\"version\"]} -> {p[\"latest_version\"]}')
"

# ─── Create update branch ─────────────────────────────────────────────────────
CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
log "Current branch: ${CURRENT_BRANCH}"

# Abort if the update branch already exists remotely
if git ls-remote --exit-code origin "${UPDATE_BRANCH}" &>/dev/null; then
  warn "Branch '${UPDATE_BRANCH}' already exists on remote. Skipping."
  exit 0
fi

git checkout -b "${UPDATE_BRANCH}"
log "Created branch: ${UPDATE_BRANCH}"

# ─── Apply updates ────────────────────────────────────────────────────────────
if [[ "${PKG_MANAGER}" == "pyproject" ]]; then
  # Use pip-compile / uv if available, otherwise fall back to plain pip
  if command -v uv &>/dev/null; then
    log "Using uv to upgrade dependencies…"
    uv pip install --upgrade $(echo "${OUTDATED_JSON}" | python3 -c "
import json, sys
print(' '.join(p['name'] for p in json.load(sys.stdin)))
")
  else
    log "Using pip to upgrade dependencies…"
    pip install --upgrade $(echo "${OUTDATED_JSON}" | python3 -c "
import json, sys
print(' '.join(p['name'] for p in json.load(sys.stdin)))
")
  fi
else
  # requirements.txt workflow
  log "Upgrading packages listed in requirements.txt…"
  pip install --upgrade -r requirements.txt
  pip freeze > requirements.txt
  log "requirements.txt updated."
fi

# ─── Check for actual file changes ────────────────────────────────────────────
if git diff --quiet; then
  log "No file changes after upgrade. Branch will be cleaned up."
  git checkout "${CURRENT_BRANCH}"
  git branch -D "${UPDATE_BRANCH}"
  exit 0
fi

# ─── Commit changes ───────────────────────────────────────────────────────────
git add -A
git commit -m "${COMMIT_MSG}"
log "Committed dependency updates."

# ─── Push branch ──────────────────────────────────────────────────────────────
git push origin "${UPDATE_BRANCH}"
log "Pushed branch '${UPDATE_BRANCH}' to origin."

# ─── Open Pull Request (requires gh CLI) ──────────────────────────────────────
if [[ "${GH_AVAILABLE}" == "true" ]]; then
  PR_BODY="## Automated Dependency Update\n\nThis PR was created automatically by the **dependency-update** skill.\n\n### Updated packages\n\n"
  PR_BODY+="$(echo "${OUTDATED_JSON}" | python3 -c "
import json, sys
pkgs = json.load(sys.stdin)
rows = ['| Package | From | To |', '|---------|------|----|']
for p in pkgs:
    rows.append(f\"| {p['name']} | {p['version']} | {p['latest_version']} |\")
print('\\n'.join(rows))
")"

  gh pr create \
    --title "chore: auto-update dependencies (${DATE_TAG})" \
    --body "$(printf '%b' "${PR_BODY}")" \
    --base "${CURRENT_BRANCH}" \
    --head "${UPDATE_BRANCH}" \
    --label "dependencies"

  log "Pull request created successfully."
else
  warn "gh CLI not available — skipping PR creation."
  log "Push complete. Please open a PR manually for branch: ${UPDATE_BRANCH}"
fi

log "Done."
