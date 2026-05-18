# dev-team

A Claude Code "virtual team" for driving Jira tickets end-to-end: Jira fetch → isolated git worktree → architect → developer → reviewer → docs. Each ticket runs in its own worktree so you can work several in parallel.

**Works in both Claude Code and Cursor.**

## Install / Quick Start

Run from inside the target project's directory.

```bash
# macOS / Linux (curl)
curl -fsSL https://dev.leonard.solutions | bash

# macOS / Linux (wget)
wget -qO- https://dev.leonard.solutions | bash
```

```powershell
# Windows (PowerShell)
iwr -useb https://raw.githubusercontent.com/LeonardM01/dev-team-pack/main/install.ps1 | iex
```

`cd` into your project first — the script operates on the current working directory.

## What it does

1. Clones dev-team-pack into a temp directory (shallow `git clone`; falls back to the GitHub codeload tarball if `git` is not available).
2. Copies `.claude/` (agents, skills, settings) into the project. **Existing files are never overwritten.** `agent-memory/` is always preserved.
3. Copies `.mcp.json` to the project root (skipped if one already exists).
4. Appends the pack's `CLAUDE.md` to the project's `CLAUDE.md`, wrapped in `<!-- dev-team-pack:begin -->` / `<!-- dev-team-pack:end -->` markers. Re-running detects the marker and skips — idempotent.
5. Runs `scripts/setup-env.sh` to install/verify the global tool stack: `lean-ctx`, `claude-mem`, and the Superpowers Claude Code plugin.
6. If the `claude` CLI is installed, runs a one-shot analysis that detects the project's tech stack and rewrites the Tech Stack + Commands sections of the dev-team block in `CLAUDE.md` to reflect the actual `package.json` scripts (or equivalent).

## Configuration

Two environment variables control the source:

| Variable | Default | Purpose |
|---|---|---|
| `DEV_TEAM_REPO` | `https://github.com/LeonardM01/dev-team-pack.git` | Override the source repo |
| `DEV_TEAM_REF` | `main` | Pin to a branch, tag, or commit |

Recommended: pin to a tag for reproducible installs.

```bash
DEV_TEAM_REF=v1.0.0 curl -fsSL https://dev.leonard.solutions | bash
```

## Requirements

- `git` OR (`curl` or `wget`) for fetching
- `tar` (Windows 10+ ships it; macOS/Linux include it by default)
- `claude` CLI — optional; install via `npm i -g @anthropic-ai/claude-code`. If missing, files are still copied but the tech-stack analysis step is skipped.
- Windows: `scripts/setup-env.sh` requires WSL or Git Bash. Without them, the installer logs a warning and continues; run `setup-env.sh` manually afterward.

## Idempotency

Re-running the installer is safe — already-installed files are left untouched. Existing project files always win. To upgrade, remove the dev-team marker block from `CLAUDE.md` (or delete the file) and re-run. This is a known limitation, not a bug.

## Security note

Piping a remote script to bash is trust-on-first-use. For security-sensitive environments, pin `DEV_TEAM_REF` to a tag and review the script before running.

## The team

Defined in `.claude/agents/`:

| Agent | Name | Role |
|---|---|---|
| `code-architect` | **Albus** | Analyzes codebase patterns, designs the architecture, breaks work into tasks, and delegates. Model: Opus. |
| `fullstack-developer` | **Harry** | Implements features across DB, API, and frontend. Model: Sonnet. |
| `code-reviewer` | Hermione | Reviews diffs for correctness, edge cases, security. |
| `docs-maintainer` | Ron | Keeps README / CLAUDE.md / docs in sync after code changes. |

Albus is the orchestrator — he delegates implementation to Harry, then hands the diff to Hermione for review and to Ron for docs.

Each agent has its own persistent memory under `.claude/agent-memory/<agent>/` (versioned, shared with the team).

## The `jira-start` skill

`.claude/skills/jira-start/SKILL.md` is the entry point. It:

1. Asks you for a **Jira ticket key** (e.g. `PROJ-123`) and a **target repo path**.
2. Fetches the full ticket via the **Atlassian MCP server** — description, acceptance criteria, linked issues, sub-tasks, recent comments, attachments.
3. Creates a git worktree at `<repo>/.worktrees/<TICKET>` on a branch named after the ticket (adding `.worktrees/` to `.gitignore` if missing).
4. Writes a normalized brief to `<worktree>/.jira-brief.md`.
5. Delegates to **Albus** (`code-architect`) with the brief and worktree path. Albus then runs the normal chain: design → Harry implements → Hermione reviews → Ron updates docs.

## Prerequisites

- Claude Code installed.
- Atlassian MCP server configured and authenticated (`/mcp` inside Claude Code).
- Target project is a git repo.

## MCP servers (project-scoped)

`.mcp.json` at the project root enables four MCP servers automatically for anyone who opens this repo in Claude Code:

| Server | Purpose |
|---|---|
| **context7** | Up-to-date library / framework / SDK docs (prefer over web search for API questions). |
| **figma** | Read/write Figma designs, generate code from frames, Code Connect mappings. Requires `FIGMA_API_KEY` in env. |
| **playwright** | Drive a real browser for end-to-end tests and UI verification. |
| **atlassian** | Read Jira tickets (used by the `jira-start` skill). OAuth on first connect. |
| **linear** | Read Linear issues (used by the `linear-start` skill). OAuth on first connect. |

They're pre-approved via `.claude/settings.json` (`enabledMcpjsonServers`). On first launch, run `/mcp` to confirm all five are connected. Set `FIGMA_API_KEY` in your shell before launching Claude Code if you use the Figma server.

## The `linear-start` skill

Same flow as `jira-start`, but sourced from Linear via the Linear MCP server. Entry point: `.claude/skills/linear-start/SKILL.md`. Trigger with `/linear-start` (or phrases like "work on ENG-123"). Produces `<worktree>/.linear-brief.md` and hands off to Albus.

## Usage

In Claude Code:

```
/jira-start       # Jira ticket
/linear-start     # Linear issue
```

Answer the two prompts (issue ID + repo path). The skill does the rest and hands control to Albus.

## Using this repo in Cursor

- Install [Cursor](https://cursor.sh).
- On first open, Cursor will prompt to approve MCP servers from `.cursor/mcp.json` — approve all five (`context7`, `figma`, `playwright`, `atlassian`, `linear`).
- Set `FIGMA_API_KEY` in your environment if you use the Figma server.
- Trigger the team: type `@albus-architect` for a direct kickoff, or `@jira-start` to run the Jira flow.
- **Persona switching**: Cursor has no subagent primitive, so Albus explicitly "switches persona" mid-session by loading the next rule. This is intentional — follow the agent's announcements to know which persona is currently active.
- **Parallel tickets**: open each `.worktrees/<KEY>` as a separate Cursor window (File → Open Folder).

### Keeping Cursor files in sync

`.cursor/rules/*.mdc` and `.cursor/mcp.json` are **generated** from `.claude/` by `scripts/sync-cursor.mjs`. Do not edit them by hand.

After editing any `.claude/agents/*.md` or `.mcp.json`, regenerate:

```bash
node scripts/sync-cursor.mjs
```

Commit the regenerated `.cursor/` files alongside the `.claude/` changes.

## Working multiple tickets in parallel

Each run creates an independent `.worktrees/<KEY>` folder on its own branch. To work tickets concurrently, open a **new Claude Code session** with its working directory set to that worktree:

```bash
cd /path/to/repo/.worktrees/PROJ-123
claude
```

Sessions are isolated by worktree — no branch switching, no conflicts, no stepping on each other.

## Finishing a ticket

When Albus reports the chain is done:

```bash
cd /path/to/repo/.worktrees/<TICKET>
git push -u origin <branch>
# open a PR, then once merged:
git -C /path/to/repo worktree remove .worktrees/<TICKET>
git -C /path/to/repo branch -D <TICKET>
```

## Layout

```
.claude/
  agents/                         agent definitions (Albus, Harry, Hermione, Ron)
  agent-memory/<agent>/           persistent per-agent memory (versioned)
  skills/jira-start/SKILL.md      the Jira ticket kickoff playbook
  skills/linear-start/SKILL.md    the Linear issue kickoff playbook
.cursor/                          generated — do not edit by hand (run scripts/sync-cursor.mjs)
  mcp.json                        copy of .mcp.json for Cursor's MCP approval flow
  README.md                       notice that these files are generated
  rules/
    albus-architect.mdc           Albus persona rule
    harry-developer.mdc           Harry persona rule
    hermione-reviewer.mdc         Hermione persona rule
    ron-docs.mdc                  Ron persona rule
    jira-start.mdc                jira-start flow adapted for Cursor
    linear-start.mdc              linear-start flow adapted for Cursor
scripts/
  sync-cursor.mjs                 regenerates .cursor/ from .claude/ (idempotent)
```

## Customizing

- **Rename agents** — edit the `You are <Name>, ...` line at the top of each `.claude/agents/*.md`. If you rename an agent file itself, run `node scripts/sync-cursor.mjs` afterward to regenerate the corresponding Cursor rule.
- **Change the worktree location** — edit Step 4 of `.claude/skills/jira-start/SKILL.md`.
- **Swap Jira for another tracker** — replace the Atlassian MCP calls in Step 2 of the skill with your tracker's MCP or CLI.
