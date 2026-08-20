---
name: linear-start
description: Start work on a Linear issue. Prompts for the issue ID and target repo, pulls full issue data via the Linear MCP server, creates an isolated git worktree at `.worktrees/<ISSUE>` on a branch named after the issue, saves a structured brief, and hands off to the code-architect (Albus) agent. Trigger whenever the user says "start linear issue", "work on <TEAM-123>", "kick off a linear ticket", "new linear issue", or supplies a Linear issue identifier and asks Claude to begin work. Supports running in parallel across multiple issues via separate worktrees.
---

# linear-start

Kick off work on a Linear issue in an isolated worktree and delegate to the code-architect agent (Albus).

## Preconditions

Check before doing anything else. If any fail, stop and tell the user.

1. **Linear MCP authenticated.** The `mcp__plugin_linear_linear__*` tools must be callable (e.g. `get_issue`, `list_teams`). If not connected, tell the user to run `/plugin` and authenticate the Linear plugin, then re-run the skill.
2. **Target repo is a git repo.** `git -C <repo> rev-parse --is-inside-work-tree` must succeed.
3. **Working tree of the main checkout is clean-ish.** Warn (don't block) on uncommitted changes in the main checkout; worktrees are independent so this is informational.

## Step 1 - Collect inputs

Use `AskUserQuestion` to ask for:

1. **Linear issue identifier** (e.g. `ENG-123`). Free text. Validate format `^[A-Z][A-Z0-9]*-\d+$`.
2. **Target repo absolute path**. Free text. Default to the current working directory if it's a git repo.

Do not guess - always ask, even if an identifier appears elsewhere in context.

## Step 2 - Fetch issue data via Linear MCP

Call `mcp__plugin_linear_linear__get_issue` with the identifier. Also call `mcp__plugin_linear_linear__list_comments` for comments. Gather:

- Title, description (full markdown, not truncated), state (status), priority, estimate
- Labels, team, project, cycle, milestone
- Assignee, creator, created/updated timestamps
- Parent issue, sub-issues (id + title)
- Related/linked issues and their relation type
- Attachments: list titles and URLs (do not download unless needed) - use `mcp__plugin_linear_linear__get_attachment` only if necessary
- Most recent ~10 comments (author, created, body) via `list_comments`
- Canonical Linear URL (the `url` field on the issue)
- Linked git branch name suggestion if Linear provides one (`branchName` field)

If the issue does not exist or the MCP call fails, abort with the error message.

## Step 2.5 - Transition issue to a started state

Move the issue into Linear's `started` workflow category so it shows as in-progress on boards. This runs after fetch and before worktree creation; failures here warn but do not block.

1. Call `mcp__plugin_linear_linear__list_issue_statuses` with the issue's team id (from the issue payload in Step 2).
2. Filter the returned statuses to those where `type === "started"`. Pick the first match.
3. If the issue's current state already has `type === "started"`, skip this step silently.
4. If exactly one started-category status is resolved, update the issue:
   - Call `mcp__plugin_linear_linear__save_issue` with the issue id and the resolved state id.
5. If multiple started-category statuses exist, use `AskUserQuestion` to let the user pick.
6. If no started-category status exists, print a warning ("Could not resolve a 'started' status for team X; leaving issue status untouched") and continue.

Never block worktree creation on a tracker-side failure.

## Step 3 - Normalize into a brief

Render the fetched data into `<repo>/.worktrees/<ISSUE>/.linear-brief.md` with this structure:

```markdown
# <ISSUE>: <Title>

- **State:** ...
- **Priority:** ... | **Estimate:** ...
- **Assignee:** ... | **Creator:** ...
- **Team:** ... | **Project:** ... | **Cycle:** ...
- **Labels:** ...
- **Linear:** <url>

## Description
<full description markdown>

## Parent / Sub-issues
- Parent: <ID> - <title>
- Sub: <ID> - <title>

## Related Issues
- <ID> (<relation>): <title>

## Attachments
- <title> - <url>

## Recent Comments
### <author> - <date>
<body>
...
```

(Write this file AFTER the worktree exists - see Step 4.)

## Step 4 - Create the worktree

1. Ensure `.worktrees/` is ignored: read `<repo>/.gitignore`; if `.worktrees/` is not present, append it on its own line. If `.gitignore` doesn't exist, create it with that single line.
2. Derive the branch name: prefer Linear's suggested `branchName` if present; otherwise use the issue identifier verbatim (e.g. `ENG-123`). If the repo uses lowercase branch conventions (check recent branches via `git -C <repo> branch --format='%(refname:short)' | head -20`), lowercase it.
3. Run: `git -C <repo> worktree add .worktrees/<ISSUE> -b <branch>`.
4. If the branch already exists, ask the user via `AskUserQuestion` whether to (a) reuse it (`git worktree add .worktrees/<ISSUE> <branch>` without `-b`), (b) replace it, or (c) abort.
5. If `.worktrees/<ISSUE>` already exists as a worktree, ask whether to reuse it, remove+recreate, or abort.
6. Now write the brief file from Step 3 into the worktree.

## Step 5 - Delegate to code-architect (Albus)

Invoke the agent via the `Agent` tool:

- `subagent_type: "code-architect"`
- `description`: "Kick off <ISSUE>: <short title>"
- `prompt`: include the full `.linear-brief.md` contents inline, the worktree absolute path, the Linear URL, and an explicit instruction: "Treat `<worktree path>` as your working directory. Follow your normal chain: analyze patterns, design the architecture, delegate implementation to the fullstack-developer (Harry), then hand off to code-reviewer and docs-maintainer as appropriate. Do not modify files outside the worktree."
- Do NOT pass `isolation: worktree` - the worktree we created IS the isolation.

## Step 6 - Report back to the user

Output a short summary:

- Issue: `<ID>` - `<title>` (`<linear url>`)
- Worktree: `<absolute path>`
- Branch: `<branch>`
- Brief: `<worktree>/.linear-brief.md`
- Architect: kicked off (or: finished / handed off to …)

Tell the user they can open a separate Claude session with `cwd=<worktree>` to continue work in parallel with other issues.

## Guardrails

- **Do not start coding yourself.** Your job is Linear fetch → worktree → delegate. Implementation is Albus's chain.
- **Do not edit anything outside `<repo>/.gitignore` and `<worktree>/.linear-brief.md`** during the skill run.
- **Do not download attachments** unless the architect later asks for them.
- **Tracker writes are scoped to a single status transition** (to a `started`-category state). Do not change assignee, description, comments, or any other field on the Linear issue during this skill.
- **Never reuse a dirty worktree silently** - always prompt.

## Parallel issues

This skill makes no assumption of a single active issue. Each run produces an independent `.worktrees/<ID>` on its own branch. Run it as many times as needed; open each worktree in its own Claude session to work on issues concurrently.
