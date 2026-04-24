#!/usr/bin/env bash
# examples-auto-run/scripts/run.sh
# Automatically discovers and runs all examples in the repository,
# capturing output and reporting pass/fail status for each.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
EXAMPLES_DIR="${REPO_ROOT}/examples"
RESULTS_DIR="${REPO_ROOT}/.agents/skills/examples-auto-run/results"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-60}"
PYTHON="${PYTHON:-python3}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Colours for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Colour

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log_info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

check_dependencies() {
    local missing=0
    for cmd in "$PYTHON" git timeout; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "Required command not found: $cmd"
            missing=1
        fi
    done
    [[ $missing -eq 0 ]] || exit 1
}

prepare_results_dir() {
    mkdir -p "$RESULTS_DIR"
    # Clear previous run artefacts
    rm -f "${RESULTS_DIR}"/*.log "${RESULTS_DIR}/summary.json"
}

# ---------------------------------------------------------------------------
# Run a single example file
# Returns 0 on success, non-zero on failure.
# ---------------------------------------------------------------------------
run_example() {
    local example_file="$1"
    local relative_path="${example_file#"${REPO_ROOT}/"}"
    local safe_name
    safe_name="$(echo "$relative_path" | tr '/' '_' | tr ' ' '_')"
    local log_file="${RESULTS_DIR}/${safe_name}.log"

    log_info "Running: ${relative_path}"

    # Some examples require environment variables — skip gracefully if they
    # are missing rather than failing the whole suite.
    if grep -qE 'os\.environ|getenv' "$example_file" 2>/dev/null; then
        if [[ -z "${OPENAI_API_KEY:-}" ]]; then
            log_warn "Skipping ${relative_path} — OPENAI_API_KEY not set"
            echo '{"status": "skipped", "reason": "OPENAI_API_KEY not set"}' > "${log_file%.log}.json"
            return 0
        fi
    fi

    local start_time
    start_time=$(date +%s)

    if timeout "$TIMEOUT_SECONDS" "$PYTHON" "$example_file" \
           > "$log_file" 2>&1; then
        local end_time elapsed
        end_time=$(date +%s)
        elapsed=$(( end_time - start_time ))
        log_info "  ✓ PASSED (${elapsed}s)"
        echo "{\"status\": \"passed\", \"elapsed_seconds\": ${elapsed}}" \
            > "${log_file%.log}.json"
        return 0
    else
        local exit_code=$?
        local end_time elapsed
        end_time=$(date +%s)
        elapsed=$(( end_time - start_time ))
        if [[ $exit_code -eq 124 ]]; then
            log_error "  ✗ TIMEOUT after ${TIMEOUT_SECONDS}s — ${relative_path}"
            echo "{\"status\": \"timeout\", \"elapsed_seconds\": ${elapsed}}" \
                > "${log_file%.log}.json"
        else
            log_error "  ✗ FAILED (exit ${exit_code}) — ${relative_path}"
            echo "{\"status\": \"failed\", \"exit_code\": ${exit_code}, \"elapsed_seconds\": ${elapsed}}" \
                > "${log_file%.log}.json"
        fi
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Collect and run all examples
# ---------------------------------------------------------------------------
run_all_examples() {
    local passed=0 failed=0 skipped=0 total=0

    if [[ ! -d "$EXAMPLES_DIR" ]]; then
        log_warn "Examples directory not found: ${EXAMPLES_DIR}"
        return 0
    fi

    # Discover all top-level Python entry-point files inside examples/
    mapfile -t example_files < <(
        find "$EXAMPLES_DIR" -name 'main.py' -o -name 'run.py' \
        | sort
    )

    if [[ ${#example_files[@]} -eq 0 ]]; then
        log_warn "No example entry-point files found under ${EXAMPLES_DIR}"
        return 0
    fi

    for f in "${example_files[@]}"; do
        (( total++ )) || true
        local result_json
        result_json="${RESULTS_DIR}/$(echo "${f#"${REPO_ROOT}/"}" | tr '/' '_' | tr ' ' '_' | sed 's/\.py$/.json/')"

        if run_example "$f"; then
            local status
            status=$(python3 -c "import json,sys; d=json.load(open('${result_json}')); print(d.get('status',''))" 2>/dev/null || echo passed)
            if [[ "$status" == "skipped" ]]; then
                (( skipped++ )) || true
            else
                (( passed++ )) || true
            fi
        else
            (( failed++ )) || true
        fi
    done

    # Write aggregated summary
    cat > "${RESULTS_DIR}/summary.json" <<EOF
{
  "total": ${total},
  "passed": ${passed},
  "failed": ${failed},
  "skipped": ${skipped}
}
EOF

    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info " Results: ${passed} passed / ${failed} failed / ${skipped} skipped / ${total} total"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info " Logs saved to: ${RESULTS_DIR}"

    [[ $failed -eq 0 ]]
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
    log_info "examples-auto-run starting"
    log_info "Repo root  : ${REPO_ROOT}"
    log_info "Examples   : ${EXAMPLES_DIR}"
    log_info "Timeout    : ${TIMEOUT_SECONDS}s per example"
    log_info "Python     : $($PYTHON --version 2>&1)"
    echo ""

    check_dependencies
    prepare_results_dir
    run_all_examples
}

main "$@"
