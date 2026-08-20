# PROGRESS - add `unslop` skill to the dev-team pack

Run started 2026-08-19. Branch: `main`. Working dir: `/Users/leonard/Documents/coding/dev-team`.

## Goal

Vendor the `unslop` skill from `cursor/plugins` (`pstack/skills/unslop/SKILL.md`) into this pack,
wired for both Claude Code and Cursor, installable by `install.sh` / `install.ps1`.

## Requirement traceability

| # | Requirement | Blueprint item / files |
|---|---|---|
| R1 | Fetch upstream `unslop` content | `.agents/skills/unslop/SKILL.md` (verbatim copy of `https://raw.githubusercontent.com/cursor/plugins/main/pstack/skills/unslop/SKILL.md`). Upstream dir listing confirms `SKILL.md` is the **only** file in the skill. |
| R2 | Tool-neutral skill packaging | `.agents/skills/unslop/agents/openai.yaml` (matches `grill-with-docs`/`grilling` shape) |
| R3 | Claude Code integration | `.claude/skills/unslop` → git symlink (mode 120000) to `../../.agents/skills/unslop` |
| R4 | Cursor integration | `scripts/sync-cursor.mjs`: `FRONTMATTER.unslop` + generation block; regenerated `.cursor/rules/unslop.mdc` and `.cursor/README.md` |
| R5 | Installable via `install.sh` / `install.ps1` | Verified by inspection + `tests/install-update.test.sh`. Both installers discover skills **dynamically**; no enumeration to edit. |
| R6 | Pack version bump | Investigated - see "Findings / decisions" D3 |
| R7 | Docs | `README.md` lines 31, 33, 250–263, 267–273 (Ron) |
| R8 | Provenance record | `skills-lock.json` entry - see D2 |

## Findings

- **Neither installer hardcodes skill names.** `install.sh` `compute_skill_link_names()` (lines 483–507)
  walks `pack/.claude/skills/*` and applies `is_skill_link()`; `install.ps1` `Get-SkillLinkNames`
  (lines 244–265) mirrors it. `merge_agents_dir` / `Merge-AgentsDir` blanket-copy `.agents/**`;
  `merge_cursor_dir` blanket-copies `.cursor/**`. A correctly-shaped new skill installs with zero
  installer edits.
- **No test enumerates real skills.** `tests/install-update.test.sh` builds a synthetic `tdd` fixture.
  No fixture or expected-list edit needed.
- **`install.ps1` has no `.cursor/` merge and no tool selection** (documented at install.ps1:351–355).
  Windows users installing via PowerShell do not receive `.cursor/rules/*.mdc` - pre-existing,
  applies to every rule, not specific to `unslop`.

## Decisions (ambiguity rule)

- **D1 - `alwaysApply: false` on the Cursor rule.** Upstream's description says "Must always apply.",
  which maps naturally onto Cursor's `alwaysApply: true`. Chose `false` for consistency with the
  closest existing analogue, `using-superpowers.mdc`, which is also an always-type meta-skill and
  ships `alwaysApply: false`. Every rule in `.cursor/rules/` is `false`; `true` would inject ~6.5KB
  into every Cursor request. The "always" intent is carried in the rule `description` instead.
  Reversible - flip one line in `scripts/sync-cursor.mjs` if the user prefers otherwise.
- **D2 - add `unslop` to `skills-lock.json`.** The file's 8 existing entries are all
  `mattpocock/skills` and it is written by an external `skills` CLI that no repo tooling reads.
  The distinction that actually separates its members from the excluded first-party skills
  (`copy-review`, `prd-generator`, …) is *vendored from upstream* vs *authored here*. `unslop` is
  vendored, so it belongs. `source: "cursor/plugins"`, `skillPath: "pstack/skills/unslop/SKILL.md"`,
  `computedHash` = sha256 of the vendored file bytes. Schema `"version": 1` is a **lockfile schema
  version**, not a release version - left untouched.
- **D3 - no hand-maintained pack version exists to bump.** `resolve_pack_version()`
  (install.sh:531–546) sets the version consumed by other projects to the pack's **git HEAD SHA**,
  falling back to `pack_tree_hash()` (a sha256 over the pack tree). It is written into the target
  project's `.dev-team-pack.json` and compared on the next run. There is no `plugin.json`,
  `marketplace.json`, or `package.json` in this repo. Update detection therefore fires
  automatically once this change is committed - no semver to increment. Surfaced to the user
  rather than inventing a version scheme (hard to reverse: other projects would start keying off it).

## Status

| Phase | Status |
|---|---|
| Recon (skill wiring, installers, tests, docs) | done |
| Upstream fetch + traceability gate | done |
| Baseline (build/tests/lint on clean tree) | done |
| Phase 1 - vendor skill + Claude symlink + lock entry | done |
| Phase 2 - Cursor sync generator + regenerate | done |
| Phase 3 - installer/test verification | done |
| Review (Hermione) | done - round 1 REQUEST-CHANGES, round 2 fixes applied and self-verified |
| Docs (Ron) | done |

## Docs result (Ron, R7)

`README.md` only. Four edits:
- line 31 - appended `unslop` to the `.agents/` list, plus one sentence on what it does
- line 33 - `eight` → `nine`, appended `unslop` to the symlink parenthetical
- `## Layout` `.claude/` block (~259) - `eight` → `nine`, added `unslop`, alignment preserved
- `## Layout` `.cursor/rules/` block (~274) - added four missing rows: `grill-with-docs.mdc`,
  `using-superpowers.mdc`, `unslop.mdc`, `lean-ctx.mdc`. Three of those were **pre-existing
  staleness** unrelated to this change (3c77e9d never updated this block). `lean-ctx.mdc` is
  noted as the one rule not generated by `scripts/sync-cursor.mjs`.

Decided against a `## The unslop skill` prose section: `jira-start`/`linear-start` have those
because they are multi-step interactive flows with prompts and worktrees. `unslop` is a stateless
style filter with no workflow, so a section would restate the inline sentence. Agreed.

Verified: `grep -n eight README.md` returns nothing; the ten `.cursor/rules/` rows all align at
column 30.

## Baseline (recorded before any edit)

- `node --version` → v22.20.0. No `package.json`, so no npm build/test/lint exists.
- `node scripts/sync-cursor.mjs` → 10 files, all UNCHANGED, `git status` unmoved. Committed
  `.cursor/` output was in sync with the generator.
- `bash tests/install-update.test.sh` → **131 run, 0 failed**. No pre-existing failures.
- Only pre-existing working-tree change: ` M PROGRESS.md` (mine).

## Implementation result (Harry, phases 1–3)

Created:
- `.agents/skills/unslop/SKILL.md` - 6595 bytes, byte-verbatim `curl` of upstream, sha256
  `181883e539caec8258ec9129e3ba5f133409144a2cbf2aa361158ab94cfc3441`. Items 1–31 verified present.
- `.agents/skills/unslop/agents/openai.yaml` - 131 bytes, `allow_implicit_invocation: true`.
- `.claude/skills/unslop` - real symlink, git mode 120000 → `../../.agents/skills/unslop`, no
  trailing newline. Matches the `grill-with-docs` shape from 3c77e9d exactly.
- `.cursor/rules/unslop.mdc` - 6794 bytes, generated.

Modified:
- `scripts/sync-cursor.mjs` - `FRONTMATTER.unslop`, generation block 7, `cursorReadme` table row.
- `.cursor/README.md` - regenerated.
- `skills-lock.json` - `"unslop"` entry appended (alphabetically last), schema `"version": 1` untouched.

Verification:
- `node scripts/sync-cursor.mjs` twice → second run all 11 UNCHANGED (idempotent).
- `bash tests/install-update.test.sh` → 131 run, 0 failed. **Zero delta vs baseline.**
- End-to-end install into a throwaway target with `--tools claude,cursor` materialized all four
  paths as real files (`.claude/skills/unslop/SKILL.md` is a real file, not a symlink - confirming
  `merge_skill_links` works) and tracked all four in the target's `.dev-team-pack.json`.
- Predicate confirmed for both the real-symlink path and the Windows `core.symlinks=false`
  link-text-file path, in bash and PowerShell.
- `install.sh` and `install.ps1` required **zero edits** - confirmed empirically, not assumed.

R6 confirmed: no hand-maintained semver exists anywhere. Every `version` hit is either the
`skills-lock.json` schema version or a value computed from the git SHA.

## Review rounds

### Round 1 (Hermione) - REQUEST-CHANGES: 0 blockers, 2 should-fixes, 3 nits

Coverage: R1, R3, R4, R5, R6 covered. R2 covered. R8 **partial**.

**SF1 - `skills-lock.json` `computedHash` does not use the convention the other 8 entries use.
ACCEPTED. This overturns decision D2.**

Hermione computed sha256 of the local `.agents/skills/<name>/SKILL.md` for all nine entries.
`unslop` is the **only** one whose recorded `computedHash` equals that value; all eight
`mattpocock` entries mismatch. She then ruled out "it is the upstream hash at vendor time":
current upstream `to-tickets/SKILL.md` hashes to `5c9fba69…`, matching neither the lock's
`0349eee2…` nor the local `5ecdf1d4…`. So the `skills` CLI hashes some other scope and the value
is **not reproducible from this repo**.

I was wrong in D2. My reasoning ("vendored vs authored" is the line that separates members) was
sound about *membership* but I hand-wrote a value under a key whose semantics I could not
reproduce. That is worse than omission: a future `skills` CLI run recomputes with its own
algorithm, gets a different value, and reports false drift. The entry shape compounds it - 
`source: "cursor/plugins"` with `skillPath: "pstack/skills/unslop/SKILL.md"` is unlike all eight
siblings (one repo, `skills/<category>/<name>/SKILL.md`), so the CLI may not resolve it at all.

**Resolution (D2-revised): remove the `unslop` entry from `skills-lock.json` entirely**, restoring
the file to its committed state. That file is an artifact of an external CLI that no repo tooling
reads. Provenance belongs where a human reads it, so record the upstream source in `README.md`
instead. Chose full removal over "keep entry, drop computedHash" because a hash-less entry is
still a schema deviation and still exposes the unresolvable `source`/`skillPath` shape.

**SF2 - three integrations declare three different auto-apply answers, rationale nowhere durable.
ACCEPTED.** Claude Code description says "Must always apply." (verbatim upstream, correct),
OpenAI says `allow_implicit_invocation: true`, Cursor says `alwaysApply: false`. Hermione
endorses `true` for OpenAI on its merits and does not dispute D1's value. Her point is that D1's
rationale lives only in this scratchpad, which is not part of the change and evaporates. Fix: a
comment above `FRONTMATTER.unslop` in `scripts/sync-cursor.mjs`.

**Nits, not actioned:** N1 (no test for `sync-cursor.mjs`; she verified the staleness property by
hand and judged this change does not widen the gap - a CI line `node scripts/sync-cursor.mjs &&
git diff --exit-code .cursor/` would be the cheap permanent guard). N2 (`trimStart()` in
`stripClaudeFrontmatter` is harmless here). N3 (a target that already installed the upstream
`pstack` plugin would see a conflict on `.claude/skills/unslop/SKILL.md` - correct behavior).

**Confirmed by Hermione independently:** R6 (no hand-maintained semver anywhere), and that
`pack_tree_hash()` **does** move for this change - the depth-1 exclusion at install.sh:518-524
skips only `.claude/skills/unslop` itself, while `.agents/skills/unslop/**` and
`.cursor/rules/unslop.mdc` are ordinary files that `find -type f` counts. Tests: 131/0 on
`install-update.test.sh`, 7/0 on `decide.test.sh`. No delta.

### Round 2 - both should-fixes applied

- SF1: `unslop` entry removed from `skills-lock.json`. `git diff skills-lock.json` is **empty**;
  file is byte-identical to HEAD. Verified by me directly, not just reported.
- SF2: four-line rationale comment added above `FRONTMATTER.unslop` in `scripts/sync-cursor.mjs`.
  Comment-only; no value changed. Verified by me directly.
- Regression: `sync-cursor.mjs` run twice → 11/11 UNCHANGED both times (the comment lives in
  generator source, so it must not move generated output - confirmed). Tests 131/0 and 7/0.

**Adjudication: no round 3.** I did not send round 2 back to Hermione. Both fixes are objectively
verifiable without judgment - a revert whose correctness is proven by an empty `git diff`, and a
comment insertion that provably does not alter generated output. I read both files myself. Sending
a reviewer to re-read a comment would spend a round on nothing.

## Deviations from blueprint

1. **D2 reversed after review.** Blueprint R8 said add `unslop` to `skills-lock.json`. Round 1
   evidence showed the `computedHash` semantics are unreproducible, so the entry was removed and
   provenance moved to `README.md` instead. Net effect on the tree: `skills-lock.json` unchanged.
2. **Ron edited one file outside his packet.** His packet said `README.md` only; he also updated
   his own memory at `.claude/agent-memory/docs-maintainer/project_dev_team_pack.md`. That path is
   agent memory, not project source, and `.claude/agent-memory/` is gitignored, so it does not
   appear in the change. Allowed to stand, flagged to the user.
3. **Ron fixed pre-existing staleness beyond the ask.** The `.cursor/rules/` listing in `## Layout`
   was missing `grill-with-docs.mdc`, `using-superpowers.mdc`, and `lean-ctx.mdc` before this task
   (since 3c77e9d). He added all of them alongside `unslop.mdc`. Kept - the block would otherwise
   have been wrong in a way this change draws attention to.
4. **Harry's e2e install used an out-of-repo git snapshot.** `install.sh`'s `fetch_pack` clones
   committed refs only, and the packet forbade committing, so a literal install from this repo
   would not have seen the new files. He snapshotted the working tree into a scratch git repo
   outside this directory and installed from that. The real repo was never cloned or modified.
   Sound call; it is the only way to exercise uncommitted content end to end.

## Known limitations (pre-existing, not introduced here)

- `install.ps1` has no `.cursor/` merge step (install.ps1:830-832). Windows PowerShell installs
  receive **no** `.mdc` rules at all, so `unslop.mdc` is absent there exactly as all nine others
  are. Told the user.
- No test covers `scripts/sync-cursor.mjs`, and no test enumerates real skills. Hermione verified
  the staleness property by hand and judged this change does not widen the gap. Cheapest permanent
  guard would be a CI line: `node scripts/sync-cursor.mjs && git diff --exit-code .cursor/`.
- A target project that already installed the upstream `cursor/plugins` pstack plugin directly
  would see a conflict on `.claude/skills/unslop/SKILL.md` at the next pack update. Correct
  behavior, but plausible in the wild given `unslop` is a popular upstream skill.

## Final state - nothing committed, nothing staged

```
 M .cursor/README.md
 M PROGRESS.md
 M README.md
 M scripts/sync-cursor.mjs
?? .agents/skills/unslop/
?? .claude/skills/unslop
?? .cursor/rules/unslop.mdc
```
