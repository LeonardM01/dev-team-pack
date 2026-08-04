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
  if state_json | grep -q '"\.claude/agents/code-reviewer\.md"'; then
    ok "state records file hash"
  else
    fail "state records file hash" "key missing from state"
  fi
  teardown_sandbox
}

test_second_run_reports_up_to_date() {
  setup_sandbox
  run_install
  run_install
  assert_out_contains "second run reports up to date" "Already up to date"
  assert_eq "up-to-date run exits 0" "$(install_exit_code)" "0"
  teardown_sandbox
}

test_force_bypasses_up_to_date() {
  setup_sandbox
  run_install
  run_install --force
  assert_out_lacks "force bypasses early exit" "Already up to date"
  teardown_sandbox
}

test_target_positional_still_works_after_flags() {
  setup_sandbox
  run_install --force
  assert_file_is "target arg honored alongside flag" \
    "$TARGET/.claude/agents/code-reviewer.md" "v1 reviewer"
  teardown_sandbox
}

test_double_dash_rejects_extra_positional() {
  setup_sandbox
  local exit_code
  bash "$REPO_ROOT/install.sh" --force -- foo bar >"$SANDBOX/out.txt" 2>&1
  exit_code=$?
  assert_eq "-- with two positionals exits 2" "$exit_code" "2"
  assert_out_contains "-- with two positionals reports unexpected argument" "Unexpected argument: bar"
  teardown_sandbox
}

test_untouched_file_is_updated() {
  setup_sandbox
  run_install
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_file_is "untouched file updated" \
    "$TARGET/.claude/agents/code-reviewer.md" "v2 reviewer"
  assert_out_contains "reports update" "updated"
  teardown_sandbox
}

test_locally_edited_file_is_kept() {
  setup_sandbox
  run_install
  printf 'mine\n' > "$TARGET/.claude/agents/code-reviewer.md"
  printf 'v2 architect\n' > "$FIXTURE/.claude/agents/code-architect.md"
  fixture_commit v2
  run_install
  assert_file_is "local edit kept when upstream unchanged" \
    "$TARGET/.claude/agents/code-reviewer.md" "mine"
  assert_file_is "sibling still updated" \
    "$TARGET/.claude/agents/code-architect.md" "v2 architect"
  teardown_sandbox
}

test_conflict_is_reported_not_overwritten() {
  setup_sandbox
  run_install
  printf 'mine\n' > "$TARGET/.claude/agents/code-reviewer.md"
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_file_is "conflict preserves local" \
    "$TARGET/.claude/agents/code-reviewer.md" "mine"
  assert_out_contains "conflict reported" "conflict"
  teardown_sandbox
}

test_force_overwrites_conflict() {
  setup_sandbox
  run_install
  printf 'mine\n' > "$TARGET/.claude/agents/code-reviewer.md"
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install --force
  assert_file_is "force overwrites conflict" \
    "$TARGET/.claude/agents/code-reviewer.md" "v2 reviewer"
  teardown_sandbox
}

test_deleted_file_stays_deleted() {
  setup_sandbox
  run_install
  rm "$TARGET/.claude/agents/code-reviewer.md"
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_file_absent "deleted file not resurrected" \
    "$TARGET/.claude/agents/code-reviewer.md"
  printf 'v3 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v3
  run_install
  assert_file_absent "deletion sticky across two updates" \
    "$TARGET/.claude/agents/code-reviewer.md"
  teardown_sandbox
}

test_adopted_file_is_updated_on_next_run() {
  setup_sandbox
  mkdir -p "$TARGET/.claude/agents"
  printf 'mine\n' > "$TARGET/.claude/agents/code-reviewer.md"
  run_install
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_file_is "baseline-adopted file updates on next run" \
    "$TARGET/.claude/agents/code-reviewer.md" "v2 reviewer"
  teardown_sandbox
}

test_conflict_in_one_step_does_not_warn_other_steps() {
  setup_sandbox
  run_install
  printf 'mine\n' > "$TARGET/.claude/agents/code-reviewer.md"
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_out_contains "claude step reports its own conflict warning" \
    "Merge .claude/ config: finished with warnings"
  assert_out_lacks "cursor step not contaminated by claude's conflict" \
    "Merge .cursor/ config: finished with warnings"
  assert_out_contains "cursor step reports skipped when nothing changed there" \
    "Merge .cursor/ config: skipped"
  teardown_sandbox
}

printf 'install-update tests\n'
test_fresh_install_copies_pack_files
test_existing_file_is_preserved
test_version_is_recorded_as_git_sha
test_state_file_written_on_install
test_second_run_reports_up_to_date
test_force_bypasses_up_to_date
test_target_positional_still_works_after_flags
test_double_dash_rejects_extra_positional
test_untouched_file_is_updated
test_locally_edited_file_is_kept
test_conflict_is_reported_not_overwritten
test_force_overwrites_conflict
test_deleted_file_stays_deleted
test_adopted_file_is_updated_on_next_run
test_conflict_in_one_step_does_not_warn_other_steps
finish
