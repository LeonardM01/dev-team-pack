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
  assert_out_contains "reports update" "1 updated"
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
  assert_out_contains "conflict reported" "1 conflicts"
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

test_edited_claude_md_block_kept_without_conflict_when_upstream_unchanged() {
  setup_sandbox
  run_install
  perl -0pi -e 's/v1 pack docs/hand edited/' "$TARGET/CLAUDE.md"
  printf 'v2 architect\n' > "$FIXTURE/.claude/agents/code-architect.md"
  fixture_commit v2
  run_install
  if grep -q 'hand edited' "$TARGET/CLAUDE.md"; then
    ok "edited block kept when upstream unchanged"
  else
    fail "edited block kept when upstream unchanged" "block was overwritten"
  fi
  assert_out_lacks "no conflict reported when upstream unchanged" \
    "conflict CLAUDE.md block"
  teardown_sandbox
}

test_force_keeps_edited_claude_md_block_when_upstream_unchanged() {
  setup_sandbox
  run_install
  perl -0pi -e 's/v1 pack docs/hand edited/' "$TARGET/CLAUDE.md"
  printf 'v2 architect\n' > "$FIXTURE/.claude/agents/code-architect.md"
  fixture_commit v2
  run_install --force
  if grep -q 'hand edited' "$TARGET/CLAUDE.md"; then
    ok "force keeps local edit when upstream unchanged"
  else
    fail "force keeps local edit when upstream unchanged" "block was overwritten"
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

run_install_with_tools() {
  local tools="$1"; shift
  DEV_TEAM_REPO="$FIXTURE" DEV_TEAM_REF=main DEV_TEAM_TOOLS="$tools" \
    DEV_TEAM_NONINTERACTIVE=1 NO_COLOR=1 \
    bash "$REPO_ROOT/install.sh" "$TARGET" "$@" >"$SANDBOX/out.txt" 2>&1
  printf '%s' "$?" > "$SANDBOX/exit.txt"
  return 0
}

add_agents_fixture() {
  mkdir -p "$FIXTURE/.agents/skills/tdd/agents" "$FIXTURE/.claude/skills"
  printf 'v1 tdd skill\n' > "$FIXTURE/.agents/skills/tdd/SKILL.md"
  printf 'v1 tdd tests\n' > "$FIXTURE/.agents/skills/tdd/tests.md"
  printf 'v1 openai config\n' > "$FIXTURE/.agents/skills/tdd/agents/openai.yaml"
  ln -s ../../.agents/skills/tdd "$FIXTURE/.claude/skills/tdd"
  fixture_commit agents
}

# A Windows clone with core.symlinks=false checks out .claude/skills/tdd not
# as a symlink but as a plain text file holding the link target — this is
# what Merge-SkillLinks / merge_skill_links resolve, and what the F3
# skill-link predicate must classify as a link even though `[ -L ... ]` is
# false for it.
add_agents_fixture_winclone() {
  mkdir -p "$FIXTURE/.agents/skills/tdd" "$FIXTURE/.claude/skills"
  printf 'v1 tdd skill\n' > "$FIXTURE/.agents/skills/tdd/SKILL.md"
  printf '../../.agents/skills/tdd' > "$FIXTURE/.claude/skills/tdd"
  fixture_commit agents-winclone
}

test_fresh_install_adds_agents_dir() {
  setup_sandbox
  add_agents_fixture
  run_install
  assert_file_is "fresh install copies .agents/skills/tdd/SKILL.md" \
    "$TARGET/.agents/skills/tdd/SKILL.md" "v1 tdd skill"
  assert_file_is "fresh install copies .agents/skills/tdd/tests.md" \
    "$TARGET/.agents/skills/tdd/tests.md" "v1 tdd tests"
  if state_keys | grep -qF '.agents/skills/tdd/SKILL.md'; then
    ok ".agents/skills/tdd/SKILL.md recorded in state"
  else
    fail ".agents/skills/tdd/SKILL.md recorded in state" "key missing from state"
  fi
  teardown_sandbox
}

test_fresh_install_materializes_symlinked_skill() {
  setup_sandbox
  add_agents_fixture
  run_install
  assert_file_is "symlinked skill materialized as a real file" \
    "$TARGET/.claude/skills/tdd/SKILL.md" "v1 tdd skill"
  if [ -d "$TARGET/.claude/skills/tdd" ] && [ ! -L "$TARGET/.claude/skills/tdd" ]; then
    ok "materialized skill dir is a real directory, not a symlink"
  else
    fail "materialized skill dir is a real directory, not a symlink" "found a symlink or missing dir"
  fi
  if state_keys | grep -qF '.claude/skills/tdd/SKILL.md'; then
    ok ".claude/skills/tdd/SKILL.md recorded in state"
  else
    fail ".claude/skills/tdd/SKILL.md recorded in state" "key missing from state"
  fi
  teardown_sandbox
}

test_agents_update_propagates_to_both_copies() {
  setup_sandbox
  add_agents_fixture
  run_install
  printf 'v2 tdd skill\n' > "$FIXTURE/.agents/skills/tdd/SKILL.md"
  fixture_commit v2
  run_install
  assert_file_is "update propagates to .agents/ copy" \
    "$TARGET/.agents/skills/tdd/SKILL.md" "v2 tdd skill"
  assert_file_is "update propagates to materialized .claude/skills/ copy" \
    "$TARGET/.claude/skills/tdd/SKILL.md" "v2 tdd skill"
  teardown_sandbox
}

test_agents_conflict_is_reported_not_overwritten() {
  setup_sandbox
  add_agents_fixture
  run_install
  printf 'mine\n' > "$TARGET/.agents/skills/tdd/SKILL.md"
  printf 'v2 tdd skill\n' > "$FIXTURE/.agents/skills/tdd/SKILL.md"
  fixture_commit v2
  run_install
  assert_file_is "conflict preserves local .agents/ edit" \
    "$TARGET/.agents/skills/tdd/SKILL.md" "mine"
  assert_out_contains "conflict reported" "1 conflicts"
  run_install --force
  assert_file_is "force resolves .agents/ conflict" \
    "$TARGET/.agents/skills/tdd/SKILL.md" "v2 tdd skill"
  teardown_sandbox
}

test_agents_deleted_locally_is_not_readded() {
  setup_sandbox
  add_agents_fixture
  run_install
  rm "$TARGET/.agents/skills/tdd/tests.md"
  printf 'v2 tdd skill\n' > "$FIXTURE/.agents/skills/tdd/SKILL.md"
  fixture_commit v2
  run_install
  # This assertion alone passes trivially against pre-fix code too: pre-fix,
  # .agents/ was never installed at all, so the file was never present to
  # begin with. Pin it against the file that IS still present and IS
  # expected to update, so a regression that stops installing .agents/
  # entirely cannot masquerade as "deletion respected".
  assert_file_is "sibling .agents/ file still updated" \
    "$TARGET/.agents/skills/tdd/SKILL.md" "v2 tdd skill"
  assert_file_absent "deleted .agents/ file not resurrected" \
    "$TARGET/.agents/skills/tdd/tests.md"
  teardown_sandbox
}

test_agents_installed_even_when_only_cursor_selected() {
  setup_sandbox
  add_agents_fixture
  run_install_with_tools cursor
  assert_file_is ".agents/ installs even when cursor-only selected" \
    "$TARGET/.agents/skills/tdd/SKILL.md" "v1 tdd skill"
  assert_file_absent "materialized .claude/skills/ not installed when claude deselected" \
    "$TARGET/.claude/skills/tdd"
  teardown_sandbox
}

test_windows_clone_link_text_file_is_not_installed() {
  setup_sandbox
  add_agents_fixture_winclone
  run_install
  assert_file_is ".agents/ still installs on a Windows-clone-style fixture" \
    "$TARGET/.agents/skills/tdd/SKILL.md" "v1 tdd skill"
  if [ -f "$TARGET/.claude/skills/tdd" ] && [ ! -d "$TARGET/.claude/skills/tdd" ]; then
    fail ".claude/skills/tdd is not installed as a raw link-text file" \
      "found a regular file with link-text content instead of a materialized skill"
  else
    ok ".claude/skills/tdd is not installed as a raw link-text file"
  fi
  teardown_sandbox
}

test_windows_clone_materializes_skill_via_merge_skill_links() {
  setup_sandbox
  add_agents_fixture_winclone
  run_install
  assert_file_is "merge_skill_links materializes the Windows-clone skill link" \
    "$TARGET/.claude/skills/tdd/SKILL.md" "v1 tdd skill"
  if [ -d "$TARGET/.claude/skills/tdd" ]; then
    ok "materialized skill dir is a real directory"
  else
    fail "materialized skill dir is a real directory" "not a directory"
  fi
  teardown_sandbox
}

test_genuine_file_at_skills_depth_one_still_installs() {
  setup_sandbox
  mkdir -p "$FIXTURE/.claude/skills"
  printf 'skills index\n' > "$FIXTURE/.claude/skills/README.md"
  fixture_commit skills-readme
  run_install
  assert_file_is "genuine file at .claude/skills/ depth 1 still installs" \
    "$TARGET/.claude/skills/README.md" "skills index"
  teardown_sandbox
}

# SF2: is_skill_link's symlink branch is conditional on the target actually
# resolving to a .agents/skills/<name> link (its sole owner, merge_skill_links,
# can only materialise that shape). A depth-1 symlink pointing anywhere else
# must NOT be claimed by the predicate, so it falls through to
# merge_claude_dir's ordinary `find -L` merge walk instead of vanishing.
test_nonagents_symlink_still_installed_by_merge_walk() {
  setup_sandbox
  mkdir -p "$FIXTURE/.claude/extra-content" "$FIXTURE/.claude/skills"
  printf 'extra content\n' > "$FIXTURE/.claude/extra-content/foo.md"
  ln -s ../extra-content "$FIXTURE/.claude/skills/other"
  fixture_commit nonagents-symlink
  run_install
  assert_file_is "depth-1 symlink outside .agents/skills/ still installs via merge walk" \
    "$TARGET/.claude/skills/other/foo.md" "extra content"
  teardown_sandbox
}

# SF5: no prior test covered a genuine skill directory (not a symlink, not a
# link-text file) at depth 1 alongside a real link and a genuine file. A
# too-greedy subtree skip (e.g. reverting the F3 predicate to a blanket
# `skills/*) continue`) would silently drop the real directory skill and the
# genuine file too, since it's indistinguishable from that failure mode using
# only the link-materialization tests above.
test_mixed_skills_fixture_installs_link_dir_and_readme() {
  setup_sandbox
  add_agents_fixture
  mkdir -p "$FIXTURE/.claude/skills/realdir/sub"
  printf 'nested content\n' > "$FIXTURE/.claude/skills/realdir/sub/nested.md"
  printf 'skills index\n' > "$FIXTURE/.claude/skills/README.md"
  fixture_commit mixed-skills
  run_install
  assert_file_is "mixed fixture: symlinked skill materialized" \
    "$TARGET/.claude/skills/tdd/SKILL.md" "v1 tdd skill"
  assert_file_is "mixed fixture: real directory skill with nested file installed" \
    "$TARGET/.claude/skills/realdir/sub/nested.md" "nested content"
  assert_file_is "mixed fixture: genuine depth-1 README.md installed" \
    "$TARGET/.claude/skills/README.md" "skills index"
  teardown_sandbox
}

test_state_is_superset_when_cursor_deselected() {
  setup_sandbox
  run_install
  local before; before="$(state_keys)"
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install_with_tools claude
  assert_state_superset "narrowing to claude keeps .cursor keys tracked" "$before"

  printf 'v3 rule\n' > "$FIXTURE/.cursor/rules/base.mdc"
  fixture_commit v3
  run_install_with_tools claude,cursor
  assert_file_is "deselected-then-reselected .cursor file still updates" \
    "$TARGET/.cursor/rules/base.mdc" "v3 rule"
  teardown_sandbox
}

test_state_is_superset_when_claude_deselected() {
  setup_sandbox
  run_install
  local before; before="$(state_keys)"
  printf 'v2 rule\n' > "$FIXTURE/.cursor/rules/base.mdc"
  fixture_commit v2
  run_install_with_tools cursor
  assert_state_superset "narrowing to cursor keeps .claude and CLAUDE.md keys tracked" "$before"

  printf 'v3 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  printf 'v3 pack docs\n' > "$FIXTURE/CLAUDE.md"
  fixture_commit v3
  run_install_with_tools claude,cursor
  assert_file_is "deselected-then-reselected .claude file still updates" \
    "$TARGET/.claude/agents/code-reviewer.md" "v3 reviewer"
  if grep -q 'v3 pack docs' "$TARGET/CLAUDE.md"; then
    ok "deselected-then-reselected CLAUDE.md block still updates"
  else
    fail "deselected-then-reselected CLAUDE.md block still updates" "block did not update"
  fi
  teardown_sandbox
}

bom_crlf_state_file() {
  python3 - "$TARGET/.dev-team-pack.json" <<'PY'
import sys
p = sys.argv[1]
data = open(p, 'rb').read()
open(p, 'wb').write(b'\xef\xbb\xbf' + data.replace(b'\n', b'\r\n'))
PY
}

test_state_file_with_bom_and_crlf_is_read() {
  setup_sandbox
  run_install
  bom_crlf_state_file
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_eq "PowerShell-written state file (UTF-8 BOM + CRLF) does not abort install.sh" \
    "$(install_exit_code)" "0"
  assert_out_lacks "no raw python traceback on BOM state file" "Traceback (most recent call last)"
  assert_file_is "update still applies with a BOM state file" \
    "$TARGET/.claude/agents/code-reviewer.md" "v2 reviewer"
  teardown_sandbox
}

test_non_numeric_schema_dies_with_friendly_message() {
  setup_sandbox
  run_install
  python3 -c '
import json, sys
sf = sys.argv[1]
d = json.load(open(sf))
d["schema"] = "one"
json.dump(d, open(sf, "w"), indent=2)
' "$TARGET/.dev-team-pack.json"
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_out_contains "non-numeric schema reports the friendly error" "Corrupt state file"
  # bash 3.2 says "integer expression expected", bash 5.x says "integer
  # expected"; "integer exp" is the only substring common to both. Matching
  # either full wording is vacuous on the other interpreter, and stock macOS
  # /bin/bash is 3.2.
  assert_out_lacks "non-numeric schema does not leak a raw shell error" \
    "integer exp"
  teardown_sandbox
}

test_empty_schema_dies_with_friendly_message() {
  setup_sandbox
  run_install
  python3 -c '
import json, sys
sf = sys.argv[1]
d = json.load(open(sf))
d["schema"] = ""
json.dump(d, open(sf, "w"), indent=2)
' "$TARGET/.dev-team-pack.json"
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_out_contains "empty-string schema reports the friendly error" "Corrupt state file"
  assert_out_lacks "empty-string schema does not leak a raw shell error" \
    "integer exp"
  teardown_sandbox
}

test_absent_schema_key_is_accepted() {
  setup_sandbox
  run_install
  python3 -c '
import json, sys
sf = sys.argv[1]
d = json.load(open(sf))
d.pop("schema", None)
json.dump(d, open(sf, "w"), indent=2)
' "$TARGET/.dev-team-pack.json"
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_out_lacks "absent schema key is not treated as corrupt" "Corrupt state file"
  assert_eq "absent schema key still exits 0" "$(install_exit_code)" "0"
  assert_file_is "absent schema key still applies the update" \
    "$TARGET/.claude/agents/code-reviewer.md" "v2 reviewer"
  teardown_sandbox
}

test_up_to_date_run_relists_unresolved_conflicts() {
  setup_sandbox
  run_install
  printf 'mine\n' > "$TARGET/.claude/agents/code-reviewer.md"
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_out_contains "conflict run reports the conflict" "1 conflicts"
  assert_eq "conflict is recorded in state" \
    "$(state_field conflicts)" '[".claude/agents/code-reviewer.md"]'
  run_install
  assert_out_contains "up-to-date run still reports up to date" "Already up to date"
  assert_out_contains "up-to-date run re-lists the unresolved conflict" \
    "conflict: .claude/agents/code-reviewer.md"
  run_install --force
  assert_file_is "force resolves the conflict" \
    "$TARGET/.claude/agents/code-reviewer.md" "v2 reviewer"
  assert_eq "resolved conflict is cleared from state" "$(state_field conflicts)" '[]'
  run_install
  assert_out_lacks "up-to-date run after resolution lists nothing" \
    "Unresolved conflicts from the last run"
  teardown_sandbox
}

test_conflict_in_skipped_step_is_carried_forward() {
  setup_sandbox
  run_install
  printf 'mine\n'    > "$TARGET/.cursor/rules/base.mdc"
  printf 'v2 rule\n' > "$FIXTURE/.cursor/rules/base.mdc"
  fixture_commit v2
  run_install
  assert_eq "cursor conflict is recorded" \
    "$(state_field conflicts)" '[".cursor/rules/base.mdc"]'

  printf 'v3 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v3
  run_install_with_tools claude
  assert_eq "conflict from the skipped cursor step survives in state" \
    "$(state_field conflicts)" '[".cursor/rules/base.mdc"]'
  assert_file_is "the carried-forward conflict is still the local version" \
    "$TARGET/.cursor/rules/base.mdc" "mine"

  run_install_with_tools claude
  assert_out_contains "up-to-date run after the skipped step still lists the conflict" \
    "conflict: .cursor/rules/base.mdc"
  teardown_sandbox
}

test_conflicting_path_with_a_space_round_trips() {
  setup_sandbox
  printf 'v1 spaced\n' > "$FIXTURE/.claude/agents/my agent.md"
  fixture_commit v1-spaced
  run_install
  printf 'mine\n'      > "$TARGET/.claude/agents/my agent.md"
  printf 'v2 spaced\n' > "$FIXTURE/.claude/agents/my agent.md"
  fixture_commit v2-spaced
  run_install
  assert_eq "conflicting path with a space is one state entry" \
    "$(state_field conflicts)" '[".claude/agents/my agent.md"]'
  run_install
  assert_out_contains "up-to-date run re-lists the spaced path intact" \
    "conflict: .claude/agents/my agent.md"
  teardown_sandbox
}

test_conflict_resolved_by_local_revert_is_dropped() {
  setup_sandbox
  run_install
  printf 'mine\n'        > "$TARGET/.claude/agents/code-reviewer.md"
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_eq "conflict recorded before the revert" \
    "$(state_field conflicts)" '[".claude/agents/code-reviewer.md"]'

  printf 'v1 reviewer\n' > "$TARGET/.claude/agents/code-reviewer.md"
  printf 'v3 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v3
  run_install
  assert_file_is "reverted file takes the upstream update" \
    "$TARGET/.claude/agents/code-reviewer.md" "v3 reviewer"
  assert_eq "conflict resolved by local revert is dropped from state" \
    "$(state_field conflicts)" '[]'
  run_install
  assert_out_lacks "up-to-date run does not re-list the resolved conflict" \
    "conflict: .claude/agents/code-reviewer.md"
  teardown_sandbox
}

test_conflict_resolved_by_upstream_revert_is_dropped() {
  setup_sandbox
  run_install
  printf 'mine\n'        > "$TARGET/.claude/agents/code-reviewer.md"
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_eq "conflict recorded before upstream reverts" \
    "$(state_field conflicts)" '[".claude/agents/code-reviewer.md"]'

  printf 'v1 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  printf 'v3 architect\n' > "$FIXTURE/.claude/agents/code-architect.md"
  fixture_commit v3
  run_install
  assert_file_is "upstream revert leaves the local edit in place" \
    "$TARGET/.claude/agents/code-reviewer.md" "mine"
  assert_eq "conflict resolved by upstream revert is dropped from state" \
    "$(state_field conflicts)" '[]'
  teardown_sandbox
}

test_clean_update_omits_conflict_section() {
  setup_sandbox
  run_install
  printf 'v2 reviewer\n' > "$FIXTURE/.claude/agents/code-reviewer.md"
  fixture_commit v2
  run_install
  assert_out_contains "clean update reports zero conflicts" "0 conflicts"
  assert_out_lacks "clean update omits the conflict list heading" "conflict:"
  assert_out_lacks "clean update omits the force hint" \
    "Re-run with --force to overwrite conflicts."
  teardown_sandbox
}

test_reconfigure_is_not_swallowed_by_up_to_date() {
  setup_sandbox
  run_install_with_tools claude
  run_install_with_tools claude,cursor --reconfigure
  assert_out_lacks "--reconfigure bypasses the up-to-date early exit" "Already up to date"
  assert_file_is "--reconfigure applies the widened tool selection" \
    "$TARGET/.cursor/rules/base.mdc" "v1 rule"
  teardown_sandbox
}

test_unfiltered_json_keeps_pack_bytes() {
  setup_sandbox
  run_install
  assert_files_identical "all MCPs selected leaves .mcp.json byte-identical to the pack" \
    "$TARGET/.mcp.json" "$FIXTURE/.mcp.json"
  assert_files_identical "all MCPs selected leaves .claude/settings.json byte-identical to the pack" \
    "$TARGET/.claude/settings.json" "$FIXTURE/.claude/settings.json"
  run_install
  assert_out_contains "second run over unfiltered JSON is up to date, not an endless update" \
    "Already up to date"
  teardown_sandbox
}

test_subset_selection_still_filters_mcp_json() {
  setup_sandbox
  DEV_TEAM_REPO="$FIXTURE" DEV_TEAM_REF=main DEV_TEAM_MCPS=context7 NO_COLOR=1 \
    bash "$REPO_ROOT/install.sh" "$TARGET" >"$SANDBOX/out.txt" 2>&1
  if grep -q 'lean-ctx' "$TARGET/.mcp.json"; then
    fail "subset selection still filters .mcp.json" "deselected server survived filtering"
  else
    ok "subset selection still filters .mcp.json"
  fi
  if grep -q 'lean-ctx' "$TARGET/.claude/settings.json"; then
    fail "subset selection still filters .claude/settings.json" "deselected server survived filtering"
  else
    ok "subset selection still filters .claude/settings.json"
  fi
  teardown_sandbox
}

printf 'install-update tests\n'
test_unfiltered_json_keeps_pack_bytes
test_subset_selection_still_filters_mcp_json
test_up_to_date_run_relists_unresolved_conflicts
test_conflict_in_skipped_step_is_carried_forward
test_conflicting_path_with_a_space_round_trips
test_conflict_resolved_by_local_revert_is_dropped
test_conflict_resolved_by_upstream_revert_is_dropped
test_clean_update_omits_conflict_section
test_reconfigure_is_not_swallowed_by_up_to_date
test_state_file_with_bom_and_crlf_is_read
test_non_numeric_schema_dies_with_friendly_message
test_empty_schema_dies_with_friendly_message
test_absent_schema_key_is_accepted
test_state_is_superset_when_cursor_deselected
test_state_is_superset_when_claude_deselected
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
test_edited_claude_md_block_kept_without_conflict_when_upstream_unchanged
test_force_keeps_edited_claude_md_block_when_upstream_unchanged
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
test_fresh_install_adds_agents_dir
test_fresh_install_materializes_symlinked_skill
test_agents_update_propagates_to_both_copies
test_agents_conflict_is_reported_not_overwritten
test_agents_deleted_locally_is_not_readded
test_agents_installed_even_when_only_cursor_selected
test_windows_clone_link_text_file_is_not_installed
test_windows_clone_materializes_skill_via_merge_skill_links
test_genuine_file_at_skills_depth_one_still_installs
test_nonagents_symlink_still_installed_by_merge_walk
test_mixed_skills_fixture_installs_link_dir_and_readme
finish
