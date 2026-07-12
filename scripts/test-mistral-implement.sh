#!/usr/bin/env bash
# Smoke tests for mistral-implement.sh's guard rails (bad args, missing
# commands, missing MISTRAL_API_KEY, bad repo path). Every case here fails
# before the script would reach `gh issue view` or `vibe`, so these tests
# make no network calls, need no GitHub auth, and never spend Vibe budget.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/mistral-implement.sh"
BASH_BIN="$(command -v bash)"
GIT_BIN="$(command -v git)"
REAL_BIN_DIR="$(dirname "$GIT_BIN")"

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

# Stub gh/vibe: they only need to exist and be executable for the
# command-presence check. If a test ever reaches the point of actually
# running the stub `vibe`, that's a bug in the test, not real Vibe usage.
mk_stub() {
  local dir="$1"; shift
  mkdir -p "$dir"
  for name in "$@"; do
    printf '#!/usr/bin/env bash\necho "stub %s should not run in these tests" >&2\nexit 1\n' "$name" > "$dir/$name"
    chmod +x "$dir/$name"
  done
}

FULL_STUBS="$TMP_ROOT/full"
mk_stub "$FULL_STUBS" gh vibe
PATH_FULL="$FULL_STUBS:$REAL_BIN_DIR"

NO_GH_STUBS="$TMP_ROOT/no_gh"
mk_stub "$NO_GH_STUBS" vibe
PATH_NO_GH="$NO_GH_STUBS:$REAL_BIN_DIR"

NO_VIBE_STUBS="$TMP_ROOT/no_vibe"
mk_stub "$NO_VIBE_STUBS" gh
PATH_NO_VIBE="$NO_VIBE_STUBS:$REAL_BIN_DIR"

GIT_REPO="$TMP_ROOT/repo"
mkdir -p "$GIT_REPO"
git -C "$GIT_REPO" init -q

NOT_GIT_REPO="$TMP_ROOT/not_repo"
mkdir -p "$NOT_GIT_REPO"

PASS=0
FAIL=0

run() {
  # run <PATH> <MISTRAL_API_KEY> <script args...>
  local path_val="$1" key_val="$2"; shift 2
  env -i PATH="$path_val" MISTRAL_API_KEY="$key_val" HOME="$HOME" "$BASH_BIN" "$SCRIPT" "$@" 2>&1
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

out=$(run "$PATH_FULL" "dummy"); ec=$?
check "no args -> usage error" "$ec" "usage" "$out"

out=$(run "$PATH_FULL" "dummy" 1 2 3); ec=$?
check "too many args -> usage error" "$ec" "usage" "$out"

out=$(run "$PATH_FULL" "dummy" abc "$GIT_REPO"); ec=$?
check "non-numeric issue number -> error" "$ec" "numeric" "$out"

out=$(run "$PATH_NO_GH" "dummy" 42 "$GIT_REPO"); ec=$?
check "missing gh -> clear error" "$ec" "gh" "$out"

out=$(run "$PATH_NO_VIBE" "dummy" 42 "$GIT_REPO"); ec=$?
check "missing vibe -> clear error" "$ec" "vibe" "$out"

out=$(run "$PATH_FULL" "" 42 "$GIT_REPO"); ec=$?
check "missing MISTRAL_API_KEY -> clear error" "$ec" "MISTRAL_API_KEY" "$out"

out=$(run "$PATH_FULL" "dummy" 42 "$TMP_ROOT/does-not-exist"); ec=$?
check "nonexistent repo path -> clear error" "$ec" "does not exist" "$out"

out=$(run "$PATH_FULL" "dummy" 42 "$NOT_GIT_REPO"); ec=$?
check "non-git repo path -> clear error" "$ec" "git repository" "$out"

echo ""
echo "$PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
