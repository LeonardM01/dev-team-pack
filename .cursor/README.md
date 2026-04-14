# .cursor/ — generated files

> **Do not edit these files by hand.**
> They are generated from `.claude/` by `scripts/sync-cursor.mjs`.
> After editing any `.claude/agents/*.md` or `.mcp.json`, run:
>
>     node scripts/sync-cursor.mjs
>
> Then commit the regenerated `.cursor/` files alongside the `.claude/` changes.

## What's here

| File | Source |
|------|--------|
| `mcp.json` | `.mcp.json` (byte-identical copy) |
| `rules/albus-architect.mdc` | `.claude/agents/code-architect.md` |
| `rules/harry-developer.mdc` | `.claude/agents/fullstack-developer.md` |
| `rules/hermione-reviewer.mdc` | `.claude/agents/code-reviewer.md` |
| `rules/ron-docs.mdc` | `.claude/agents/docs-maintainer.md` |
| `rules/jira-start.mdc` | `.claude/skills/jira-start/SKILL.md` |

## MCP server approval

On first open, Cursor will prompt you to approve MCP servers from `mcp.json`.
Approve all four: **context7**, **figma**, **playwright**, **atlassian**.
Set `FIGMA_API_KEY` in your environment if you use the Figma server.
