#!/usr/bin/env bash
# Issue Triage Skill - Automatically triages GitHub issues by analyzing content,
# applying labels, assigning priority, and routing to appropriate team members.

set -euo pipefail

# ─── Configuration ────────────────────────────────────────────────────────────
REPO="${REPO:-}"
ISSUE_NUMBER="${ISSUE_NUMBER:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
OPENAI_API_KEY="${OPENAI_API_KEY:-}"

# ─── Validation ───────────────────────────────────────────────────────────────
if [[ -z "$REPO" ]]; then
  echo "ERROR: REPO environment variable is required (e.g. 'owner/repo')" >&2
  exit 1
fi

if [[ -z "$ISSUE_NUMBER" ]]; then
  echo "ERROR: ISSUE_NUMBER environment variable is required" >&2
  exit 1
fi

if [[ -z "$GITHUB_TOKEN" ]]; then
  echo "ERROR: GITHUB_TOKEN environment variable is required" >&2
  exit 1
fi

if [[ -z "$OPENAI_API_KEY" ]]; then
  echo "ERROR: OPENAI_API_KEY environment variable is required" >&2
  exit 1
fi

GH_API="https://api.github.com"
AUTH_HEADER="Authorization: Bearer ${GITHUB_TOKEN}"
ACCEPT_HEADER="Accept: application/vnd.github+json"

# ─── Helpers ──────────────────────────────────────────────────────────────────
gh_get() {
  curl -fsSL -H "$AUTH_HEADER" -H "$ACCEPT_HEADER" "${GH_API}/${1}"
}

gh_post() {
  local endpoint="$1"
  local payload="$2"
  curl -fsSL -X POST \
    -H "$AUTH_HEADER" \
    -H "$ACCEPT_HEADER" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${GH_API}/${endpoint}"
}

gh_patch() {
  local endpoint="$1"
  local payload="$2"
  curl -fsSL -X PATCH \
    -H "$AUTH_HEADER" \
    -H "$ACCEPT_HEADER" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "${GH_API}/${endpoint}"
}

log() { echo "[issue-triage] $*"; }

# ─── Fetch Issue ──────────────────────────────────────────────────────────────
log "Fetching issue #${ISSUE_NUMBER} from ${REPO}..."
ISSUE_JSON=$(gh_get "repos/${REPO}/issues/${ISSUE_NUMBER}")

ISSUE_TITLE=$(echo "$ISSUE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('title',''))")
ISSUE_BODY=$(echo "$ISSUE_JSON"  | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('body','') or '')")
ISSUE_AUTHOR=$(echo "$ISSUE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['user']['login'])")
EXISTING_LABELS=$(echo "$ISSUE_JSON" | python3 -c "import sys,json; d=json.load(sys.stdin); print(','.join(l['name'] for l in d.get('labels',[])))")

log "Title  : $ISSUE_TITLE"
log "Author : $ISSUE_AUTHOR"
log "Labels : ${EXISTING_LABELS:-<none>}"

# ─── Classify via OpenAI ──────────────────────────────────────────────────────
log "Classifying issue with OpenAI..."

PROMPT=$(python3 - <<'PYEOF'
import json, os, sys

title  = os.environ.get("ISSUE_TITLE", "")
body   = os.environ.get("ISSUE_BODY", "")[:3000]  # cap to avoid token overflow

system = (
    "You are an expert maintainer for the openai-agents-python SDK. "
    "Analyse the GitHub issue and return a JSON object with these fields:\n"
    "  label      : one of [bug, enhancement, question, documentation, duplicate, wontfix]\n"
    "  priority   : one of [critical, high, medium, low]\n"
    "  component  : one of [core, tracing, tools, streaming, voice, docs, ci, other]\n"
    "  summary    : one-sentence description (max 120 chars)\n"
    "  needs_repro: true/false — whether a reproduction case is missing\n"
    "Return ONLY valid JSON, no markdown fences."
)

user = f"Title: {title}\n\nBody:\n{body}"

payload = {
    "model": "gpt-4o-mini",
    "temperature": 0,
    "messages": [
        {"role": "system", "content": system},
        {"role": "user",   "content": user},
    ],
}
print(json.dumps(payload))
PYEOF
)

export ISSUE_TITLE ISSUE_BODY

AI_RESPONSE=$(echo "$PROMPT" | curl -fsSL -X POST \
  -H "Authorization: Bearer ${OPENAI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d @- \
  "https://api.openai.com/v1/chat/completions")

CLASSIFICATION=$(echo "$AI_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data['choices'][0]['message']['content'])
")

log "Classification: $CLASSIFICATION"

# ─── Parse Classification ─────────────────────────────────────────────────────
read LABEL PRIORITY COMPONENT SUMMARY NEEDS_REPRO <<< "$(echo "$CLASSIFICATION" | python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
print(d.get('label','question'), d.get('priority','medium'), d.get('component','other'),
      repr(d.get('summary','')), str(d.get('needs_repro', False)).lower())
")"

# ─── Apply Labels ─────────────────────────────────────────────────────────────
log "Applying labels: ${LABEL}, priority:${PRIORITY}, component:${COMPONENT}"

LABELS_JSON=$(python3 -c "
import json
labels = ['${LABEL}', 'priority:${PRIORITY}', 'component:${COMPONENT}']
print(json.dumps({'labels': labels}))
")

gh_post "repos/${REPO}/issues/${ISSUE_NUMBER}/labels" "$LABELS_JSON" > /dev/null

# ─── Request Repro if Needed ──────────────────────────────────────────────────
if [[ "$NEEDS_REPRO" == "true" && "$LABEL" == "bug" ]]; then
  log "Requesting reproduction steps from author..."
  COMMENT_BODY=$(python3 -c "
import json
body = (
    'Hi @${ISSUE_AUTHOR}, thanks for opening this issue! 👋\\n\\n'
    'To help us investigate, could you please provide a **minimal reproduction** '
    'script or steps to reproduce the problem? Including:\\n'
    '- SDK version (`pip show openai-agents`)\\n'
    '- Python version\\n'
    '- A short, self-contained code snippet\\n\\n'
    'Thank you!'
)
print(json.dumps({'body': body}))
")
  gh_post "repos/${REPO}/issues/${ISSUE_NUMBER}/comments" "$COMMENT_BODY" > /dev/null
fi

log "Triage complete for issue #${ISSUE_NUMBER}."
