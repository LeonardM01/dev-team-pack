#!/usr/bin/env bash
# install.sh — dev-team-pack installer
# Usage: bash install.sh [TARGET_DIR]    (run with --help for full options)
set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'USAGE'
Usage: bash install.sh [TARGET_DIR]

  TARGET_DIR  Directory to install dev-team-pack into (default: $PWD)

Environment:
  DEV_TEAM_REPO  Git repo URL (default: https://github.com/LeonardM01/dev-team-pack.git)
  DEV_TEAM_REF   Branch / tag / ref to fetch (default: main)
  NO_COLOR       Set to disable colors and the banner

Examples:
  bash install.sh
  bash install.sh ~/projects/my-app
  DEV_TEAM_REF=v2.0 bash install.sh ~/projects/my-app
USAGE
  exit 0
fi

REPO_URL="${DEV_TEAM_REPO:-https://github.com/LeonardM01/dev-team-pack.git}"
REF="${DEV_TEAM_REF:-main}"
TARGET="${1:-$PWD}"
WORK=""

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'
  C_DIM=$'\033[2m'
  C_BOLD=$'\033[1m'
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[0;32m'
  C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[0;31m'
  UI_RICH=1
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_CYAN=""; C_GREEN=""; C_YELLOW=""; C_RED=""
  UI_RICH=0
fi

banner() {
  [ "$UI_RICH" = "1" ] || return 0
  printf '\n%s' "$C_CYAN"
  cat <<'BANNER'
$$$$$$$\                            $$$$$$$$\
$$  __$$\                           \__$$  __|
$$ |  $$ | $$$$$$\ $$\    $$\          $$ | $$$$$$\   $$$$$$\  $$$$$$\$$$$\
$$ |  $$ |$$  __$$\\$$\  $$  |         $$ |$$  __$$\  \____$$\ $$  _$$  _$$\
$$ |  $$ |$$$$$$$$ |\$$\$$  /          $$ |$$$$$$$$ | $$$$$$$ |$$ / $$ / $$ |
$$ |  $$ |$$   ____| \$$$  /           $$ |$$   ____|$$  __$$ |$$ | $$ | $$ |
$$$$$$$  |\$$$$$$$\   \$  /            $$ |\$$$$$$$\ \$$$$$$$ |$$ | $$ | $$ |
\_______/  \_______|   \_/             \__| \_______| \_______|\__| \__| \__|
BANNER
  printf '%s%s                              installer · pack%s\n\n' "$C_RESET" "$C_DIM" "$C_RESET"
}

divider() {
  if [ "$UI_RICH" = "1" ]; then
    printf '%s──── %s ────────────────────────────────────────%s\n' "$C_DIM" "$1" "$C_RESET"
  else
    printf '[dev-team-pack] --- %s ---\n' "$1"
  fi
}

note() { printf '   %s%s%s\n' "$C_DIM" "$*" "$C_RESET"; }

log() {
  if [ "$UI_RICH" = "1" ]; then
    printf '   %s· %s%s\n' "$C_DIM" "$*" "$C_RESET"
  else
    printf '[dev-team-pack]   %s\n' "$*"
  fi
}

die() {
  printf '\n%s✗ %s%s\n' "$C_RED" "$*" "$C_RESET" >&2
  exit 1
}

STEP_STATUS=""

step() {
  local label="$1"; shift
  STEP_STATUS=ok
  if [ "$UI_RICH" = "1" ]; then
    printf '%s→%s %s%s%s\n' "$C_CYAN" "$C_RESET" "$C_BOLD" "$label" "$C_RESET"
  else
    printf '[dev-team-pack] %s\n' "$label"
  fi
  if "$@"; then
    local sym color tag
    case "${STEP_STATUS:-ok}" in
      ok)   sym='✓'; color="$C_GREEN";  tag='done' ;;
      skip) sym='·'; color="$C_DIM";    tag='skipped' ;;
      warn) sym='!'; color="$C_YELLOW"; tag='finished with warnings' ;;
      *)    sym='✓'; color="$C_GREEN";  tag='done' ;;
    esac
    if [ "$UI_RICH" = "1" ]; then
      printf '   %s%s %s%s\n\n' "$color" "$sym" "$tag" "$C_RESET"
    else
      printf '[dev-team-pack]   %s: %s\n' "$label" "$tag"
    fi
  else
    if [ "$UI_RICH" = "1" ]; then
      printf '   %s✗ failed%s\n\n' "$C_RED" "$C_RESET"
    else
      printf '[dev-team-pack]   %s: failed\n' "$label"
    fi
    exit 1
  fi
}

preamble() {
  local repo_pretty
  repo_pretty="$(printf '%s' "$REPO_URL" | sed -E 's#^https?://##; s#\.git$##')"
  if [ "$UI_RICH" = "1" ]; then
    printf '  %starget%s  %s\n'   "$C_DIM" "$C_RESET" "$TARGET"
    printf '  %ssource%s  %s @ %s\n\n' "$C_DIM" "$C_RESET" "$repo_pretty" "$REF"
    printf '  %sThis installer will:%s\n' "$C_DIM" "$C_RESET"
    printf '    %s·%s download the pack into a temp dir\n' "$C_DIM" "$C_RESET"
    printf '    %s·%s merge .claude/ into your target (existing files win)\n' "$C_DIM" "$C_RESET"
    printf '    %s·%s add .mcp.json and a CLAUDE.md block\n' "$C_DIM" "$C_RESET"
    printf '    %s·%s run scripts/setup-env.sh (lean-ctx, claude-mem, superpowers)\n' "$C_DIM" "$C_RESET"
    printf '    %s·%s run a stack-analysis pass with Claude CLI (if installed)\n\n' "$C_DIM" "$C_RESET"
  else
    printf '[dev-team-pack] target: %s\n' "$TARGET"
    printf '[dev-team-pack] source: %s @ %s\n' "$repo_pretty" "$REF"
  fi
}

print_summary() {
  [ -t 1 ] || return 0
  if [ "$UI_RICH" = "1" ]; then
    printf '%s%s✓ Installation complete%s\n\n' "$C_GREEN" "$C_BOLD" "$C_RESET"
    printf '  %starget%s  %s\n'  "$C_DIM" "$C_RESET" "$TARGET"
    printf '  %sref%s     %s\n\n' "$C_DIM" "$C_RESET" "$REF"
    printf '  %sNext: restart your shell, then Claude Code and Cursor, to pick up new MCP servers.%s\n\n' "$C_DIM" "$C_RESET"
  else
    printf '[dev-team-pack] Installation complete.\n'
    printf '  target: %s\n' "$TARGET"
    printf '  ref:    %s\n' "$REF"
  fi
}

require_target_writable() {
  mkdir -p "$TARGET"
  [ -w "$TARGET" ] || die "Target directory is not writable: $TARGET"
}

make_workdir() {
  cleanup() { [ -n "${WORK:-}" ] && rm -rf "$WORK"; }
  trap cleanup EXIT INT TERM HUP
  WORK="$(mktemp -d)"
}

fetch_pack() {
  local has_git=0 has_curl=0 has_wget=0
  command -v git  >/dev/null 2>&1 && has_git=1
  command -v curl >/dev/null 2>&1 && has_curl=1
  command -v wget >/dev/null 2>&1 && has_wget=1

  if [ "$has_git" = "1" ]; then
    local clone_err
    if clone_err="$(git clone --depth 1 --branch "$REF" "$REPO_URL" "$WORK/pack" 2>&1)"; then
      log "cloned $REF via git"
      return 0
    fi
    log "git clone failed, falling back to tarball"
    log "$clone_err"
  fi

  case "$REPO_URL" in
    https://github.com/*|http://github.com/*) ;;
    *) die "DEV_TEAM_REPO must be a github.com URL when git is unavailable: $REPO_URL" ;;
  esac

  local slug
  slug="$(printf '%s' "$REPO_URL" | sed -E 's#^https?://github\.com/##; s#\.git$##')"
  case "$slug" in
    */*) ;;
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
  log "fetched $REF via tarball"
}

merge_claude_dir() {
  local src_base="$WORK/pack/.claude"
  [ -d "$src_base" ] || { STEP_STATUS=skip; log "no .claude/ in pack"; return 0; }

  local added=0 kept=0 preserved=0

  while IFS= read -r -d '' src_file; do
    local rel="${src_file#"$src_base/"}"
    case "$rel" in
      agent-memory/*) continue ;;
    esac

    if [ "$(basename "$rel")" = "settings.local.json" ] && [ -f "$TARGET/.claude/settings.local.json" ]; then
      preserved=$((preserved + 1))
      continue
    fi

    local dest="$TARGET/.claude/$rel"
    if [ -f "$dest" ]; then
      kept=$((kept + 1))
    else
      mkdir -p "$(dirname "$dest")"
      cp "$src_file" "$dest"
      added=$((added + 1))
    fi
  done < <(find "$src_base" -type f -print0)

  log "added $added · existing kept $kept · local settings preserved $preserved"
  [ "$added" -gt 0 ] || STEP_STATUS=skip
}

merge_claude_md() {
  local pack_md="$WORK/pack/CLAUDE.md"
  local target_md="$TARGET/CLAUDE.md"
  local begin_marker="<!-- dev-team-pack:begin -->"
  local end_marker="<!-- dev-team-pack:end -->"

  [ -f "$pack_md" ] || { STEP_STATUS=skip; log "no CLAUDE.md in pack"; return 0; }

  local block
  block="$(printf '%s\n# Dev Team Pack\n%s\n%s' \
    "$begin_marker" "$(cat "$pack_md")" "$end_marker")"

  if [ ! -f "$target_md" ]; then
    printf '%s\n' "$block" > "$target_md"
    log "created CLAUDE.md with dev-team block"
    return 0
  fi

  if grep -qxF "$begin_marker" "$target_md"; then
    log "dev-team-pack block already present"
    STEP_STATUS=skip
    return 0
  fi

  printf '\n\n---\n\n%s\n' "$block" >> "$target_md"
  log "appended dev-team block to existing CLAUDE.md"
}

copy_mcp_json() {
  local src="$WORK/pack/.mcp.json"
  local dest="$TARGET/.mcp.json"
  [ -f "$src" ] || { STEP_STATUS=skip; log "no .mcp.json in pack"; return 0; }
  if [ -f "$dest" ]; then
    log ".mcp.json already exists (existing wins)"
    STEP_STATUS=skip
  else
    cp "$src" "$dest"
    log "wrote .mcp.json"
  fi
}

run_env_setup() {
  local setup_script="$WORK/pack/scripts/setup-env.sh"
  if [ ! -f "$setup_script" ]; then
    STEP_STATUS=skip
    log "setup-env.sh not in pack"
    return 0
  fi
  (cd "$TARGET" && bash "$setup_script") || STEP_STATUS=warn
}

run_analysis() {
  local prompt_file="$WORK/pack/scripts/analyze-prompt.txt"
  [ -f "$prompt_file" ] || { STEP_STATUS=skip; log "no analyze-prompt.txt in pack"; return 0; }

  if ! command -v claude >/dev/null 2>&1; then
    log "Claude CLI not found — install with: npm i -g @anthropic-ai/claude-code"
    STEP_STATUS=skip
    return 0
  fi

  local -a extra_args=()
  if claude --help 2>&1 | grep -q "permission-mode"; then
    extra_args=(--permission-mode acceptEdits)
  fi

  local prompt_content
  prompt_content="$(cat "$prompt_file")"

  (cd "$TARGET" && claude -p "$prompt_content" --add-dir "$TARGET" "${extra_args[@]}") || STEP_STATUS=warn
}

main() {
  banner
  require_target_writable
  preamble

  divider "fetch"
  make_workdir
  step "Fetch pack from GitHub"  fetch_pack

  divider "merge"
  step "Merge .claude/ config"   merge_claude_dir
  step "Install .mcp.json"       copy_mcp_json
  step "Update CLAUDE.md"        merge_claude_md

  divider "hooks"
  step "Run environment setup"   run_env_setup
  step "Run stack analysis"      run_analysis

  print_summary
}

main
