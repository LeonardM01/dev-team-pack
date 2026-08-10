#!/usr/bin/env bash
# Unit tests for decide_file_action. Run: bash tests/decide.test.sh
. "$(dirname "$0")/lib.sh"

# Source install.sh without running main: DEV_TEAM_SOURCE_ONLY short-circuits it.
DEV_TEAM_SOURCE_ONLY=1 . "$REPO_ROOT/install.sh"

setup_case() {
  WORK="$(mktemp -d)"
  : > "$WORK/state_old.tsv"
  mkdir -p "$WORK/dest" "$WORK/pack"
  HASH_MODE=""
  detect_hash_runtime >/dev/null 2>&1
}

teardown_case() { rm -rf "$WORK"; }

seed_recorded() { printf '%s\t%s\n' "$1" "$2" >> "$WORK/state_old.tsv"; }
hash_of() { printf '%s' "$1" > "$WORK/.h"; sha256_file "$WORK/.h"; }

check() {
  local name="$1" expected="$2"
  local got; got="$(decide_file_action f.md "$WORK/dest/f.md" "$WORK/pack/f.md")"
  assert_eq "$name" "$got" "$expected"
}

test_add() {
  setup_case
  printf 'pack\n' > "$WORK/pack/f.md"
  check "missing + unrecorded -> add" "add"
  teardown_case
}

test_skip_deleted() {
  setup_case
  printf 'pack\n' > "$WORK/pack/f.md"
  seed_recorded f.md "$(hash_of 'old')"
  check "missing + recorded -> skip-deleted" "skip-deleted"
  teardown_case
}

test_keep_untracked() {
  setup_case
  printf 'pack\n' > "$WORK/pack/f.md"
  printf 'mine\n' > "$WORK/dest/f.md"
  check "exists + unrecorded -> keep-untracked" "keep-untracked"
  teardown_case
}

test_current() {
  setup_case
  printf 'same\n' > "$WORK/pack/f.md"
  printf 'same\n' > "$WORK/dest/f.md"
  seed_recorded f.md "$(sha256_file "$WORK/pack/f.md")"
  check "disk==rec, pack==rec -> current" "current"
  teardown_case
}

test_update() {
  setup_case
  printf 'new\n' > "$WORK/pack/f.md"
  printf 'old\n' > "$WORK/dest/f.md"
  seed_recorded f.md "$(sha256_file "$WORK/dest/f.md")"
  check "disk==rec, pack!=rec -> update" "update"
  teardown_case
}

test_keep_local() {
  setup_case
  printf 'old\n'  > "$WORK/pack/f.md"
  printf 'mine\n' > "$WORK/dest/f.md"
  seed_recorded f.md "$(sha256_file "$WORK/pack/f.md")"
  check "disk!=rec, pack==rec -> keep-local" "keep-local"
  teardown_case
}

test_conflict() {
  setup_case
  printf 'new\n'  > "$WORK/pack/f.md"
  printf 'mine\n' > "$WORK/dest/f.md"
  seed_recorded f.md "$(hash_of 'original')"
  check "disk!=rec, pack!=rec -> conflict" "conflict"
  teardown_case
}

printf 'decide_file_action tests\n'
test_add
test_skip_deleted
test_keep_untracked
test_current
test_update
test_keep_local
test_conflict
finish
