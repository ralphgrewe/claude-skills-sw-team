#!/usr/bin/env bash
# Push a single GitHub issue to Mistral Vibe CLI for a manual, hand-picked
# implementation attempt. Part of the Phase 1 (manual) rollout of issue #2.
#
# Usage: mistral-implement.sh <issue-number> [repo-path]
#
# Makes NO GitHub writes (no comments, labels, closes, pushes) — the operator
# reviews the local commit and records findings on issue #2 by hand.
set -euo pipefail

# --- Guardrails (edit here, not inline below) ---
MAX_TURNS=20
MAX_PRICE=2.00

usage() {
  echo "Usage: $(basename "$0") <issue-number> [repo-path]" >&2
  echo "  repo-path defaults to the current directory." >&2
  exit 1
}

[[ $# -ge 1 && $# -le 2 ]] || usage

ISSUE_NUMBER="$1"
REPO_PATH="${2:-$(pwd)}"

if [[ ! "$ISSUE_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "Error: issue number must be numeric, got '$ISSUE_NUMBER'." >&2
  exit 1
fi

for cmd in gh vibe git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found on PATH." >&2
    case "$cmd" in
      gh) echo "Install: https://cli.github.com/" >&2 ;;
      vibe) echo "Install: https://github.com/mistralai/mistral-vibe" >&2 ;;
    esac
    exit 1
  fi
done

if [[ -z "${MISTRAL_API_KEY:-}" ]]; then
  echo "Error: MISTRAL_API_KEY is not set. Vibe needs it to authenticate." >&2
  exit 1
fi

if [[ ! -d "$REPO_PATH" ]]; then
  echo "Error: repo path '$REPO_PATH' does not exist." >&2
  exit 1
fi

if ! git -C "$REPO_PATH" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: '$REPO_PATH' is not a git repository." >&2
  exit 1
fi

echo "Fetching issue #${ISSUE_NUMBER} from $REPO_PATH..." >&2
if ! ISSUE_TITLE=$(cd "$REPO_PATH" && gh issue view "$ISSUE_NUMBER" --json title --jq '.title' 2>&1); then
  echo "Error: could not fetch issue #${ISSUE_NUMBER} (does it exist? is 'gh' authenticated for this repo?)." >&2
  echo "$ISSUE_TITLE" >&2
  exit 1
fi
if ! ISSUE_BODY=$(cd "$REPO_PATH" && gh issue view "$ISSUE_NUMBER" --json body --jq '.body' 2>&1); then
  echo "Error: could not fetch the body of issue #${ISSUE_NUMBER}." >&2
  echo "$ISSUE_BODY" >&2
  exit 1
fi

PROMPT=$(cat <<EOF
Implement GitHub issue #${ISSUE_NUMBER} in this repository.

Issue title: ${ISSUE_TITLE}

Issue body:
${ISSUE_BODY}

You have no GitHub access — you cannot fetch further issue detail, comment,
label, or close anything. Treat the text above as the full spec.

Repo conventions: read and follow CLAUDE.md and/or README.md at the repo
root if present.

Steps:
1. If anything required to implement this issue is ambiguous or missing
   (unclear acceptance criteria, missing config, conflicting instructions),
   do NOT guess. Stop and clearly state your specific open question instead
   of implementing on a guess — the operator running this script will relay
   your question to the issue manually.
2. Otherwise, implement the change described above.
3. Add/update tests covering the change.
4. Run the test suite — it must pass before proceeding.
5. Commit locally (do NOT push) with a one-line summary plus a brief body,
   ending with "Closes #${ISSUE_NUMBER}".
EOF
)

echo "Running vibe (--max-turns=${MAX_TURNS} --max-price=${MAX_PRICE})..." >&2
BEFORE_SHA=$(git -C "$REPO_PATH" rev-parse HEAD 2>/dev/null || echo "none")

set +e
VIBE_OUTPUT=$(vibe --prompt "$PROMPT" --auto-approve --output json \
  --max-turns "$MAX_TURNS" --max-price "$MAX_PRICE" --workdir "$REPO_PATH" 2>&1)
VIBE_EXIT=$?
set -e

AFTER_SHA=$(git -C "$REPO_PATH" rev-parse HEAD 2>/dev/null || echo "none")
if [[ "$AFTER_SHA" != "$BEFORE_SHA" && "$AFTER_SHA" != "none" ]]; then
  COMMIT_SHA="$AFTER_SHA"
  BRANCH=$(git -C "$REPO_PATH" rev-parse --abbrev-ref HEAD)
else
  COMMIT_SHA="none"
  BRANCH="none"
fi

echo ""
echo "===================================================="
echo " Mistral Vibe run summary — issue #${ISSUE_NUMBER}"
echo "===================================================="
echo "Commit: ${COMMIT_SHA}"
echo "Branch: ${BRANCH}"
echo "Vibe exit code: ${VIBE_EXIT}"
echo ""
echo "Vibe's reported outcome (review below for test result and diff quality):"
echo "----------------------------------------------------"
if command -v jq >/dev/null 2>&1 && echo "$VIBE_OUTPUT" | jq -e . >/dev/null 2>&1; then
  echo "$VIBE_OUTPUT" | jq .
else
  echo "$VIBE_OUTPUT"
fi
echo "----------------------------------------------------"
echo ""
echo "This script made no GitHub writes. Inspect the commit above yourself,"
echo "then record your findings (success/failure, diff quality, cost, prompt"
echo "adjustments) as a comment on issue #2 by hand — see"
echo "docs/mistral-vibe-runbook.md for the full cycle."
