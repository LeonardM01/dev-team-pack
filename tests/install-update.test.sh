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

test_claude_md_block_updates_preserving_user_content() {
  setup_sandbox
  run_install
  printf '\n\n# My own notes\n' >> "$TARGET/CLAUDE.md"
  printf 'v2 pack docs\n' > "$FIXTURE/CLAUDE.md"
  fixture_commit v2
  run_install
  if grep -q 'v2 pack docs' "$TARGET/CLAUDE.md"; then
    ok "CLAUDE.md block updated"
  else
    fail "CLAUDE.md block updated" "block still at v1"
  fi
  if grep -q '# My own notes' "$TARGET/CLAUDE.md"; then
    ok "content outside markers preserved"
  else
    fail "content outside markers preserved" "user content lost"
  fi
  if ! grep -q 'v1 pack docs' "$TARGET/CLAUDE.md"; then
    ok "old block content removed"
  else
    fail "old block content removed" "v1 text still present"
  fi
  teardown_sandbox
}

test_edited_claude_md_block_conflicts() {
  setup_sandbox
  run_install
  perl -0pi -e 's/v1 pack docs/hand edited/' "$TARGET/CLAUDE.md"
  printf 'v2 pack docs\n' > "$FIXTURE/CLAUDE.md"
  fixture_commit v2
  run_install
  if grep -q 'hand edited' "$TARGET/CLAUDE.md"; then
    ok "edited block preserved on conflict"
  else
    fail "edited block preserved on conflict" "block was overwritten"
  fi
  teardown_sandbox
}

test_claude_md_block_update_preserves_content_before_and_after() {
  setup_sandbox
  run_install
  {
    printf '# Before notes\nsome preamble\n\n'
    cat "$TARGET/CLAUDE.md"
    printf '\n\n# After notes\ntrailing content\n'
  } > "$SANDBOX/claude_md_seed.txt"
  cp "$SANDBOX/claude_md_seed.txt" "$TARGET/CLAUDE.md"
  printf 'v2 pack docs\n' > "$FIXTURE/CLAUDE.md"
  fixture_commit v2
  run_install
  printf '# Before notes\nsome preamble\n\n<!-- dev-team-pack:begin -->\n# Dev Team Pack\nv2 pack docs\n<!-- dev-team-pack:end -->\n\n\n# After notes\ntrailing content\n' \
    > "$SANDBOX/claude_md_expected.txt"
  assert_files_identical "block update preserves content on both sides, byte-for-byte" \
    "$TARGET/CLAUDE.md" "$SANDBOX/claude_md_expected.txt"
  teardown_sandbox
}

test_claude_md_marker_substring_in_prose_is_not_treated_as_marker() {
  setup_sandbox
  run_install
  {
    printf 'Notes: markers are delimited by <!-- dev-team-pack:begin -->.\n\n'
    cat "$TARGET/CLAUDE.md"
  } > "$SANDBOX/claude_md_seed.txt"
  cp "$SANDBOX/claude_md_seed.txt" "$TARGET/CLAUDE.md"
  printf 'v2 pack docs\n' > "$FIXTURE/CLAUDE.md"
  fixture_commit v2
  run_install
  printf 'Notes: markers are delimited by <!-- dev-team-pack:begin -->.\n\n<!-- dev-team-pack:begin -->\n# Dev Team Pack\nv2 pack docs\n<!-- dev-team-pack:end -->\n' \
    > "$SANDBOX/claude_md_expected.txt"
  assert_files_identical "marker text inside a prose line does not confuse the block locator" \
    "$TARGET/CLAUDE.md" "$SANDBOX/claude_md_expected.txt"
  teardown_sandbox
}

test_claude_md_update_preserves_missing_trailing_newline() {
  setup_sandbox
  run_install
  {
    cat "$TARGET/CLAUDE.md"
    printf 'trailing content, no newline at EOF'
  } > "$SANDBOX/claude_md_seed.txt"
  cp "$SANDBOX/claude_md_seed.txt" "$TARGET/CLAUDE.md"
  printf 'v2 pack docs\n' > "$FIXTURE/CLAUDE.md"
  fixture_commit v2
  run_install
  printf '<!-- dev-team-pack:begin -->\n# Dev Team Pack\nv2 pack docs\n<!-- dev-team-pack:end -->\ntrailing content, no newline at EOF' \
    > "$SANDBOX/claude_md_expected.txt"
  assert_files_identical "tail content with no trailing newline is preserved exactly, no newline gained" \
    "$TARGET/CLAUDE.md" "$SANDBOX/claude_md_expected.txt"
  teardown_sandbox
}

test_claude_md_missing_end_marker_leaves_file_untouched() {
  setup_sandbox
  run_install
  perl -0pi -e 's/<!-- dev-team-pack:end -->\n?//' "$TARGET/CLAUDE.md"
  cp "$TARGET/CLAUDE.md" "$SANDBOX/claude_md_corrupted.txt"
  printf 'v2 pack docs\n' > "$FIXTURE/CLAUDE.md"
  fixture_commit v2
  run_install
  assert_files_identical "CLAUDE.md with begin marker but no end marker is left untouched" \
    "$TARGET/CLAUDE.md" "$SANDBOX/claude_md_corrupted.txt"
  assert_out_contains "missing end marker is logged" "no matching end marker"
  teardown_sandbox
}

test_claude_md_update_preserves_single_trailing_blank_line() {
  setup_sandbox
  run_install
  {
    cat "$TARGET/CLAUDE.md"
    printf 'after1\n\n'
  } > "$SANDBOX/claude_md_seed.txt"
  cp "$SANDBOX/claude_md_seed.txt" "$TARGET/CLAUDE.md"
  printf 'v2 pack docs\n' > "$FIXTURE/CLAUDE.md"
  fixture_commit v2
  run_install
  printf '<!-- dev-team-pack:begin -->\n# Dev Team Pack\nv2 pack docs\n<!-- dev-team-pack:end -->\nafter1\n\n' \
    > "$SANDBOX/claude_md_expected.txt"
  assert_files_identical "single trailing blank line at EOF is preserved, not dropped" \
    "$TARGET/CLAUDE.md" "$SANDBOX/claude_md_expected.txt"
  teardown_sandbox
}

test_claude_md_update_preserves_two_trailing_blank_lines() {
  setup_sandbox
  run_install
  {
    cat "$TARGET/CLAUDE.md"
    printf 'after1\n\n\n'
  } > "$SANDBOX/claude_md_seed.txt"
  cp "$SANDBOX/claude_md_seed.txt" "$TARGET/CLAUDE.md"
  printf 'v2 pack docs\n' > "$FIXTURE/CLAUDE.md"
  fixture_commit v2
  run_install
  printf '<!-- dev-team-pack:begin -->\n# Dev Team Pack\nv2 pack docs\n<!-- dev-team-pack:end -->\nafter1\n\n\n' \
    > "$SANDBOX/claude_md_expected.txt"
  assert_files_identical "two trailing blank lines at EOF are preserved, loss does not compound" \
    "$TARGET/CLAUDE.md" "$SANDBOX/claude_md_expected.txt"
  teardown_sandbox
}

test_claude_md_update_preserves_missing_trailing_newline_when_end_marker_is_last_line() {
  setup_sandbox
  run_install
  printf '%s' "$(cat "$TARGET/CLAUDE.md")" > "$SANDBOX/claude_md_seed.txt"
  cp "$SANDBOX/claude_md_seed.txt" "$TARGET/CLAUDE.md"
  printf 'v2 pack docs\n' > "$FIXTURE/CLAUDE.md"
  fixture_commit v2
  run_install
  printf '<!-- dev-team-pack:begin -->\n# Dev Team Pack\nv2 pack docs\n<!-- dev-team-pack:end -->' \
    > "$SANDBOX/claude_md_expected.txt"
  assert_files_identical "end marker as last line with no trailing newline and nothing after stays newline-free" \
    "$TARGET/CLAUDE.md" "$SANDBOX/claude_md_expected.txt"
  teardown_sandbox
}

test_mcp_selection_is_reused_on_update() {
  setup_sandbox
  DEV_TEAM_REPO="$FIXTURE" DEV_TEAM_REF=main DEV_TEAM_MCPS=context7 NO_COLOR=1 \
    bash "$REPO_ROOT/install.sh" "$TARGET" >"$SANDBOX/out.txt" 2>&1
  assert_eq "first run records single mcp" "$(state_field mcps)" '["context7"]'
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_eq "second run reuses recorded mcps" "$(state_field mcps)" '["context7"]'
  assert_out_contains "reports reuse" "from previous install"
  teardown_sandbox
}

test_mcp_selection_absent_from_state_falls_back_to_default() {
  setup_sandbox
  DEV_TEAM_REPO="$FIXTURE" DEV_TEAM_REF=main DEV_TEAM_MCPS=context7 NO_COLOR=1 \
    bash "$REPO_ROOT/install.sh" "$TARGET" >"$SANDBOX/out.txt" 2>&1
  assert_eq "first run records single mcp" "$(state_field mcps)" '["context7"]'
  python3 -c '
import json
sf = "'"$TARGET"'/.dev-team-pack.json"
d = json.load(open(sf))
d.pop("mcps", None)
json.dump(d, open(sf, "w"), indent=2)
'
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_eq "second run does not silently reuse empty selection; falls back to non-interactive default (all)" \
    "$(state_field mcps)" '["context7", "lean-ctx"]'
  teardown_sandbox
}

test_mcp_selection_explicit_empty_is_reused_not_defaulted() {
  setup_sandbox
  DEV_TEAM_REPO="$FIXTURE" DEV_TEAM_REF=main DEV_TEAM_MCPS=none NO_COLOR=1 \
    bash "$REPO_ROOT/install.sh" "$TARGET" >"$SANDBOX/out.txt" 2>&1
  assert_eq "first run records empty mcps" "$(state_field mcps)" '[]'
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_eq "second run reuses explicit empty selection, does not default to all" \
    "$(state_field mcps)" '[]'
  teardown_sandbox
}

test_tool_selection_is_reused_on_update() {
  setup_sandbox
  DEV_TEAM_REPO="$FIXTURE" DEV_TEAM_REF=main DEV_TEAM_TOOLS=claude NO_COLOR=1 \
    bash "$REPO_ROOT/install.sh" "$TARGET" >"$SANDBOX/out.txt" 2>&1
  assert_eq "first run records single tool" "$(state_field tools)" '["claude"]'
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_eq "second run reuses recorded tools" "$(state_field tools)" '["claude"]'
  assert_out_contains "reports tools reuse" "from previous install"
  teardown_sandbox
}

test_update_summary_tallies_and_lists_conflicts() {
  setup_sandbox
  run_install
  printf 'mine\n' > "$TARGET/.claude/agents/code-reviewer.md"
  printf 'v2 reviewer\n'  > "$FIXTURE/.claude/agents/code-reviewer.md"
  printf 'v2 architect\n' > "$FIXTURE/.claude/agents/code-architect.md"
  fixture_commit v2
  run_install
  assert_out_contains "summary tallies updates"   "1 updated"
  assert_out_contains "summary tallies conflicts" "1 conflict"
  assert_out_contains "summary names conflict"    ".claude/agents/code-reviewer.md"
  assert_out_contains "summary suggests force"    "--force"
  teardown_sandbox
}

test_first_upgrade_notes_baseline_adoption() {
  setup_sandbox
  mkdir -p "$TARGET/.claude/agents"
  printf 'mine\n' > "$TARGET/.claude/agents/code-reviewer.md"
  run_install
  assert_out_contains "first run explains adoption" "existing files were recorded as the baseline"
  teardown_sandbox
}

test_update_run_does_not_repeat_baseline_adoption_note() {
  setup_sandbox
  run_install
  printf 'mine new agent\n' > "$TARGET/.claude/agents/new-agent.md"
  printf 'v2 new agent\n'   > "$FIXTURE/.claude/agents/new-agent.md"
  fixture_commit v2
  run_install
  assert_out_contains "update run keeps the newly-adopted file"  "1 kept"
  assert_out_lacks "update run omits baseline adoption note" "existing files were recorded as the baseline"
  teardown_sandbox
}

test_fresh_install_without_kept_files_omits_baseline_note() {
  setup_sandbox
  run_install
  assert_out_lacks "install run with nothing kept omits baseline adoption note" \
    "existing files were recorded as the baseline"
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
test_claude_md_block_updates_preserving_user_content
test_edited_claude_md_block_conflicts
test_claude_md_block_update_preserves_content_before_and_after
test_claude_md_marker_substring_in_prose_is_not_treated_as_marker
test_claude_md_update_preserves_missing_trailing_newline
test_claude_md_missing_end_marker_leaves_file_untouched
test_claude_md_update_preserves_single_trailing_blank_line
test_claude_md_update_preserves_two_trailing_blank_lines
test_claude_md_update_preserves_missing_trailing_newline_when_end_marker_is_last_line
test_mcp_selection_is_reused_on_update
test_mcp_selection_absent_from_state_falls_back_to_default
test_mcp_selection_explicit_empty_is_reused_not_defaulted
test_tool_selection_is_reused_on_update
test_update_summary_tallies_and_lists_conflicts
test_first_upgrade_notes_baseline_adoption
test_update_run_does_not_repeat_baseline_adoption_note
test_fresh_install_without_kept_files_omits_baseline_note
finish
