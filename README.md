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
2. **Prompts you to select AI tool targets** (`claude`, `cursor`, or both) and **which MCP servers** to enable (any subset of `context7`, `figma`, `playwright`, `atlassian`, `linear`, `lean-ctx`, `XcodeBuildMCP`). Only the selected targets and servers are installed. Use env vars (see Configuration) to skip prompts entirely.
3. Copies `.claude/` (agents, skills, settings) into the project for the selected tool targets. `agent-memory/` is always preserved. Files already in the project that this pack did not write are left alone; see [Updating](#updating) for what happens to pack files on a re-run.
4. Copies `.mcp.json` to the project root containing only the selected MCP servers. On a re-run it is updated, kept or reported as a conflict like any other pack file — see [Updating](#updating).
5. Appends the pack's `CLAUDE.md` to the project's `CLAUDE.md`, wrapped in `<!-- dev-team-pack:begin -->` / `<!-- dev-team-pack:end -->` markers. On a re-run the block is updated in place if you haven't edited it, or reported as a conflict if you have — see [Updating](#updating).
6. Runs `scripts/setup-env.sh` to install/verify the global tool stack: `lean-ctx`, `claude-mem`, and the Superpowers Claude Code plugin.
7. If the `claude` CLI is installed, runs a one-shot analysis that detects the project's tech stack and rewrites the Tech Stack + Commands sections of the dev-team block in `CLAUDE.md` to reflect the actual `package.json` scripts (or equivalent).

## Updating

Re-run the installer to pick up pack changes:

```bash
bash install.sh
```

The installer records what it wrote in `.dev-team-pack.json`. On a re-run it:

- exits immediately if you already have the fetched version
- updates pack files you have not edited
- keeps files you have edited, and reports them as conflicts if upstream
  also changed them
- never touches files it did not write in the first place
- reuses the tool and MCP selection from your last run

| Flag | Effect |
| --- | --- |
| `--force` | Reinstall even if up to date; overwrite conflicting files |
| `--reconfigure` | Re-open the tool and MCP prompts, and skip the up-to-date early exit |

Environment equivalents: `DEV_TEAM_FORCE=1` and `DEV_TEAM_RECONFIGURE=1`.

A run that leaves a conflict records it in `.dev-team-pack.json`, and every
later run re-lists it — including runs that are otherwise up to date — until
you resolve it by hand or with `--force`.

**Resetting the baseline.** `--force` overwrites *conflicts*, but it will not
adopt a file the installer never wrote: untracked files are always left alone
by design. If you want the installer to take ownership of a file it is
currently ignoring, delete `.dev-team-pack.json` and re-run. The next run
records everything on disk as the new baseline.

Windows uses `-Force` and `-Reconfigure` on `install.ps1`. `install.ps1` implements a
subset of `install.sh` and has no tool or MCP selection prompts at all, so
`-Reconfigure` is accepted but is currently a no-op there.

> **Do not alternate the two installers against the same target with a
> non-default MCP selection.** `install.ps1` has no MCP filtering, so it always
> installs the full server list. If `install.sh` installed a filtered
> `.mcp.json`, `.cursor/mcp.json` or `.claude/settings.json`, each installer
> will see the other's version as an upstream change and rewrite it on every
> run. With the default (all servers) selection the two agree and can be
> alternated safely. `install.ps1` also has no `.cursor/` merge: it preserves
> the `.cursor/*` entries a bash run recorded, but only `install.sh` updates
> those files.

Commit `.dev-team-pack.json` so everyone on the team shares the same baseline.

**On your first re-run after upgrading to an installer that supports this,**
your current files become the recorded baseline — including any customizations.
A later update may overwrite them if upstream changes the same file. The install
summary flags how many files were adopted so you can review them.

Update detection needs a sha256 tool (`shasum`, `sha256sum`, or `python3`) and
`python3`. Without them the installer warns once and falls back to preserving
every existing file.

## Configuration

Environment variables control the source and allow non-interactive installs:

| Variable | Default | Purpose |
|---|---|---|
| `DEV_TEAM_REPO` | `https://github.com/LeonardM01/dev-team-pack.git` | Override the source repo |
| `DEV_TEAM_REF` | `main` | Pin to a branch, tag, or commit |
| `DEV_TEAM_TOOLS` | (prompt) | CSV of tool targets to install: `claude`, `cursor`. Use `all` or `*` for both. |
| `DEV_TEAM_MCPS` | (prompt) | CSV of MCP server names to enable. Use `all` or `*` for all 7, `none` for none. |
| `DEV_TEAM_NONINTERACTIVE` | (unset) | Set to `1` to skip all prompts and apply defaults (both tools, all MCPs). |

Recommended: pin to a tag for reproducible installs.

```bash
DEV_TEAM_REF=v1.0.0 curl -fsSL https://dev.leonard.solutions | bash
```

To install only the Claude target with a subset of MCPs non-interactively:

```bash
DEV_TEAM_TOOLS=claude DEV_TEAM_MCPS=context7,lean-ctx curl -fsSL https://dev.leonard.solutions | bash
```

**Interactive prompts:** when run in an interactive shell (or via `curl | bash` with a real TTY), the installer shows menus and reads your selection directly from `/dev/tty`. If there is no TTY and no env vars are set, defaults are applied silently (both tools, all MCPs).

## Requirements

- `git` OR (`curl` or `wget`) for fetching
- `tar` (Windows 10+ ships it; macOS/Linux include it by default)
- `jq` or `python3` for MCP server filtering — if neither is found, all MCPs are installed unfiltered with a warning. Both ship by default on macOS; nearly all Linux distros include `python3`.
- `claude` CLI — optional; install via `npm i -g @anthropic-ai/claude-code`. If missing, files are still copied but the tech-stack analysis step is skipped.
- Windows: `scripts/setup-env.sh` requires WSL or Git Bash. Without them, the installer logs a warning and continues; run `setup-env.sh` manually afterward.

## Idempotency

Re-running the installer is safe. See [Updating](#updating) for exactly what happens to each file on a re-run.

To change your tool target or MCP selection, re-run with `--reconfigure` (`-Reconfigure` on Windows, though it is currently a no-op in `install.ps1`) instead of deleting files. `--reconfigure` also bypasses the up-to-date early exit, so it works even when you already have the latest pack version.

## Security note

Piping a remote script to bash is trust-on-first-use. For security-sensitive environments, pin `DEV_TEAM_REF` to a tag and review the script before running.

## The team

Defined in `.claude/agents/`:

| Agent | Name | Role |
|---|---|---|
| `code-architect` | **Albus** | Analyzes codebase patterns, designs the architecture, breaks work into tasks, and delegates. Model: Opus. |
| `fullstack-developer` | **Harry** | Implements features across DB, API, frontend, and mobile — whatever stack the project uses. Model: Sonnet. |
| `code-reviewer` | Hermione | Reviews diffs for correctness, requirement coverage, edge cases, security. |
| `docs-maintainer` | Ron | Keeps README / CLAUDE.md / docs in sync after code changes. |

Albus is the orchestrator — he delegates implementation to Harry (baseline first, then one task per blueprint phase), hands the diff plus blueprint and requirements to Hermione for review (max 3 rounds, blocker/should-fix/nit severity), then to Ron for docs. He tracks the run in a `PROGRESS.md` scratchpad in the working directory.

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
