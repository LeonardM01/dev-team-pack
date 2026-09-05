---
name: dispatch-to-albus
description: Turn the current conversation into a written brief and hand it to the code-architect agent (Albus) to execute. Use whenever the user wants Albus to take over work discussed in this session - "send this to Albus", "have Albus fix these", "dispatch this", "let the team handle it" - whether the work is review findings, a bug, a refactor, or a feature. Not for starting from a tracker ticket; that is jira-start / linear-start.
argument-hint: "Optional: what Albus should focus on, if narrower than the whole conversation"
---

Write a brief that a fresh agent can act on without this conversation, save it in the working tree, then dispatch Albus with it. The brief is a contract: every sentence in it has to be either verified or marked as assumed. Albus spot-checks the ground and re-verifies stated premises in one research pass before dispatching (his R2 step), so a claim written as fact that turns out wrong does not slip through - it stalls the run and costs a dispatch. Mark anything unchecked as assumed so he verifies it deliberately instead of tripping over it.

The brief is read on every turn of a long run. Its length is paid for many times over, so it carries the facts the tasks turn on and nothing else: no background essay, no analysis of consequences, no reopening of what the user has already decided.

## Step 1 - Pin the working directory

Decide where the work happens and confirm it before writing anything.

- Existing branch or PR: use its worktree under `<repo>/.worktrees/<name>` if one exists; otherwise create one with `git -C <repo> worktree add .worktrees/<name> <branch>`. Record `git -C <worktree> rev-parse HEAD` and `git -C <worktree> status --porcelain`. A dirty tree is a stop: ask the user before continuing.
- New work: create `.worktrees/<slug>` on a new branch, same as jira-start Step 4.
- The main checkout is never the working directory.

## Step 2 - Research, once

Everything this session can find out now, find out now, so Albus's research pass confirms rather than discovers and no packet stops to look something up:

- Read the files each task touches and pin the exact lines the task turns on.
- Read the project's canonical build / test / lint commands from CLAUDE.md or the manifests and record the exact invocations, including any environment the commands need (a daemon, an env var, a generated prerequisite).
- Answer platform and library questions from documentation where they decide a task's shape.
- Collect every question that needs a running system, a cloud console, or a database into one **Recon** list. Do not answer them piecemeal across the brief; Albus carries the list into the first packet and gets every answer in one report.

Anything you did not check goes under Assumed, with what checking it would take.

## Step 3 - Write the brief

Save to `<worktree>/.dispatch-brief.md`. If a `.dispatch-brief.md` already exists from an earlier run, rename it `.dispatch-brief-<nn>-<slug>.md` first and reference it by path. If the user passed an argument, the brief covers that and references the rest by one line. Keep it under roughly 1,200 words for remediation and 2,000 for a feature; a brief that needs more is carrying analysis that belongs in the packet Albus writes, or tasks that belong in a second brief. Use this shape, in this order, and keep every section:

```markdown
# Dispatch: <one-line objective>

## Mode

feature | remediation | bugfix | refactor
(remediation = bounded changes to an existing branch/PR driven by review
findings. If the tasks create a subsystem - a runner, a harness, a new table
and its access layer, CI, work in a second repo - it is a feature even when
a bug triggered it. Albus checks this and will relabel.)

## Where

- Worktree: <absolute path>
- Branch: <name> HEAD: <sha> Clean: yes
- Push: no. PR/tracker writes: no. Leonard reviews first.

## User's words

<The user's acceptance criteria and decisions, quoted verbatim from the
conversation. Do not paraphrase. If the user said "only if the values
match", this section says "only if the values match".>

## Context

<At most one paragraph: what is broken or wanted, and where. The cause, if
known, as a file:line and one sentence. No history, no essay.>

## Tasks

<A checklist. Each item: what to change, which files (absolute paths), the
done-condition Albus can check, and what is explicitly out of scope. Only
items that change code, tests, config, or docs are tasks. A question the
user wants answered goes under Report back, not here.>

- [ ] 1. ...
- [ ] 2. ...

## Decisions already made

<Choices the user settled in conversation, one line each, with the reason
if the user gave one. Albus does not reopen these. "Fix all" is a decision:
it settles every finding the user was looking at when they said it.>

## Decisions left to Albus

<Open calls only. For each: the options and any lead. Albus writes one line
for the choice and one for the case against it. Do not put a decision here
that the user's words already settle.>

## Facts

- verified: <fact> (<file:line> | <command run> | <doc URL>)
- assumed: <fact> - <what would check it>

## Recon

<Every question that needs the live system, a console, or a database, as
one list. Albus carries it into the first packet unchanged.>

## Optional verification

<Anything worth doing but not required - e2e check, live run - with a time
box (minutes or attempts) and the fallback: "stop, use unit tests as
evidence, report that it was not done".>

## Repo rules

<Paths only: CLAUDE.md and any standards file that exists. The project's
build / test / lint / run commands as exact invocations, plus what they
need to run (daemon, env var, generated prerequisite).>

## Related artifacts

<Paths and URLs: PR, review output, spec, tickets, earlier briefs.
Never copied in.>

## Report back

<The fields Leonard wants in the final summary, and every report-only
question, one line each.>

## Discovered during run

<Empty at dispatch. Albus appends facts here as recon and reports produce
them, so a resumed run and every later packet start from the corrected
picture. Nothing above this heading is edited after dispatch.>
```

Rules while writing:

- Reference existing artifacts by path or URL. Copy in only the specific lines the task turns on (a single line of code, a constant).
- Every instruction carries its reason in the same sentence, so Albus can apply it to a case you did not foresee.
- Anything Albus cannot do himself (he has no Bash) is phrased as a step inside Harry's first packet, not as a separate task: the ground check and the Recon list both ride in packet 1.
- Refer to commands generically ("the project's test command") in prose and give the exact invocation once, under Repo rules. Never assume a particular runner.
- Redact secrets. Credentials live at a path, not in the brief.

## Step 4 - Reconcile

Read the brief back cold. For each instruction you intend to tell the user you sent, find it in the file. Anything you meant to include but cannot point to goes in now. Anything written as fact that was only assumed moves to the Assumed list. Anything under Decisions left to Albus that the User's words already answer moves to Decisions already made. Anything under Tasks that changes no file moves to Report back. This step exists because the summary to the user and the brief the agent receives drift apart, and the agent only sees the brief.

## Step 5 - Dispatch

Invoke the `Agent` tool:

- `subagent_type: "code-architect"`
- `description: "<mode>: <one-line objective>"`
- `prompt`: the full contents of `.dispatch-brief.md` inline, followed by: "This brief is at `<worktree>/.dispatch-brief.md`. Treat `<worktree>` as your working directory. Run in <mode> mode per your definition. Do not modify files outside the worktree. Do not push."

Do not pass `isolation: worktree`; the worktree is the isolation.

## Step 6 - Report to the user

Five lines: objective, worktree path and HEAD, brief path, mode, the open decisions handed to Albus. The summary is read from the brief file, not from memory.

## Guardrails

- No implementation in this skill. Research, brief, reconcile, dispatch.
- One dispatch per brief. A second round of findings is a new brief, referencing the first by path.
- A dirty worktree, a missing branch, or a HEAD that does not match what the user expects stops the skill with a question, not a guess.
