#!/usr/bin/env bash
# Run: bash tests/install-update.test.sh
. "$(dirname "$0")/lib.sh"

test_fresh_install_copies_pack_files() {
  setup_sandbox
  run_install
  assert_file_is "fresh install copies .claude file" \
    "$TARGET/.claude/agents/code-reviewer.md" "v1 reviewer"
  assert_file_is "fresh install copies .cursor file" \
    "$TARGET/.cursor/rules/base.mdc" "v1 rule"
  assert_eq "fresh install exits 0" "$(install_exit_code)" "0"
  teardown_sandbox
}

test_existing_file_is_preserved() {
  setup_sandbox
  mkdir -p "$TARGET/.claude/agents"
  printf 'mine\n' > "$TARGET/.claude/agents/code-reviewer.md"
  run_install
  assert_file_is "pre-existing file preserved" \
    "$TARGET/.claude/agents/code-reviewer.md" "mine"
  teardown_sandbox
}

test_version_is_recorded_as_git_sha() {
  setup_sandbox
  run_install
  local head; head="$(git -C "$FIXTURE" rev-parse HEAD)"
  assert_out_contains "reports resolved pack version" "$head"
  teardown_sandbox
}

test_state_file_written_on_install() {
  setup_sandbox
  run_install
  local head; head="$(git -C "$FIXTURE" rev-parse HEAD)"
  assert_eq "state schema is 1"        "$(state_field schema)"        "1"
  assert_eq "state version is head"    "$(state_field version)"       "$head"
  assert_eq "state versionSource git"  "$(state_field versionSource)" "git"
  assert_eq "state ref is main"        "$(state_field ref)"           "main"
  # re-enabled in Task 6: record_state_entry is not called until Task 6, so
  # "files" is written as an empty object and this assertion cannot pass yet.
  # if state_json | grep -q '"\.claude/agents/code-reviewer\.md"'; then
  #   ok "state records file hash"
  # else
  #   fail "state records file hash" "key missing from state"
  # fi
  teardown_sandbox
}

printf 'install-update tests\n'
test_fresh_install_copies_pack_files
test_existing_file_is_preserved
test_version_is_recorded_as_git_sha
test_state_file_written_on_install
finish
