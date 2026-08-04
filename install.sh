#!/usr/bin/env bash
# install.sh — dev-team-pack installer
# Usage: bash install.sh [TARGET_DIR]    (run with --help for full options)
set -euo pipefail

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  cat <<'USAGE'
Usage: bash install.sh [TARGET_DIR]

  TARGET_DIR  Directory to install dev-team-pack into (default: $PWD)

Environment:
  DEV_TEAM_REPO          Git repo URL (default: https://github.com/LeonardM01/dev-team-pack.git)
  DEV_TEAM_REF           Branch / tag / ref to fetch (default: main)
  DEV_TEAM_TOOLS         CSV of tools to install: claude,cursor or all (default: interactive)
  DEV_TEAM_MCPS          CSV of MCP server names to enable, all, or none (default: interactive)
  DEV_TEAM_NONINTERACTIVE  Set to 1 to skip prompts and use defaults (both tools, all MCPs)
  NO_COLOR               Set to disable colors and the banner

Examples:
  bash install.sh
  bash install.sh ~/projects/my-app
  DEV_TEAM_REF=v2.0 bash install.sh ~/projects/my-app
  DEV_TEAM_TOOLS=claude DEV_TEAM_MCPS=context7,lean-ctx bash install.sh ~/projects/my-app
  DEV_TEAM_TOOLS=cursor DEV_TEAM_MCPS=none bash install.sh ~/projects/my-app
  DEV_TEAM_NONINTERACTIVE=1 bash install.sh ~/projects/my-app

Notes:
  - Existing files in TARGET_DIR are never overwritten (existing wins).
  - To change your selection on a re-run, manually delete the relevant files first.
USAGE
  exit 0
fi

REPO_URL="${DEV_TEAM_REPO:-https://github.com/LeonardM01/dev-team-pack.git}"
REF="${DEV_TEAM_REF:-main}"
TARGET="${1:-$PWD}"
WORK=""

SELECTED_TOOLS=""
SELECTED_MCPS=""
MCP_FILTER_MODE="none"
HASH_MODE="none"
PACK_VERSION=""
PACK_VERSION_SOURCE=""

STATE_ENABLED=0
STATE_PRESENT=0
MODE="install"
STATE_VERSION=""
STATE_REF=""
STATE_INSTALLED_AT=""
STATE_TOOLS=""
STATE_MCPS=""
STATE_HAS_TOOLS=0
STATE_HAS_MCPS=0
STATE_SCHEMA_SUPPORTED=1

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
    printf '    %s·%s merge selected tool configs (existing files win)\n' "$C_DIM" "$C_RESET"
    printf '    %s·%s add a filtered .mcp.json\n' "$C_DIM" "$C_RESET"
    printf '    %s·%s run scripts/setup-env.sh (lean-ctx, claude-mem, superpowers)\n' "$C_DIM" "$C_RESET"
    printf '    %s·%s run a stack-analysis pass with Claude CLI (if installed)\n\n' "$C_DIM" "$C_RESET"
    note "Re-runs preserve existing files. To change selection, delete files first."
    printf '\n'
  else
    printf '[dev-team-pack] target: %s\n' "$TARGET"
    printf '[dev-team-pack] source: %s @ %s\n' "$repo_pretty" "$REF"
  fi
}

print_summary() {
  [ -t 1 ] || return 0
  local mcp_count
  mcp_count="$(printf '%s' "$SELECTED_MCPS" | tr ' ' '\n' | grep -c . || true)"
  if [ "$UI_RICH" = "1" ]; then
    printf '%s%s✓ Installation complete%s\n\n' "$C_GREEN" "$C_BOLD" "$C_RESET"
    printf '  %starget%s  %s\n'  "$C_DIM" "$C_RESET" "$TARGET"
    printf '  %sref%s     %s\n' "$C_DIM" "$C_RESET" "$REF"
    printf '  %stools%s   %s\n' "$C_DIM" "$C_RESET" "$SELECTED_TOOLS"
    printf '  %smcps%s    %s (%s enabled)\n\n' "$C_DIM" "$C_RESET" "$SELECTED_MCPS" "$mcp_count"
    printf '  %sNext: restart your shell, then Claude Code and Cursor, to pick up new MCP servers.%s\n\n' "$C_DIM" "$C_RESET"
  else
    printf '[dev-team-pack] Installation complete.\n'
    printf '  target: %s\n' "$TARGET"
    printf '  ref:    %s\n' "$REF"
    printf '  tools:  %s\n' "$SELECTED_TOOLS"
    printf '  mcps:   %s\n' "$SELECTED_MCPS"
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

detect_jq_runtime() {
  if command -v jq >/dev/null 2>&1; then
    MCP_FILTER_MODE=jq
    log "MCP filter: jq"
  elif command -v python3 >/dev/null 2>&1; then
    MCP_FILTER_MODE=python
    log "MCP filter: python3"
  else
    MCP_FILTER_MODE=none
    log "MCP filter: none (jq and python3 unavailable — MCP JSON will be unfiltered)"
  fi
}

detect_hash_runtime() {
  if command -v shasum >/dev/null 2>&1; then
    HASH_MODE=shasum
  elif command -v sha256sum >/dev/null 2>&1; then
    HASH_MODE=sha256sum
  elif command -v python3 >/dev/null 2>&1; then
    HASH_MODE=python
  else
    HASH_MODE=none
  fi
  log "hash: $HASH_MODE"
}

sha256_stdin() {
  case "$HASH_MODE" in
    shasum)    shasum -a 256 | cut -d' ' -f1 ;;
    sha256sum) sha256sum | cut -d' ' -f1 ;;
    python)    python3 -c 'import hashlib,sys;print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())' ;;
    *)         return 1 ;;
  esac
}

sha256_file() {
  [ -f "$1" ] || return 1
  case "$HASH_MODE" in
    shasum)    shasum -a 256 "$1" | cut -d' ' -f1 ;;
    sha256sum) sha256sum "$1" | cut -d' ' -f1 ;;
    python)    python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1" ;;
    *)         return 1 ;;
  esac
}

pack_tree_hash() {
  (
    cd "$WORK/pack" || exit 1
    find . -type f -not -path './.git/*' -print0 \
      | LC_ALL=C sort -z \
      | while IFS= read -r -d '' f; do
          printf '%s:%s\n' "$f" "$(sha256_file "$f")"
        done
  ) | sha256_stdin
}

resolve_pack_version() {
  if [ -d "$WORK/pack/.git" ] && command -v git >/dev/null 2>&1; then
    PACK_VERSION="$(git -C "$WORK/pack" rev-parse HEAD 2>/dev/null || true)"
    if [ -n "$PACK_VERSION" ]; then
      PACK_VERSION_SOURCE=git
      log "pack version $PACK_VERSION (git)"
      return 0
    fi
  fi
  PACK_VERSION="$(pack_tree_hash || true)"
  PACK_VERSION_SOURCE=tree
  if [ -z "$PACK_VERSION" ]; then
    log "hashing unavailable — pack version cannot be computed"
  fi
  log "pack version $PACK_VERSION (tree)"
}

state_path() { printf '%s/.dev-team-pack.json' "$TARGET"; }

detect_state_support() {
  if [ "$HASH_MODE" = "none" ] || ! command -v python3 >/dev/null 2>&1; then
    STATE_ENABLED=0
    log "update detection unavailable (needs a sha256 tool and python3) — existing files always win"
  else
    STATE_ENABLED=1
  fi
}

read_state() {
  : > "$WORK/state_old.tsv"
  : > "$WORK/state_new.tsv"
  [ "$STATE_ENABLED" = "1" ] || return 0

  local sf; sf="$(state_path)"
  [ -f "$sf" ] || return 0

  if ! validate_json "$sf"; then
    die "Corrupt state file: $sf (delete it to reinstall from scratch)"
  fi

  local meta
  meta="$(python3 - "$sf" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
print(d.get("schema", 0))
print(d.get("version", ""))
print(d.get("ref", ""))
print(d.get("installedAt", ""))
print("1" if "tools" in d else "0")
print(" ".join(d.get("tools", [])))
print("1" if "mcps" in d else "0")
print(" ".join(d.get("mcps", [])))
PY
)"

  local schema
  schema="$(printf '%s\n' "$meta" | sed -n 1p)"
  STATE_VERSION="$(printf '%s\n' "$meta" | sed -n 2p)"
  STATE_REF="$(printf '%s\n' "$meta" | sed -n 3p)"
  STATE_INSTALLED_AT="$(printf '%s\n' "$meta" | sed -n 4p)"
  STATE_HAS_TOOLS="$(printf '%s\n' "$meta" | sed -n 5p)"
  STATE_TOOLS="$(printf '%s\n' "$meta" | sed -n 6p)"
  STATE_HAS_MCPS="$(printf '%s\n' "$meta" | sed -n 7p)"
  STATE_MCPS="$(printf '%s\n' "$meta" | sed -n 8p)"

  if [ "${schema:-0}" -gt "$STATE_SCHEMA_SUPPORTED" ]; then
    die "State file schema $schema is newer than this installer supports ($STATE_SCHEMA_SUPPORTED). Update the installer and re-run."
  fi

  python3 - "$sf" <<'PY' > "$WORK/state_old.tsv"
import json, sys
d = json.load(open(sys.argv[1]))
for k, v in d.get("files", {}).items():
    print("%s\t%s" % (k, v))
PY

  STATE_PRESENT=1
  MODE="update"
}

state_hash_for() {
  [ -s "$WORK/state_old.tsv" ] || return 0
  awk -F'\t' -v k="$1" '$1 == k { print $2; exit }' "$WORK/state_old.tsv"
}

record_state_entry() {
  [ -n "${2:-}" ] || return 0
  printf '%s\t%s\n' "$1" "$2" >> "$WORK/state_new.tsv"
}

write_state() {
  if [ "$STATE_ENABLED" != "1" ]; then
    STEP_STATUS=skip
    log "state tracking disabled"
    return 0
  fi

  local sf now installed_at
  sf="$(state_path)"
  now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  installed_at="${STATE_INSTALLED_AT:-$now}"

  python3 - "$sf" "$WORK/state_new.tsv" "$REPO_URL" "$REF" "$PACK_VERSION" \
      "$PACK_VERSION_SOURCE" "$installed_at" "$now" "$SELECTED_TOOLS" "$SELECTED_MCPS" <<'PY'
import json, sys, io

(sf, tsv, repo, ref, version, vsrc, installed_at, now, tools, mcps) = sys.argv[1:11]

files = {}
with io.open(tsv, encoding="utf-8") as fh:
    for line in fh:
        line = line.rstrip("\n")
        if not line:
            continue
        k, _, v = line.partition("\t")
        files[k] = v

state = {
    "schema": 1,
    "repo": repo,
    "ref": ref,
    "version": version,
    "versionSource": vsrc,
    "installedAt": installed_at,
    "updatedAt": now,
    "tools": tools.split(),
    "mcps": mcps.split(),
    "files": dict(sorted(files.items())),
}
with io.open(sf, "w", encoding="utf-8") as fh:
    json.dump(state, fh, indent=2)
    fh.write("\n")
PY

  log "wrote $(basename "$sf")"
}

parse_csv_list() {
  local input="$1"
  local validset="$2"
  local result=""
  local token

  local IFS_OLD="$IFS"
  IFS=','
  for token in $input; do
    IFS="$IFS_OLD"
    token="$(printf '%s' "$token" | tr -d ' ')"
    [ -z "$token" ] && continue

    local found=0
    local v
    for v in $validset; do
      if [ "$token" = "$v" ]; then
        found=1
        break
      fi
    done

    if [ "$found" = "0" ]; then
      die "Invalid selection '$token'. Valid options: $validset"
    fi

    if [ -z "$result" ]; then
      result="$token"
    else
      result="$result $token"
    fi
    IFS=','
  done
  IFS="$IFS_OLD"

  printf '%s' "$result"
}

prompt_multiselect() {
  local title="$1"
  local default_csv="$2"
  shift 2
  local opts="$*"

  if exec 3>/dev/tty 2>/dev/null; then :; else exec 3>&2; fi

  local idx=1
  local opt
  printf '\n' >&3
  if [ "$UI_RICH" = "1" ]; then
    printf '  %s%s%s\n' "$C_BOLD" "$title" "$C_RESET" >&3
  else
    printf '  %s\n' "$title" >&3
  fi

  for opt in $opts; do
    printf '    %s%s)%s %s\n' "$C_CYAN" "$idx" "$C_RESET" "$opt" >&3
    idx=$((idx + 1))
  done
  printf '\n' >&3
  printf '   %s%s%s\n' "$C_DIM" "Enter numbers (e.g. 1,2), a/all, n/none, or press Enter for default [$default_csv]" "$C_RESET" >&3
  printf '\n' >&3

  local attempts=0
  local answer result

  while [ "$attempts" -lt 3 ]; do
    attempts=$((attempts + 1))
    if [ "$UI_RICH" = "1" ]; then
      printf '  %s>%s ' "$C_CYAN" "$C_RESET" >&3
    else
      printf '  > ' >&3
    fi

    answer=""
    if read -r answer </dev/tty 2>/dev/null; then
      :
    else
      if [ -z "$answer" ]; then
        printf '%s' "$default_csv"
        return 0
      fi
    fi

    if [ -z "$answer" ]; then
      answer="$default_csv"
    fi

    local lower
    lower="$(printf '%s' "$answer" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz' | tr -d ' ')"

    if [ "$lower" = "a" ] || [ "$lower" = "all" ]; then
      result="$opts"
      printf '%s' "$result"
      return 0
    fi

    if [ "$lower" = "n" ] || [ "$lower" = "none" ]; then
      printf ''
      return 0
    fi

    local opt_array="$opts"
    local num_opts=0
    for opt in $opt_array; do
      num_opts=$((num_opts + 1))
    done

    result=""
    local bad=0
    local IFS_OLD2="$IFS"

    local normalized
    normalized="$(printf '%s' "$answer" | tr ' ' ',')"

    IFS=','
    for token in $normalized; do
      IFS="$IFS_OLD2"
      token="$(printf '%s' "$token" | tr -d ' ')"
      [ -z "$token" ] && continue

      case "$token" in
        ''|*[!0-9]*)
          if printf '%s' " $opts " | grep -q " $token "; then
            if [ -z "$result" ]; then
              result="$token"
            else
              result="$result $token"
            fi
          else
            printf '   %s· Unknown option: %s%s\n' "$C_DIM" "$token" "$C_RESET" >&3
            bad=1
            break
          fi
          ;;
        *)
          if [ "$token" -lt 1 ] || [ "$token" -gt "$num_opts" ]; then
            printf '   %s· Number out of range: %s (valid: 1-%s)%s\n' "$C_DIM" "$token" "$num_opts" "$C_RESET" >&3
            bad=1
            break
          fi
          local picked_idx=0
          local picked=""
          for opt in $opt_array; do
            picked_idx=$((picked_idx + 1))
            if [ "$picked_idx" = "$token" ]; then
              picked="$opt"
              break
            fi
          done
          if [ -z "$result" ]; then
            result="$picked"
          else
            result="$result $picked"
          fi
          ;;
      esac
      IFS=','
    done
    IFS="$IFS_OLD2"

    if [ "$bad" = "0" ]; then
      printf '%s' "$result"
      return 0
    fi

    if [ "$attempts" -lt 3 ]; then
      printf '   %sInvalid input. Please try again (%s attempt(s) remaining).%s\n' "$C_DIM" "$((3 - attempts))" "$C_RESET" >&3
    fi
  done

  die "Too many invalid selections. Aborting."
}

select_tools() {
  local all_tools="claude cursor"

  if [ -n "${DEV_TEAM_TOOLS:-}" ]; then
    local lower_tools
    lower_tools="$(printf '%s' "$DEV_TEAM_TOOLS" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz' | tr -d ' ')"
    if [ "$lower_tools" = "all" ] || [ "$lower_tools" = "*" ]; then
      SELECTED_TOOLS="$all_tools"
    else
      SELECTED_TOOLS="$(parse_csv_list "$DEV_TEAM_TOOLS" "$all_tools")"
    fi
    log "Tools from env: ${SELECTED_TOOLS:-none}"
  elif [ "${DEV_TEAM_NONINTERACTIVE:-}" = "1" ]; then
    SELECTED_TOOLS="$all_tools"
    log "Tools (non-interactive default): $SELECTED_TOOLS"
  elif [ -r /dev/tty ]; then
    SELECTED_TOOLS="$(prompt_multiselect "Which AI tools to install?" "claude,cursor" $all_tools)"
  else
    SELECTED_TOOLS="$all_tools"
    log "no TTY available, using defaults: $SELECTED_TOOLS"
  fi

  [ -n "$SELECTED_TOOLS" ] || die "Select at least one tool to install."
}

select_mcps() {
  local mcp_src="$WORK/pack/.mcp.json"
  local all_mcps=""

  if [ -f "$mcp_src" ]; then
    if [ "$MCP_FILTER_MODE" = "jq" ]; then
      all_mcps="$(jq -r '.mcpServers | keys[]' "$mcp_src" | tr '\n' ' ' | sed 's/ *$//')"
    elif [ "$MCP_FILTER_MODE" = "python" ]; then
      all_mcps="$(python3 -c "
import json, sys
data = json.load(open('$mcp_src'))
print(' '.join(data.get('mcpServers', {}).keys()))
")"
    else
      all_mcps="$(grep '"' "$mcp_src" | grep ':' | sed -E 's/^ *"([^"]+)" *:.*/\1/' | grep -v 'mcpServers' | tr '\n' ' ' | sed 's/ *$//')"
    fi
  fi

  if [ -z "$all_mcps" ]; then
    SELECTED_MCPS=""
    log "No MCP servers found in pack"
    return 0
  fi

  if [ -n "${DEV_TEAM_MCPS:-}" ]; then
    local lower_mcps
    lower_mcps="$(printf '%s' "$DEV_TEAM_MCPS" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz' | tr -d ' ')"
    if [ "$lower_mcps" = "all" ] || [ "$lower_mcps" = "*" ]; then
      SELECTED_MCPS="$all_mcps"
    elif [ "$lower_mcps" = "none" ]; then
      SELECTED_MCPS=""
    else
      SELECTED_MCPS="$(parse_csv_list "$DEV_TEAM_MCPS" "$all_mcps")"
    fi
    log "MCPs from env: ${SELECTED_MCPS:-none}"
    return 0
  fi

  if [ "${DEV_TEAM_NONINTERACTIVE:-}" = "1" ]; then
    SELECTED_MCPS="$all_mcps"
    log "MCPs (non-interactive default): all"
    return 0
  fi

  if [ -r /dev/tty ]; then
    local default_csv
    default_csv="$(printf '%s' "$all_mcps" | tr ' ' ',')"
    SELECTED_MCPS="$(prompt_multiselect "Which MCP servers to enable?" "$default_csv" $all_mcps)"
  else
    SELECTED_MCPS="$all_mcps"
    log "no TTY available, using defaults: all MCPs"
  fi

  log "MCPs selected: ${SELECTED_MCPS:-none}"
}

filter_mcp_json() {
  local src="$1"
  local dest="$2"
  local servers="$3"

  if [ "$MCP_FILTER_MODE" = "jq" ]; then
    local keep_json
    keep_json="$(printf '%s\n' $servers | jq -R . | jq -s .)"
    jq --argjson keep "$keep_json" \
      '.mcpServers |= with_entries(select(.key as $k | $keep | index($k)))' \
      "$src" > "$dest"
  elif [ "$MCP_FILTER_MODE" = "python" ]; then
    python3 - "$src" "$dest" "$servers" <<'PY'
import json, sys
src, dest, selected = sys.argv[1], sys.argv[2], set(sys.argv[3].split())
data = json.load(open(src))
data["mcpServers"] = {k: v for k, v in data.get("mcpServers", {}).items() if k in selected}
json.dump(data, open(dest, "w"), indent=2)
PY
  else
    cp "$src" "$dest"
    return 1
  fi
  return 0
}

filter_claude_settings() {
  local src="$1"
  local dest="$2"
  local servers="$3"

  if [ "$MCP_FILTER_MODE" = "jq" ]; then
    local keep_json
    keep_json="$(printf '%s\n' $servers | jq -R . | jq -s .)"
    jq --argjson keep "$keep_json" \
      '.enabledMcpjsonServers |= if . then [.[] | select(. as $s | $keep | index($s))] else [] end' \
      "$src" > "$dest"
  elif [ "$MCP_FILTER_MODE" = "python" ]; then
    python3 - "$src" "$dest" "$servers" <<'PY'
import json, sys
src, dest, selected = sys.argv[1], sys.argv[2], set(sys.argv[3].split())
data = json.load(open(src))
existing = data.get("enabledMcpjsonServers", [])
data["enabledMcpjsonServers"] = [s for s in existing if s in selected]
json.dump(data, open(dest, "w"), indent=2)
PY
  else
    cp "$src" "$dest"
    return 1
  fi
  return 0
}

validate_json() {
  local f="$1"
  if [ "$MCP_FILTER_MODE" = "jq" ]; then
    jq empty "$f" >/dev/null 2>&1 || return 1
  elif [ "$MCP_FILTER_MODE" = "python" ]; then
    python3 -c "import json; json.load(open('$f'))" >/dev/null 2>&1 || return 1
  fi
  return 0
}

stage_filtered_pack() {
  local mcp_src="$WORK/pack/.mcp.json"
  local cursor_mcp_src="$WORK/pack/.cursor/mcp.json"
  local settings_src="$WORK/pack/.claude/settings.json"

  local servers="${SELECTED_MCPS:-}"

  if [ -f "$mcp_src" ]; then
    local mcp_tmp="$WORK/mcp_filtered.json"

    if [ -z "$servers" ]; then
      if [ "$MCP_FILTER_MODE" = "jq" ]; then
        jq '.mcpServers = {}' "$mcp_src" > "$mcp_tmp"
      elif [ "$MCP_FILTER_MODE" = "python" ]; then
        python3 -c "
import json
data = json.load(open('$mcp_src'))
data['mcpServers'] = {}
json.dump(data, open('$mcp_tmp', 'w'), indent=2)
"
      else
        cp "$mcp_src" "$mcp_tmp"
        STEP_STATUS=warn
        log "Cannot filter MCP JSON (no jq/python3) — full list will be installed"
      fi
    elif ! filter_mcp_json "$mcp_src" "$mcp_tmp" "$servers"; then
      STEP_STATUS=warn
      log "Cannot filter MCP JSON (no jq/python3) — full list will be installed"
    fi

    if [ -f "$mcp_tmp" ]; then
      if ! validate_json "$mcp_tmp"; then
        die "Filtered .mcp.json failed JSON validation"
      fi
      cp "$mcp_tmp" "$mcp_src"
      log "staged .mcp.json (${servers:-none})"
    fi
  fi

  if [ -f "$cursor_mcp_src" ]; then
    local cursor_tmp="$WORK/cursor_mcp_filtered.json"

    if [ -z "$servers" ]; then
      if [ "$MCP_FILTER_MODE" = "jq" ]; then
        jq '.mcpServers = {}' "$cursor_mcp_src" > "$cursor_tmp"
      elif [ "$MCP_FILTER_MODE" = "python" ]; then
        python3 -c "
import json
data = json.load(open('$cursor_mcp_src'))
data['mcpServers'] = {}
json.dump(data, open('$cursor_tmp', 'w'), indent=2)
"
      else
        cp "$cursor_mcp_src" "$cursor_tmp"
      fi
    elif ! filter_mcp_json "$cursor_mcp_src" "$cursor_tmp" "$servers"; then
      cp "$cursor_mcp_src" "$cursor_tmp"
    fi

    if [ -f "$cursor_tmp" ]; then
      if ! validate_json "$cursor_tmp"; then
        die "Filtered .cursor/mcp.json failed JSON validation"
      fi
      cp "$cursor_tmp" "$cursor_mcp_src"
      log "staged .cursor/mcp.json"
    fi
  fi

  if [ -f "$settings_src" ]; then
    local settings_tmp="$WORK/settings_filtered.json"

    if [ -z "$servers" ]; then
      if [ "$MCP_FILTER_MODE" = "jq" ]; then
        jq '.enabledMcpjsonServers = []' "$settings_src" > "$settings_tmp"
      elif [ "$MCP_FILTER_MODE" = "python" ]; then
        python3 -c "
import json
data = json.load(open('$settings_src'))
data['enabledMcpjsonServers'] = []
json.dump(data, open('$settings_tmp', 'w'), indent=2)
"
      else
        cp "$settings_src" "$settings_tmp"
      fi
    elif ! filter_claude_settings "$settings_src" "$settings_tmp" "$servers"; then
      cp "$settings_src" "$settings_tmp"
    fi

    if [ -f "$settings_tmp" ]; then
      if ! validate_json "$settings_tmp"; then
        die "Filtered .claude/settings.json failed JSON validation"
      fi
      cp "$settings_tmp" "$settings_src"
      log "staged .claude/settings.json"
    fi
  fi
}

merge_claude_dir() {
  if ! printf ' %s ' "$SELECTED_TOOLS" | grep -q ' claude '; then
    STEP_STATUS=skip
    log "claude not selected"
    return 0
  fi

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

merge_cursor_dir() {
  if ! printf ' %s ' "$SELECTED_TOOLS" | grep -q ' cursor '; then
    STEP_STATUS=skip
    log "cursor not selected"
    return 0
  fi

  local src_base="$WORK/pack/.cursor"
  if [ ! -d "$src_base" ]; then
    STEP_STATUS=skip
    log "no .cursor/ in pack"
    return 0
  fi

  local added=0 kept=0

  while IFS= read -r -d '' src_file; do
    local rel="${src_file#"$src_base/"}"
    local dest="$TARGET/.cursor/$rel"
    if [ -f "$dest" ]; then
      kept=$((kept + 1))
    else
      mkdir -p "$(dirname "$dest")"
      cp "$src_file" "$dest"
      added=$((added + 1))
    fi
  done < <(find "$src_base" -type f -print0)

  log "added $added · existing kept $kept"
  [ "$added" -gt 0 ] || STEP_STATUS=skip
}

merge_claude_md() {
  if ! printf ' %s ' "$SELECTED_TOOLS" | grep -q ' claude '; then
    STEP_STATUS=skip
    log "claude not selected"
    return 0
  fi

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
  if ! printf ' %s ' "$SELECTED_TOOLS" | grep -q ' claude '; then
    STEP_STATUS=skip
    log "claude not selected"
    return 0
  fi

  local prompt_file="$WORK/pack/scripts/analyze-prompt.txt"
  [ -f "$prompt_file" ] || { STEP_STATUS=skip; log "no analyze-prompt.txt in pack"; return 0; }

  if ! command -v claude >/dev/null 2>&1; then
    log "Claude CLI not found — install with: npm i -g @anthropic-ai/claude-code"
    STEP_STATUS=skip
    return 0
  fi

  local extra_args=""
  if claude --help 2>&1 | grep -q "permission-mode"; then
    extra_args="--permission-mode acceptEdits"
  fi

  local prompt_content
  prompt_content="$(cat "$prompt_file")"

  (cd "$TARGET" && claude -p "$prompt_content" --add-dir "$TARGET" $extra_args) || STEP_STATUS=warn
}

main() {
  banner
  require_target_writable
  preamble

  divider "fetch"
  make_workdir
  step "Fetch pack from GitHub"  fetch_pack

  divider "select"
  detect_jq_runtime
  detect_hash_runtime
  resolve_pack_version
  detect_state_support
  read_state
  select_tools
  select_mcps

  if [ "$UI_RICH" = "1" ]; then
    printf '\n'
    note "Installing tools: ${SELECTED_TOOLS}"
    local mcp_display="${SELECTED_MCPS:-none}"
    note "Enabling MCPs:    ${mcp_display}"
    printf '\n'
  else
    printf '[dev-team-pack] tools: %s\n' "$SELECTED_TOOLS"
    printf '[dev-team-pack] mcps: %s\n' "${SELECTED_MCPS:-none}"
  fi

  divider "merge"
  step "Stage filtered pack"     stage_filtered_pack
  step "Merge .claude/ config"   merge_claude_dir
  step "Merge .cursor/ config"   merge_cursor_dir
  step "Install .mcp.json"       copy_mcp_json
  step "Update CLAUDE.md"        merge_claude_md

  divider "hooks"
  step "Run environment setup"   run_env_setup
  step "Run stack analysis"      run_analysis

  step "Record install state"    write_state

  print_summary
}

main
