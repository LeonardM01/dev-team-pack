#!/usr/bin/env bash
# setup-env.sh — bootstrap a new dev environment with global tools
# Run: bash scripts/setup-env.sh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✓${NC} $1"; }
warn() { echo -e "${YELLOW}!${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

echo "=== dev-team environment setup ==="
echo ""

# ─── 1. lean-ctx (MCP server + shell compression) ─────────────────────────

if command -v lean-ctx &>/dev/null; then
  ok "lean-ctx already installed: $(lean-ctx --version)"
else
  echo "Installing lean-ctx..."
  if command -v brew &>/dev/null; then
    brew tap yvgude/lean-ctx
    brew install lean-ctx
    ok "lean-ctx installed via Homebrew"
  else
    echo "No Homebrew found. Using universal installer..."
    curl -fsSL https://leanctx.com/install.sh | sh
    ok "lean-ctx installed via curl"
  fi
fi

# Run setup (shell aliases + editor auto-detection)
echo "Running lean-ctx setup (shell hooks + editor config)..."
lean-ctx setup

# Install agent instructions for Claude Code
if command -v claude &>/dev/null; then
  # Add lean-ctx as MCP server for Claude Code (global)
  claude mcp add lean-ctx lean-ctx 2>/dev/null || warn "lean-ctx MCP already configured for Claude Code"
  # Install agent instructions (CLAUDE.md, AGENTS.md)
  lean-ctx init --agent claude
  ok "lean-ctx configured for Claude Code"
else
  warn "Claude Code CLI not found — skipping Claude-specific config. Install from https://claude.ai/code"
fi

# Install agent instructions for Cursor
lean-ctx init --agent cursor
ok "lean-ctx configured for Cursor"

# ─── 2. claude-mem (persistent memory plugin) ─────────────────────────────

echo ""
echo "Installing claude-mem..."
if [ -d "$HOME/.claude/plugins/marketplaces/thedotmack" ]; then
  ok "claude-mem already installed"
else
  npx claude-mem install
  ok "claude-mem installed"
fi

# ─── 3. Verify ────────────────────────────────────────────────────────────

echo ""
echo "=== Verification ==="

command -v lean-ctx &>/dev/null && ok "lean-ctx: $(lean-ctx --version)" || fail "lean-ctx not in PATH"
command -v claude &>/dev/null  && ok "Claude Code CLI: $(claude --version 2>/dev/null || echo 'installed')" || warn "Claude Code CLI not found"

echo ""
echo "Running lean-ctx doctor..."
lean-ctx doctor || true

echo ""
echo "=== Setup complete ==="
echo ""
echo "Next steps:"
echo "  1. Restart your shell:  source ~/.zshrc"
echo "  2. Restart Claude Code and Cursor to pick up new MCP servers"
echo "  3. In any project, run: lean-ctx init --agent claude && lean-ctx init --agent cursor"
