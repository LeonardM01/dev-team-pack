#!/usr/bin/env bash
# Usage:
#   bash install.sh [TARGET_DIR]
#
#   TARGET_DIR  Directory to install dev-team-pack into (default: current directory)
#
#   Environment variables:
#     DEV_TEAM_REPO   Git repo URL (default: https://github.com/LeonardM01/dev-team-pack.git)
#     DEV_TEAM_REF    Branch/tag/ref to fetch (default: main)
#
#   Examples:
#     bash install.sh
#     bash install.sh ~/projects/my-app
#     DEV_TEAM_REF=v2.0 bash install.sh ~/projects/my-app

set -euo pipefail

REPO_URL="${DEV_TEAM_REPO:-https://github.com/LeonardM01/dev-team-pack.git}"
REF="${DEV_TEAM_REF:-main}"
TARGET="${1:-$PWD}"
WORK=""

log() {
  printf '[dev-team-pack] %s\n' "$*"
}

die() {
  printf '[dev-team-pack] ERROR: %s\n' "$*" >&2
  exit 1
}

require_target_writable() {
  mkdir -p "$TARGET"
  [ -w "$TARGET" ] || die "Target directory is not writable: $TARGET"
}

print_summary() {
  [ -t 1 ] || return 0
  printf '\n[dev-team-pack] Installation complete.\n'
  printf '  Target : %s\n' "$TARGET"
  printf '  Repo   : %s\n' "$REPO_URL"
  printf '  Ref    : %s\n' "$REF"
}

make_workdir() {
  cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
  trap cleanup EXIT INT TERM HUP
  WORK="$(mktemp -d)"
}

fetch_pack() {
  local has_git has_curl has_wget

  has_git=0
  has_curl=0
  has_wget=0

  command -v git  >/dev/null 2>&1 && has_git=1
  command -v curl >/dev/null 2>&1 && has_curl=1
  command -v wget >/dev/null 2>&1 && has_wget=1

  if [ "$has_git" = "1" ]; then
    local clone_err
    if clone_err="$(git clone --depth 1 --branch "$REF" "$REPO_URL" "$WORK/pack" 2>&1)"; then
      return 0
    fi
    log "git clone failed, falling back to tarball:"
    printf '%s\n' "$clone_err" >&2
  fi

  local slug
  case "$REPO_URL" in
    https://github.com/*|http://github.com/*) ;;
    *) die "DEV_TEAM_REPO must be a github.com URL when git is unavailable: $REPO_URL" ;;
  esac
  slug="$(printf '%s' "$REPO_URL" | sed -E 's#^https?://github\.com/##; s#\.git$##')"
  case "$slug" in
    */*)  ;;
    *) die "DEV_TEAM_REPO must be a github.com URL when git is unavailable: $REPO_URL" ;;
  esac

  local tarball_base="https://codeload.github.com/${slug}/tar.gz"

  _try_tarball() {
    local url="$1"
    if [ "$has_curl" = "1" ]; then
      curl -fsSL "$url" | tar -xz -C "$WORK" && return 0
    elif [ "$has_wget" = "1" ]; then
      wget -qO- "$url" | tar -xz -C "$WORK" && return 0
    fi
    return 1
  }

  if ! _try_tarball "${tarball_base}/refs/heads/${REF}"; then
    if ! _try_tarball "${tarball_base}/refs/tags/${REF}"; then
      if [ "$has_curl" = "0" ] && [ "$has_wget" = "0" ]; then
        die "No download tool found. Install git and curl (or wget), then re-run."
      fi
      die "ref $REF not found on $REPO_URL (tried refs/heads and refs/tags)"
    fi
  fi

  local extracted
  extracted="$(ls -d "$WORK"/dev-team-pack-* 2>/dev/null | head -1)"
  [ -n "$extracted" ] || die "Could not find extracted pack directory in $WORK"
  mv "$extracted" "$WORK/pack"
}

merge_claude_dir() {
  local src_base="$WORK/pack/.claude"
  [ -d "$src_base" ] || return 0

  while IFS= read -r -d '' src_file; do
    local rel="${src_file#"$src_base/"}"

    case "$rel" in
      agent-memory/*) continue ;;
    esac

    if [ "$(basename "$rel")" = "settings.local.json" ] && [ -f "$TARGET/.claude/settings.local.json" ]; then
      log "skip .claude/$rel (local settings preserved)"
      continue
    fi

    local dest="$TARGET/.claude/$rel"

    if [ -f "$dest" ]; then
      log "skip .claude/$rel (existing wins)"
    else
      mkdir -p "$(dirname "$dest")"
      cp "$src_file" "$dest"
      log "add  .claude/$rel"
    fi
  done < <(find "$src_base" -type f -print0)
}

merge_claude_md() {
  local pack_md="$WORK/pack/CLAUDE.md"
  local target_md="$TARGET/CLAUDE.md"
  local begin_marker="<!-- dev-team-pack:begin -->"
  local end_marker="<!-- dev-team-pack:end -->"

  [ -f "$pack_md" ] || return 0

  local block
  block="$(printf '%s\n# Dev Team Pack\n%s\n%s' \
    "$begin_marker" \
    "$(cat "$pack_md")" \
    "$end_marker")"

  if [ ! -f "$target_md" ]; then
    printf '%s\n' "$block" > "$target_md"
    log "add  CLAUDE.md"
    return 0
  fi

  if grep -qxF "$begin_marker" "$target_md"; then
    log "skip CLAUDE.md (dev-team-pack already installed)"
    return 0
  fi

  printf '\n\n---\n\n%s\n' "$block" >> "$target_md"
  log "add  CLAUDE.md (appended dev-team block)"
}

copy_mcp_json() {
  local src="$WORK/pack/.mcp.json"
  local dest="$TARGET/.mcp.json"
  [ -f "$src" ] || return 0
  if [ -f "$dest" ]; then
    log "skip .mcp.json (existing wins)"
  else
    cp "$src" "$dest"
    log "add  .mcp.json"
  fi
}

run_env_setup() {
  local setup_script="$WORK/pack/scripts/setup-env.sh"
  if [ ! -f "$setup_script" ]; then
    log "setup-env.sh not found in pack — skipping"
    return 0
  fi
  log "Running setup-env.sh..."
  (cd "$TARGET" && bash "$setup_script") || log "setup-env.sh failed (non-fatal)"
}

run_analysis() {
  local prompt_file="$WORK/pack/scripts/analyze-prompt.txt"
  [ -f "$prompt_file" ] || return 0

  if ! command -v claude >/dev/null 2>&1; then
    log "Claude CLI not found — skipping stack analysis."
    log "To install: npm i -g @anthropic-ai/claude-code"
    return 0
  fi

  local -a extra_args=()
  if claude --help 2>&1 | grep -q "permission-mode"; then
    extra_args=(--permission-mode acceptEdits)
  fi

  local prompt_content
  prompt_content="$(cat "$prompt_file")"

  log "Running stack analysis with Claude CLI..."
  (cd "$TARGET" && claude -p "$prompt_content" --add-dir "$TARGET" "${extra_args[@]}") || log "Analysis finished with warnings (non-fatal)."
}

main() {
  require_target_writable
  make_workdir
  fetch_pack
  merge_claude_dir
  copy_mcp_json
  merge_claude_md
  run_env_setup
  run_analysis
  print_summary
  log "Done."
}

main
