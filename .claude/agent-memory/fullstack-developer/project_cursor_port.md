---
name: cursor-port-phase-1
description: Phase 1 of porting the dev-team Claude Code setup to Cursor — sync script and generated .cursor/ files
type: project
---

Phase 1 of Albus's Cursor-port blueprint (plan: humble-weaving-patterson-agent-ab9b0469fd27d65be.md) is complete.

`scripts/sync-cursor.mjs` generates `.cursor/rules/*.mdc` and `.cursor/mcp.json` from `.claude/` sources. The script is idempotent, pure Node >=18, zero deps.

**Why:** Dual-tool repo (Claude Code + Cursor). `.claude/` is canonical; `.cursor/` is a generated mirror so agent definitions stay in one place.

**How to apply:** When touching `.claude/agents/*.md` or `.mcp.json`, always re-run `node scripts/sync-cursor.mjs` and commit the regenerated `.cursor/` files alongside the source changes. Phase 2 (Hermione review) and Phase 3 (Ron README update) remain pending as of 2026-04-14.
