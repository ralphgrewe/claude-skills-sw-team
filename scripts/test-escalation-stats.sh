#!/usr/bin/env bash
# Smoke tests for escalation-stats.py's guardrails (bad --repo format, missing
# gh, gh not authenticated). Every case here fails before the script would
# reach a real `gh repo list` / `gh api` call, so these tests make no network
# calls and need no GitHub auth.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/escalation-stats.py"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PYTHON_BIN="$REPO_ROOT/venv/bin/python"
if [[ ! -x "$PYTHON_BIN" ]]; then
  PYTHON_BIN="$(command -v python3)"
fi

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# Stub `gh`: `gh auth status` exit code is controlled by GH_AUTH_EXIT so we
# can simulate an authenticated or unauthenticated session. Any other
# invocation is unexpected in these guardrail-only tests and fails loudly,
# which also proves the test never reached real network/API calls.
mk_gh_stub() {
  local dir="$1" auth_exit="$2"
  mkdir -p "$dir"
  cat > "$dir/gh" <<EOF
#!/usr/bin/env bash
if [[ "\$1 \$2" == "auth status" ]]; then
  exit ${auth_exit}
fi
echo "stub gh: unexpected invocation: \$*" >&2
exit 1
EOF
  chmod +x "$dir/gh"
}

AUTHED_STUBS="$TMP_ROOT/authed"
mk_gh_stub "$AUTHED_STUBS" 0
PATH_AUTHED="$AUTHED_STUBS"

UNAUTHED_STUBS="$TMP_ROOT/unauthed"
mk_gh_stub "$UNAUTHED_STUBS" 1
PATH_UNAUTHED="$UNAUTHED_STUBS"

NO_GH_STUBS="$TMP_ROOT/no_gh"
mkdir -p "$NO_GH_STUBS"
PATH_NO_GH="$NO_GH_STUBS"

PASS=0
FAIL=0

run() {
  # run <PATH> <script args...>
  local path_val="$1"; shift
  env -i PATH="$path_val" HOME="$HOME" "$PYTHON_BIN" "$SCRIPT" "$@" 2>&1
}

check() {
  local desc="$1" exit_code="$2" grep_for="$3" output="$4"
  if [[ "$exit_code" -ne 0 ]] && grep -qi "$grep_for" <<<"$output"; then
    echo "PASS: $desc"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $desc (exit=$exit_code)"
    echo "  output: $output"
    FAIL=$((FAIL + 1))
  fi
}

out=$(run "$PATH_AUTHED" --repo badformat); ec=$?
check "--repo without a slash -> error" "$ec" "OWNER/REPO" "$out"

out=$(run "$PATH_AUTHED" --repo "owner/"); ec=$?
check "--repo with empty repo segment -> error" "$ec" "OWNER/REPO" "$out"

out=$(run "$PATH_AUTHED" --repo "/repo"); ec=$?
check "--repo with empty owner segment -> error" "$ec" "OWNER/REPO" "$out"

out=$(run "$PATH_NO_GH"); ec=$?
check "missing gh -> clear error" "$ec" "gh" "$out"

out=$(run "$PATH_UNAUTHED"); ec=$?
check "gh not authenticated -> clear error" "$ec" "authenticated" "$out"

out=$("$PYTHON_BIN" "$SCRIPT" --help 2>&1); ec=$?
if [[ "$ec" -eq 0 ]] && grep -qi -- "--repo" <<<"$out"; then
  echo "PASS: --help exits cleanly and documents --repo"
  PASS=$((PASS + 1))
else
  echo "FAIL: --help exits cleanly and documents --repo (exit=$ec)"
  echo "  output: $out"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
