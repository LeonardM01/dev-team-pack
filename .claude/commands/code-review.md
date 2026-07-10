---
description: "Code review a GitHub pull request"
argument-hint: <pr-number-or-url>
allowed-tools:
  - Bash(gh pr view:*)
  - Bash(gh pr diff:*)
  - Bash(gh issue view:*)
  - Bash(gh api:*)
  - Bash(gh pr comment:*)
  - Read
  - Glob
  - Agent
---

You are the orchestrator of a multi-agent PR review. The goal is to post a single, well-structured review comment on the pull request with real issues only — no false positives, no filler.

Division of labor, for cost and quality: YOU (the larger model) do all exploration and context gathering exactly once, digest it into a context pack, and dispatch five Sonnet reviewers who receive everything they need inline. The reviewers never explore the repository — they only read the diff and the context pack you hand them. This keeps token cost low and keeps the cheap models focused on judgment instead of navigation.

## Step 1 — Resolve the PR

`$ARGUMENTS` is either a PR number or a full GitHub PR URL. Run:

```
gh pr view $ARGUMENTS --json number,title,body,baseRefName,headRefName,headRefOid,url,files,commits
```

Extract: the repo (from the URL or `gh pr view` output), the PR number, the head SHA (`headRefOid`), the base branch, the PR URL, the changed-file list, and the commit messages. You will need the full 40-character SHA later for permalink construction.

## Step 2 — Fetch the diff

```
gh pr diff $ARGUMENTS
```

Read the entire diff. Note every file path and every changed hunk. Do not truncate.

## Step 3 — Build the context pack

This is your exploration budget being spent once so five reviewers don't spend it five times. Gather:

1. **Intent** — What is this PR trying to accomplish, and why? Synthesize from the title, body, and commit messages. If the body references an issue or ticket (`#123`, `PROJ-123`, a Linear/Jira URL), fetch it (`gh issue view 123 --json title,body` for GitHub issues) and fold its goal and acceptance criteria in. Skip silently if not fetchable.
2. **Tech stack** — Name the specific technologies the diff touches so reviewers apply the right idioms: language + version hints, framework (e.g. Next.js App Router, Expo/React Native, SwiftUI, Hono), ORM/database, test framework. Infer from file extensions, imports visible in the diff, and manifest files (`package.json`, `Package.swift`, `app.json`, etc.) — read them if present in the checked-out repo.
3. **Changed-file map** — Every changed file with one line on its role in this PR (e.g. "adds the webhook route", "migration for the new column", "test coverage for the parser").
4. **Conventions** — Read `CLAUDE.md` (root, plus any nested ones covering changed paths) and extract only the rules a reviewer could act on (naming, patterns, forbidden constructs, review rules). Do not paste the whole file.
5. **Declared scope limits** — Anything the PR body explicitly defers ("follow-up", "out of scope", known limitations), so reviewers don't flag intentional omissions.

Assemble it in exactly this shape, and keep it under ~50 lines:

```
## PR Context Pack
**Intent:** <2-4 sentences: what this PR does and why>
**Tech stack:** <specific technologies relevant to judging this diff>
**Changed files:**
- <path> — <role in this PR>
**Conventions that apply:**
- <actionable rule, with source (CLAUDE.md, lint config)>
**Explicitly out of scope:**
- <deferred item, or "nothing declared">
```

## Step 4 — Dispatch 5 parallel reviewers

In a **single message**, dispatch all five Agent tool calls simultaneously. Do not wait for one to finish before starting the next. Use `subagent_type: "code-reviewer"` and `model: "sonnet"` for all five.

Each reviewer's prompt must contain, in this order: the context pack, the full diff text, the head SHA, their domain charter (below), and these standing rules verbatim:

> You are one of five parallel reviewers. Review ONLY your assigned domain.
> Do NOT explore the repository: no file reads, no shell commands, no searching. Everything you may use is in this prompt — the context pack and the diff. If a judgment depends on code you cannot see, do not investigate; lower your confidence per the rubric and say what context is missing.
> Ignore your default review workflow and output format for this task. Return ONLY the JSON array described below — no prose before or after.
> Confidence rubric: 95-100 = definitively wrong or insecure, no reasonable interpretation makes it correct. 85-94 = very likely real, the triggering scenario is realistic. 75-84 = probable but depends on context not visible in the diff — say so in the body. 60-74 = speculative, include only if the risk is severe. Below 60 = do not include.
> Do not flag anything listed as explicitly out of scope in the context pack, style choices consistent with the rest of the diff, or TODO comments.

Domain charters:

- Reviewer A — Correctness, logic & intent: wrong conditions, off-by-one errors, incorrect state transitions, missing awaits, broken control flow. Additionally: does the diff actually accomplish the Intent stated in the context pack? A stated goal with no implementing code in the diff is a critical finding.
- Reviewer B — Security: injection, authentication/authorization gaps, secrets in diffs, unvalidated input, unsafe deserialization, OWASP Top 10, platform-specific risks for the stack named in the context pack.
- Reviewer C — Edge cases & error handling: null/undefined, empty collections, boundary values, network failures, timeouts, concurrent access, partial failures.
- Reviewer D — Performance & scalability: N+1 queries, missing indexes hinted by ORM usage, unbounded loops, blocking I/O in hot paths, unnecessary re-renders or main-thread work for UI stacks.
- Reviewer E — Maintainability & conventions: naming, duplication, complexity, missing tests for non-trivial logic, and violations of the Conventions section of the context pack (cite the convention violated).

Each reviewer must return a JSON array (and nothing else) in this exact schema:

```json
[
  {
    "file": "src/foo/bar.ts",
    "line": 42,
    "severity": "critical|important|suggestion",
    "title": "Short title (no emoji)",
    "body": "What is wrong, why it matters, concrete fix. 2-4 sentences max.",
    "confidence": 85
  }
]
```

Return `[]` if no issues are found in the assigned domain.

## Step 5 — Collect and deduplicate

Merge all five arrays. Deduplicate: if two reviewers flag the same file+line for the same root cause, keep the one with higher confidence (or merge the bodies if they are complementary). Filter out any finding with `confidence < 80`.

## Step 6 — Re-score each finding

You have context the reviewers lacked — the repository itself. For each remaining finding, verify the confidence score against the same rubric the reviewers used (95-100 definitive, 85-94 very likely, 75-84 context-dependent, 60-74 speculative). Where a reviewer lowered confidence for missing context, check that context now (read the file at the referenced location) and re-score up or down accordingly. Apply the threshold again: drop findings below 80 after re-scoring, unless severity is critical and the risk is severe.

## Step 7 — False-positive check

Before posting, verify each finding is NOT one of these common false positives:

- Flagging a pattern as missing when it is clearly handled elsewhere in the diff (e.g., error handling present two hunks up).
- Complaining about a style choice that is consistent with other code visible in the diff or sanctioned by the context pack's conventions.
- Treating a TODO comment as a bug.
- Flagging something the PR body or context pack declares intentional or out of scope.
- Flagging an intentional type assertion that is safe given the surrounding context.
- Raising a performance concern on a code path that runs once at startup.
- Assuming a variable is unvalidated when the diff shows validation earlier in the same function.

Remove any finding that matches a false-positive pattern above.

## Step 8 — Build the GitHub comment

Construct the comment body using exactly these templates.

### If findings remain after filtering:

```
## Code Review — {N} issue(s) found

**PR intent:** {one-sentence restatement of the Intent from the context pack}

| # | Severity | File | Line | Title |
|---|----------|------|------|-------|
| 1 | 🔴 Critical | `src/foo/bar.ts` | 42 | Short title |
| 2 | 🟡 Important | `src/baz.ts` | 17 | Short title |
| 3 | 🟢 Suggestion | `src/qux.ts` | 88 | Short title |

---

### 1. Short title
**File:** [`src/foo/bar.ts#L42`](https://github.com/{owner}/{repo}/blob/{HEAD_SHA}/src/foo/bar.ts#L42)
**Severity:** Critical | **Confidence:** 95

What is wrong and why it matters. Concrete suggested fix. Keep to 2–4 sentences.

---

### 2. Short title
**File:** [`src/baz.ts#L17`](https://github.com/{owner}/{repo}/blob/{HEAD_SHA}/src/baz.ts#L17)
**Severity:** Important | **Confidence:** 87

...

---

*Reviewed by 5 parallel Sonnet agents (correctness & intent, security, edge cases, performance, maintainability) briefed with an orchestrator-built context pack. Confidence threshold: 80. Orchestrator re-score and false-positive check applied.*
```

### If no findings remain after filtering:

```
## Code Review — No issues found

**PR intent:** {one-sentence restatement of the Intent from the context pack}

Reviewed by 5 parallel Sonnet agents across correctness & intent, security, edge cases, performance, and maintainability, briefed with an orchestrator-built context pack. All findings scored below the confidence threshold (80) or were ruled false positives.

*Confidence threshold: 80. Orchestrator re-score and false-positive check applied.*
```

Rules for the comment:
- Replace `{owner}/{repo}` with the actual org/repo from Step 1.
- Replace `{HEAD_SHA}` with the full 40-character head commit SHA from Step 1. Never use a short SHA.
- Use the full GitHub permalink format: `https://github.com/{owner}/{repo}/blob/{HEAD_SHA}/{file}#L{line}`.
- Severity order: Critical first, then Important, then Suggestion.
- No emoji in titles or body text — only in the severity column of the table.
- No trailing summary paragraph. No "happy to discuss" filler. Stop after the footer line.

## Step 9 — Post the comment

```
gh pr comment $ARGUMENTS --body "$(cat <<'REVIEW_EOF'
{comment body here}
REVIEW_EOF
)"
```

After posting, output only the PR URL so the user can navigate to it. Nothing else.
