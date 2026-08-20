---
name: copy-review
description: "Review and improve one website page's copy for conversion. Audits against master copywriting frameworks (PAS, AIDA, BAB, FAB, PASTOR, PPPP, ACCA, SLAP, 4 C's) and a 10-blunder checklist, grounds rewrites in Voice-of-Customer research, and applies approved changes via Albus and Harry. Use when the user says review the copy, improve the landing page copy, copy audit, rewrite the hero, or asks to make page copy convert better. One page per run; copy is read from and written to codebase files."
---

# Copy Review & Improvement

Audit and rewrite the copy of ONE page per run. You orchestrate; heavy work is delegated: VoC research runs in a subagent, code edits go through Albus (code-architect) → Harry (fullstack-developer). Do not load the reference files until the phase that needs them.

## Phase 1 - Context gathering

1. Ask the user in a single AskUserQuestion batch (skip anything already stated):
   - **Target page** - route or file path
   - **Audience + awareness level** - cold / problem-aware / solution-aware / product-aware
   - **Conversion goal** - the single action the page exists to drive
   - **Product name + 1–2 competitors** - seeds the research phase
2. Locate the page's source files (page file + imported section components). Extract the current copy per section: hero, features, social proof, pricing, FAQ/objections, CTA blocks - whatever the page actually has.
3. If the page files cannot be found, ask the user for the route/path. Do not guess.

## Phase 2 - VoC research (delegated)

1. Read `references/voc-research.md`.
2. Spawn ONE research subagent (general-purpose). Its prompt = the full playbook text + the product, audience, awareness level, competitors, and conversion goal from Phase 1.
3. The subagent returns a compact "VoC Research Brief" (customer phrases, objections, competitor claims, coverage gaps). Only the brief enters this conversation - never raw page dumps.
4. If the brief comes back empty or useless, proceed frameworks-only and say so explicitly in the review artifact.

## Phase 3 - Audit & rewrite (in this conversation)

1. Read `references/frameworks.md` and `references/blunders.md`.
2. **Map:** assign a framework to each page section using the selection matrix and the confirmed awareness level. Long pages stack (e.g. PAS hero → FAB breakdown → AIDA close).
3. **Audit:** check every section against blunders B1–B10; record findings by ID.
4. **Rewrite:** rewrite each section in its assigned framework, weaving in verbatim VoC phrases from the brief. Pass every sentence through the 4 C's filter (clear, concise, compelling, credible).

## Phase 4 - Review artifact & approval gate

1. Generate ONE self-contained HTML file (write to `/tmp/copy-review-<page>.html`, no external assets). Per section, a side-by-side card: current copy vs. rewrite, plus the framework used, blunder IDs fixed, VoC phrases woven in, and a one-line rationale.
2. Open it in the user's browser; if opening fails, give the user the path and suggest `! xdg-open <path>`.
3. Collect approvals/adjustments per section IN CHAT. Re-render adjusted sections until approved.
4. If the user rejects everything: stop. No files are touched.

## Phase 5 - Implementation (delegated: Albus → Harry)

1. Build a structured brief from the approved rewrites only:
   ```
   ## Copy Implementation Brief
   Page: <route>
   ### <Section> - <file path>
   OLD: <exact current string>
   NEW: <approved rewrite>
   ```
2. Send the brief to Albus (code-architect agent). Albus plans the edits and delegates the actual file changes to Harry (fullstack-developer agent), following project rules (no comments, one component per file, Tailwind, functional components).
3. When Harry finishes, diff the changed files against the brief. Flag any divergence (missing section, altered wording, touched files outside the brief) to the user before reporting done.
4. Report: sections changed, files edited, and any rewrites the user chose to skip.

## Error handling

| Situation | Do this |
| --- | --- |
| Page files not found | Ask the user; never guess |
| Steel unavailable | Playbook falls back Playwright → WebSearch; brief notes gaps |
| Research brief empty | Frameworks-only rewrite; state it in the artifact |
| User rejects all rewrites | Stop before Phase 5; nothing touched |
| Harry's diff diverges from brief | Flag divergence before reporting done |

## Non-goals

No whole-site sweeps, no A/B test tooling, no SEO keyword optimization, no CMS content - codebase copy only.
