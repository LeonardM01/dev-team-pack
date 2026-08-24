---
name: dispatch-to-albus
description: Turn the current conversation into a written brief and hand it to the code-architect agent (Albus) to execute. Use whenever the user wants Albus to take over work discussed in this session - "send this to Albus", "have Albus fix these", "dispatch this", "let the team handle it" - whether the work is review findings, a bug, a refactor, or a feature. Not for starting from a tracker ticket; that is jira-start / linear-start.
argument-hint: "Optional: what Albus should focus on, if narrower than the whole conversation"
---

Write a brief that a fresh agent can act on without this conversation, save it in the working tree, then dispatch Albus with it. The brief is a contract: every sentence in it has to be either verified or marked as assumed. Albus does re-verify the ground and any stated premises before dispatching (his R0 and R2 steps), so a claim written as fact that turns out wrong does not slip through - it stalls the run and costs a dispatch. Mark anything unchecked as assumed so he verifies it deliberately instead of tripping over it.

## Step 1 - Pin the working directory

Decide where the work happens and confirm it before writing anything.

- Existing branch or PR: use its worktree under `<repo>/.worktrees/<name>` if one exists; otherwise create one with `git -C <repo> worktree add .worktrees/<name> <branch>`. Record `git -C <worktree> rev-parse HEAD` and `git -C <worktree> status --porcelain`. A dirty tree is a stop: ask the user before continuing.
- New work: create `.worktrees/<slug>` on a new branch, same as jira-start Step 4.
- The main checkout is never the working directory.

## Step 2 - Write the brief

Save to `<worktree>/.dispatch-brief.md`. If the user passed an argument, the brief covers that and references the rest by one line. Use this shape, in this order, and keep every section:

```markdown
# Dispatch: <one-line objective>

## Mode

feature | remediation | bugfix | refactor
(remediation = changes to an existing branch/PR driven by review findings)

## Where

- Worktree: <absolute path>
- Branch: <name> HEAD: <sha> Clean: yes
- Push: no. PR/tracker writes: no. Leonard reviews first.

## User's words

<The user's acceptance criteria and decisions, quoted verbatim from the
conversation. Do not paraphrase. If the user said "only if the values
match", this section says "only if the values match".>

## Tasks

<Numbered. Each with: what to change, which files (absolute paths), the
done-condition Albus can check, and what is explicitly out of scope.>

## Decisions already made

<Choices the user settled in conversation, one line each, with the reason
if the user gave one. Albus does not reopen these.>

## Decisions left to Albus

<Open calls. For each: the options, any lead the user or you gave, and the
instruction "state the case against the preferred option before deciding".>

## Verified vs assumed

- Verified: <facts you or the user checked in this session - file read,
  command run, grep done - one per line with how it was checked>
- Assumed: <everything else the brief relies on>

## Optional verification

<Anything worth doing but not required - e2e check, live run - with a time
box (minutes or attempts) and the fallback: "stop, use unit tests as
evidence, report that it was not done".>

## Repo rules

<Paths only: CLAUDE.md, CODING_STANDARDS.md, the exact build/test/lint
commands the project allows.>

## Related artifacts

<Paths and URLs: PR, review output, spec, tickets, earlier briefs.
Never copied in.>

## Report back

<The fields Leonard wants in the final summary.>
```

Rules while writing:

- Reference existing artifacts by path or URL. Copy in only the specific lines the task turns on (a single line of code, a constant).
- Every instruction carries its reason in the same sentence, so Albus can apply it to a case you did not foresee.
- Anything Albus cannot do himself (he has no Bash) is phrased as a task for Harry: "Harry's first task: confirm the worktree is clean at <sha>".
- Redact secrets. Credentials live at a path, not in the brief.

## Step 3 - Reconcile

Read the brief back cold. For each instruction you intend to tell the user you sent, find it in the file. Anything you meant to include but cannot point to goes in now. Anything written as fact that was only assumed moves to the Assumed list. This step exists because the summary to the user and the brief the agent receives drift apart, and the agent only sees the brief.

## Step 4 - Dispatch

Invoke the `Agent` tool:

- `subagent_type: "code-architect"`
- `description: "<mode>: <one-line objective>"`
- `prompt`: the full contents of `.dispatch-brief.md` inline, followed by: "This brief is at `<worktree>/.dispatch-brief.md`. Treat `<worktree>` as your working directory. Run in <mode> mode per your definition. Do not modify files outside the worktree. Do not push."

Do not pass `isolation: worktree`; the worktree is the isolation.

## Step 5 - Report to the user

Five lines: objective, worktree path and HEAD, brief path, mode, the open decisions handed to Albus. The summary is read from the brief file, not from memory.

## Guardrails

- No implementation in this skill. Brief, reconcile, dispatch.
- One dispatch per brief. A second round of findings is a new brief, referencing the first by path.
- A dirty worktree, a missing branch, or a HEAD that does not match what the user expects stops the skill with a question, not a guess.
