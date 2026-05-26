---
name: ship-ticket
description: Finish work on a Linear or Jira ticket. Pushes the current branch, opens a GitHub PR, posts a 3-sentence executive summary plus step-by-step test plan as a comment on the originating ticket, and transitions the ticket into the review status category. Auto-detects Linear vs Jira from the brief file in the worktree. Trigger whenever the user says "ship it", "ship this ticket", "open PR for this ticket", "finish <KEY-123>", or is inside a `.worktrees/<ID>/` directory and indicates work is complete.
---

# ship-ticket

Close the loop on a ticket started via `linear-start` or `jira-start`: push branch → open PR → comment ticket with summary + test plan → transition ticket to review.

## Preconditions

1. **CWD is in a worktree.** The current working directory must be (or be inside) a `.worktrees/<ID>/` directory containing either `.linear-brief.md` or `.jira-brief.md`. The brief file determines the tracker.
2. **`gh` CLI authenticated.** `gh auth status` must succeed and the repo must have a GitHub remote.
3. **Branch has commits ahead of base.** `git rev-list --count <base>..HEAD` must be > 0. Default base is `main`; if `main` does not exist, fall back to `master`.
4. **Working tree clean.** If `git status --porcelain` is non-empty, use `AskUserQuestion` to offer: (a) commit everything with a user-provided message, (b) stash, (c) abort.
5. **Matching tracker MCP authenticated.** Linear path requires `mcp__plugin_linear_linear__*` tools; Jira path requires `mcp__claude_ai_Atlassian_Rovo__*` tools.

If any precondition fails, stop and tell the user what to fix.

## Step 1 — Detect tracker and load brief

1. Locate the brief: search the current worktree root for `.linear-brief.md` or `.jira-brief.md`.
2. Exactly one present → set tracker accordingly.
3. Both present or neither present → use `AskUserQuestion` to ask which tracker (or abort).
4. Parse the brief to extract: issue identifier, title, ticket URL. These appear in the first H1 (`# <ID>: <title>`) and a `**Linear:** <url>` or `**Jira:** <url>` line.

## Step 2 — Push the branch

1. Run `git rev-parse --abbrev-ref --symbolic-full-name @{u}` to detect an upstream.
2. If no upstream: `git push -u origin <current-branch>`.
3. If upstream exists and local is ahead: `git push`.
4. Never use `--force` or `--force-with-lease`.

## Step 3 — Generate summary artifact

Collect inputs by running:

- `git log <base>..HEAD --pretty=format:'%h %s%n%b'`
- `git diff <base>..HEAD --stat`
- `git diff <base>..HEAD` (use as context; do not paste into the comment)
- The brief markdown contents

Produce two pieces of output:

1. **Executive summary** — exactly three sentences:
   - Sentence 1: WHAT was changed (in plain language, no jargon).
   - Sentence 2: WHY (tie back to the ticket's stated goal from the brief).
   - Sentence 3: SCOPE / impact (which surfaces or users are affected; explicit non-goals if relevant).
2. **Test plan** — a numbered checklist. Each step must include: setup precondition, the action to perform, and the expected result. Steps must be reproducible by a tester who did not write the code. Derive coverage from the diff: every modified user-facing route, UI screen, CLI command, or schema change gets at least one step.

Show the rendered summary + test plan to the user via `AskUserQuestion` with three options:

- **Post as-is** — proceed to Step 4.
- **Let me edit** — write the text to `.worktrees/<ID>/.ship-summary.md`, instruct the user to edit it in their editor and reply when done, then re-read the file and re-confirm.
- **Cancel** — abort. Do not push to remote a second time, do not create a PR.

## Step 4 — Open the PR

1. Check for an existing PR for this branch: `gh pr view --json url,number 2>/dev/null`.
2. If a PR exists, capture its URL and skip creation. Then use `AskUserQuestion` to ask whether to re-post the ticket comment (default: yes) and whether to re-run the status transition (default: yes).
3. If no PR exists, create one with a minimal body:
   - Title: `<ISSUE>: <title>` (taken from the brief).
   - Body:
     ```
     Ticket: <ticket-url>
     Branch: <branch-name>

     Summary and test plan posted on the ticket.
     ```
   - Command (use HEREDOC for the body):
     ```bash
     gh pr create --base <base> --head <branch> --title "<ISSUE>: <title>" --body "$(cat <<'EOF'
     Ticket: <ticket-url>
     Branch: <branch-name>

     Summary and test plan posted on the ticket.
     EOF
     )"
     ```
4. Capture the resulting PR URL.

## Step 5 — Comment on the ticket

Build the comment body:

```
PR: <pr-url>

## Summary
<3-sentence exec summary from Step 3>

## How to test
1. <test step>
2. <test step>
...
```

Post the comment:

- **Linear path:** `mcp__plugin_linear_linear__save_comment` with the issue id and body.
- **Jira path:** `mcp__claude_ai_Atlassian_Rovo__addCommentToJiraIssue` with the ticket key and body.

If posting fails, surface the error to the user and continue to Step 6 anyway — the transition is still useful on its own.

## Step 6 — Transition ticket to review

**Linear path:**

1. Call `mcp__plugin_linear_linear__list_issue_statuses` for the issue's team.
2. Filter statuses where `type === "review"`. Pick the first match.
3. If already in a review-category state, skip silently.
4. If exactly one match, call `mcp__plugin_linear_linear__save_issue` to set the new state.
5. If multiple matches, prompt via `AskUserQuestion`.
6. If no match, warn and skip.

**Jira path:**

1. Call `mcp__claude_ai_Atlassian_Rovo__getTransitionsForJiraIssue`.
2. Filter to transitions where `to.statusCategory.key === "indeterminate"` AND the transition or target name matches `/review/i`.
3. If exactly one match, call `mcp__claude_ai_Atlassian_Rovo__transitionJiraIssue`.
4. If multiple matches, prompt via `AskUserQuestion` with the candidate list.
5. If no match, warn and skip.

Transition failures never block earlier work — by this point the PR exists and the comment is posted.

## Step 7 — Report

Print a single block to the user:

- **PR:** `<pr-url>`
- **Ticket:** `<ticket-url>` — new status: `<status name>` (or "unchanged" if skipped)
- **Comment posted:** yes / no (with error if no)

## Guardrails

- **Never force-push.**
- **Never edit files outside the worktree.**
- **Idempotent on re-run.** Existing PR is reused; user is asked before re-commenting or re-transitioning.
- **Tracker writes are scoped** to exactly: one comment + one status transition. Nothing else (no field edits, no assignee changes, no attachments).
- **Cancellation is safe.** If the user picks Cancel in Step 3, no PR is created and no ticket write occurs. The branch may already be pushed — that is fine and intentional.
- **Do not run any tests, builds, or formatters.** This skill is purely about shipping the work that already exists on the branch.
