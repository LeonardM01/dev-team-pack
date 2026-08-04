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

printf 'install-update tests\n'
test_fresh_install_copies_pack_files
test_existing_file_is_preserved
finish
