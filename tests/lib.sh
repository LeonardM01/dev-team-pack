#!/usr/bin/env bash
# Shared helpers for installer tests. Sourced, not executed.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_RUN=0
TESTS_FAILED=0
SANDBOX=""
FIXTURE=""
TARGET=""

git_fixture() { git -C "$FIXTURE" -c user.email=t@example.com -c user.name=test "$@"; }

setup_sandbox() {
  SANDBOX="$(mktemp -d)"
  FIXTURE="$SANDBOX/fixture"
  TARGET="$SANDBOX/target"
  mkdir -p "$FIXTURE/.claude/agents" "$FIXTURE/.cursor/rules" "$TARGET"
  printf 'v1 reviewer\n'  > "$FIXTURE/.claude/agents/code-reviewer.md"
  printf 'v1 architect\n' > "$FIXTURE/.claude/agents/code-architect.md"
  printf 'v1 rule\n'      > "$FIXTURE/.cursor/rules/base.mdc"
  printf 'v1 pack docs\n' > "$FIXTURE/CLAUDE.md"
  printf '{ "mcpServers": { "context7": {"command":"c7"}, "lean-ctx": {"command":"lc"} } }\n' \
    > "$FIXTURE/.mcp.json"
  printf '{ "enabledMcpjsonServers": ["context7", "lean-ctx"] }\n' \
    > "$FIXTURE/.claude/settings.json"
  git -C "$FIXTURE" init -q -b main
  git_fixture add -A
  git_fixture commit -q -m v1
}

teardown_sandbox() { [ -n "$SANDBOX" ] && rm -rf "$SANDBOX"; SANDBOX=""; }

fixture_commit() { git_fixture add -A; git_fixture commit -q -m "$1"; }

run_install() {
  DEV_TEAM_REPO="$FIXTURE" DEV_TEAM_REF=main DEV_TEAM_NONINTERACTIVE=1 NO_COLOR=1 \
    bash "$REPO_ROOT/install.sh" "$TARGET" "$@" >"$SANDBOX/out.txt" 2>&1
  printf '%s' "$?" > "$SANDBOX/exit.txt"
  return 0
}

install_exit_code() { cat "$SANDBOX/exit.txt"; }
state_json() { cat "$TARGET/.dev-team-pack.json" 2>/dev/null; }

state_field() {
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("."):
    d = d.get(k, "") if isinstance(d, dict) else ""
print(d if not isinstance(d, (list, dict)) else json.dumps(d))
' "$TARGET/.dev-team-pack.json" "$1" 2>/dev/null
}

ok()   { TESTS_RUN=$((TESTS_RUN+1)); printf '  ok   %s\n' "$1"; }
fail() { TESTS_RUN=$((TESTS_RUN+1)); TESTS_FAILED=$((TESTS_FAILED+1)); printf '  FAIL %s\n       %s\n' "$1" "$2"; }

assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail "$1" "expected [$3] got [$2]"; fi
}
assert_file_is() {
  local got; got="$(cat "$2" 2>/dev/null || true)"
  assert_eq "$1" "$got" "$3"
}
assert_file_absent() {
  if [ -e "$2" ]; then fail "$1" "expected absent: $2"; else ok "$1"; fi
}
assert_out_contains() {
  if grep -qF "$2" "$SANDBOX/out.txt"; then ok "$1"; else
    fail "$1" "output missing [$2]; got:
$(cat "$SANDBOX/out.txt")"
  fi
}
assert_out_lacks() {
  if grep -qF "$2" "$SANDBOX/out.txt"; then fail "$1" "output should not contain [$2]"; else ok "$1"; fi
}
assert_files_identical() {
  if cmp -s "$2" "$3"; then
    ok "$1"
  else
    fail "$1" "files differ:
$(diff "$2" "$3" 2>&1 | head -40)"
  fi
}

finish() {
  printf '\n%s run, %s failed\n' "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
