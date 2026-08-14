# PROGRESS — install `.agents/` + symlinked skills

Branch: `feat/installer-update-detection` (pre-existing uncommitted work must be preserved)

## Problem

1. `.agents/` (16 files under `.agents/skills/`) is never installed — neither installer references it.
2. The seven `.claude/skills/*` entries that are git-mode-120000 symlinks into `../../.agents/skills/<name>`
   are never installed, because `merge_claude_dir` walks with `find "$src_base" -type f`, and a symlink
   is not `-type f`.

## Verified facts (do not re-derive)

- `fetch_pack` (install.sh:311) tries `git clone -c core.autocrlf=false --depth 1 --branch $REF`, then
  falls back to `curl|wget → tar -xz -C "$WORK"` from codeload. Both mechanisms deliver real symlinks
  on macOS/Linux. Symlinks survive the fetch; the loss is purely in the `find -type f` walk.
- On Windows both paths are unreliable: `git clone` with default `core.symlinks=false` materializes each
  symlink as a small regular file containing the link text; `tar.exe` symlink extraction needs privilege.
- `sha256_file` (install.sh:402) guards with `[ -f "$1" ]`, which *follows* symlinks — a symlink to a file
  hashes the target's bytes, identical to a real copy. A symlink to a directory returns 1.
- `pack_tree_hash` (install.sh:412) uses `find . -type f` → excludes the symlinks. `Get-PackVersion`
  (install.ps1:177) uses `Get-ChildItem -Recurse -File -Force` → on Windows *includes* the git-materialized
  junk files. This is an existing cross-platform version-hash divergence on the tarball path
  (`resolve_pack_version` prefers `git rev-parse HEAD` when `.git` exists, so it only bites the tarball path).
- install.ps1 has no `Merge-CursorDir` at all; its step list is Merge-ClaudeDir → Copy-McpJson →
  Merge-ClaudeMd → Run-EnvSetup → Run-Analysis → Write-PackState → Print-Summary.

## Architecture decision: materialize, never recreate symlinks

**Chosen:** install `.agents/` as real files, and materialize the symlinked skills as **real files** under
`.claude/skills/<name>/...` in the target. No symlink is ever created in a target project.

Mechanism, per platform, chosen so the resulting **state key set and every hash are byte-identical**:

- **bash:** change the walk in `merge_claude_dir` from `find "$src_base" -type f` to
  `find -L "$src_base" -type f`. `-L` descends *through* the directory symlink, so it emits
  `<src>/skills/tdd/SKILL.md` directly. `rel` extraction is unchanged. Zero new machinery.
- **PowerShell:** `Get-ChildItem -Recurse` does not reliably descend reparse points and `-FollowSymlink`
  does not exist in Windows PowerShell 5.1, and on Windows the entries are usually plain text files anyway.
  So install.ps1 gets an explicit `Merge-SkillLinks` that, for each depth-1 entry under `pack\.claude\skills`
  that is not a real directory, resolves the link text (`../../.agents/skills/<name>`, either from
  `$_.Target` for a real reparse point or from the file's own contents for the git-materialized case)
  against `pack\.agents\skills\<name>` and walks the real directory, emitting the same keys.

Both installers additionally **skip any depth-1 regular file under `.claude/skills/`**
(`skills/<name>` with no further path component). On Unix that is a no-op safety net; on Windows it is
what stops the junk link-text file being installed as a "skill".

Rejected: recreating relative symlinks in the target. It works on macOS/Linux and breaks on Windows without
developer mode, forces a directory-level state key that does not fit the per-file add/update/conflict model,
and makes bash and PowerShell behave differently — the exact class of divergence the recent commits on this
branch were spent fixing.

Accepted cost: skill content is duplicated in the target under both `.agents/skills/<name>/` and
`.claude/skills/<name>/`. They are independent state keys; the pack drives both. ~16 small markdown files.

### Version-hash canonicalisation

Canonical rule, applied on both sides: **a depth-1 entry under `.claude/skills/` is never a hashed file.**
- bash `pack_tree_hash`: already correct via `-type f` (symlinks excluded). Leave `find` unprefixed — do
  **not** add `-L` here, or the skill content would be double-counted (it is already counted under `.agents/`).
- PowerShell `Get-PackVersion`: add a `Where-Object` exclusion for `^\.claude/skills/[^/]+$`.

This removes the existing macOS↔Windows tree-hash divergence rather than deepening it.

### `.agents/` tool gating

`merge_agents_dir` is **ungated** by `SELECTED_TOOLS`, matching `copy_mcp_json` rather than
`merge_claude_dir`/`merge_cursor_dir`. Rationale: `.agents/` is the tool-neutral AGENTS.md convention and
maps to no member of the `claude cursor` tool universe; gating it on `claude` would make the shared
source-of-truth dir disappear for cursor-only users. Recorded under the ambiguity rule.

## Requirement traceability

| # | Requirement | Blueprint item | Files |
|---|---|---|---|
| R1 | `merge_agents_dir` step keyed `.agents/<rel>`, full add/update/conflict/force/skip-deleted semantics | new fn mirroring `merge_cursor_dir` (install.sh:1295), reusing `apply_file_action` | install.sh |
| R2 | Wired into `main()` merge phase + summary | `step "Merge .agents/ skills" merge_agents_dir` after `stage_filtered_pack` (install.sh:1541); counters are global so `print_summary` needs no change | install.sh |
| R3 | Symlinked `.claude/skills/*` usable in target | `find -L` in `merge_claude_dir` (install.sh:1288) + depth-1 skip | install.sh |
| R4 | Tarball/clone symlink survival verified | verified above; materialisation chosen so it does not matter | — |
| R5 | Consistent, identical state hashing across bash/PS | materialise real files both sides; identical keys; `sha256_file` already follows links | install.sh, install.ps1 |
| R6 | Mirror everything in install.ps1 | `Merge-AgentsDir`, `Merge-SkillLinks`, depth-1 skip in `Merge-ClaudeDir`, `Get-PackVersion` exclusion, main-flow wiring | install.ps1 |
| R7 | bash tests: fresh-install `.agents/`, symlinked skill usable, update/conflict for `.agents/` keys | new `add_agents_fixture` helper + new `test_*` cases + footer entries | tests/install-update.test.sh |
| R8 | Update PS verification matrix | new cases appended in existing style + header comment refresh | tests/verify-install-ps1.ps1 |
| R9 | Keep existing style (POSIX-ish bash, log/step/STEP_STATUS) | explicit constraint in the implementation packet | all |
| R10 | Run `bash tests/install-update.test.sh`, report actual results | baseline + post-change run | — |

## Status

- [x] Pattern analysis
- [x] Architecture decision
- [x] Traceability gate
- [ ] Baseline test run
- [x] Baseline test run — 107/0 and 7/0, green
- [x] Phase 1 — install.sh (`54e0c1e`), architect-verified at install.sh:1279-1280, 1290, 1297-1312, 1561
- [x] Phase 2 — install.ps1 (`d5e1478`), architect-verified at install.ps1:379-381, 394-409, 411-459
- [x] Phase 3 — tests (`03bbf1c`) — `bash tests/install-update.test.sh` → 121 run, 0 failed
- [x] Review round 1 (Hermione) — **changes-required**: 1 blocker, 7 should-fix, 5 nits
- [x] Round 2 fixes (`9769693`) — 127 run, 0 failed
- [x] Review round 2 (Hermione) — **approve-with-should-fixes**, zero blockers
- [x] Round 3 fixes (`62a54c2`) — 131 run, 0 failed
- [x] Docs (Ron) — README.md, uncommitted

## Review round 2 — findings and disposition

Reviewer independently reproduced 127/0 and both discrimination checks, and ran three of her own
(including a bash tree-hash comparison across Unix-symlink vs Windows-link-text clones of identical
content — identical hash, so R5 is bash-verified).

- **SF1** `Get-PackVersion` excluded depth-1 only while `Merge-ClaudeDir` excluded the whole subtree, under
  identical `-Recurse` exposure — so on WinPS 5.1 with a real-symlink checkout the `.agents/skills/<name>`
  tree was hashed twice and the PS tree hash diverged from bash's. Reopened the `4a001b0` oscillation class.
  **Taken** (drop the trailing `$`).
- **SF2** the predicate claimed *any* depth-1 symlink, but the sole owner can only materialise
  `.agents/skills/<name>` targets — so a symlink pointing elsewhere was claimed, skipped by the merge walk,
  and its content vanished. **Taken** (symlink branch now conditional on the target resolving).
- **SF3** bash `tr -d '[:space:]'` stripped *internal* whitespace where PS only `.Trim()`s — a live
  divergence in the one predicate required to be identical. **Taken** (ends-only trim helper).
- **SF5** no test covered a genuine skill *directory* at depth 1, which is exactly the R3 failure mode
  (a too-greedy subtree skip silently dropping the 8 real skill dirs). **Taken** (mixed-fixture test).
- **SF4** a PowerShell test creating a *real* symlink, to cover the `string[] $Entry.Target` scalarisation
  and the `-Recurse` double-processing path. **DEFERRED — see known gaps.**
- **N1–N5** all taken.

## Known gaps at hand-off

1. **The PowerShell changes have never been executed.** `pwsh` is not installed in this environment, so
   `install.ps1` and `tests/verify-install-ps1.ps1` were verified by review and 1:1 mirroring of the tested
   bash logic only. Four of the fixes in this run are PowerShell-only.
2. **SF4 / Windows PowerShell 5.1 is a declared target but is untested.** The PS matrix invokes `pwsh`
   (PS 7) only, and its fixture models only the plain-link-text clone. Neither the round-1 blocker's
   `string[] $Entry.Target` path nor the 5.1 `-Recurse` reparse-point-following path is exercised on any
   PowerShell version. This is larger than this change and wants a Windows CI job.

## Final test results

- `bash tests/install-update.test.sh` → **131 run, 0 failed** (baseline 107 → 131)
- `bash tests/decide.test.sh` → **7 run, 0 failed**
- `bash -n install.sh` → exit 0
- Four independent discrimination checks in round 3, each reproducing the expected failure signature.

## Review round 1 — findings and disposition

- **B1 (blocker)** — `Merge-SkillLinks` on Windows PowerShell 5.1: `FileSystemInfo.Target` is `string[]`,
  not a string (scalar only since PS 6). With an array operand `-notmatch` filters instead of returning a
  boolean *and* leaves `$Matches` unpopulated, so `$name` was `$null`, `$resolvedSrc` collapsed to the
  `.agents\skills` root, and the walk copied every skill into every skill dir — ~112 bogus files and state
  keys, silently, on the exact platform the function was written for. Fixed in `9769693` via `@(...)[0]`
  scalarisation and `[regex]::Match`.
- **S1** double-processing on WinPS 5.1 (`Get-ChildItem -Recurse` follows reparse points there; that is why
  PS 6 added opt-in `-FollowSymlink`), which double-counted conflicts. Fixed by the sole-owner design.
- **S2/S5 (architect adjudication)** — these two conflicted. S2: the depth-1 skip was too broad, so a
  genuine `.claude/skills/README.md` would never install and the PS tree hash diverged from bash. S5: a
  Windows `core.symlinks=false` clone presents the link as a plain file that *must* be skipped. Hermione's
  proposed `[ -L ] && continue` satisfies S2 and breaks S5. **Ruling:** one shared predicate — depth-1 under
  `.claude/skills/` AND (symlink OR <256-byte file whose trimmed content matches
  `^(\.\./)*\.agents/skills/[^/]+/?$`) — applied in bash `merge_claude_dir`, bash `pack_tree_hash`,
  PS `Merge-ClaudeDir`, PS `Get-PackVersion`, factored into one helper per language.
- **New gap found via that ruling (F4):** install.sh runs under Git Bash on Windows, where `find -L` finds
  nothing, so none of the 7 skills reached `.claude/skills/` at all. Added bash `merge_skill_links`
  mirroring the PS function, wired at `install.sh:1393`, with the sole-owner design on both platforms.
- **S3/S4** vacuous assertions (the delete test passed pre-fix for the wrong reason; `case22`'s
  `-match 'conflict'` matched the unconditional summary line). Both anchored.
- **S6** README does not mention `.agents/` — routed to Ron after approval, not fixed in code.
- **S7** commits 1 and 2 contain a `merge_claude_md` keep-local branch and the `-Reconfigure` wiring that
  are not mentioned in their messages. **Adjudicated:** these are the user's own pre-existing uncommitted
  edits that were in the working tree at session start, not implementation drift. Left in place and
  disclosed rather than rewritten, since history surgery on the user's default branch is out of scope.
- **N1–N5** nits; N1, N2, N3 fixed opportunistically, N4/N5 recorded only.
- [ ] Git branch-state reconciliation (see below)

## Post-change test results

- `bash tests/install-update.test.sh` → **121 run, 0 failed** (baseline 107 → +14 assertions across 6 new tests)
- `bash tests/decide.test.sh` → **7 run, 0 failed**
- `bash -n install.sh` → exit 0
- Discrimination check: reverting only the phase-1 hunks in a scratch copy → 121 run, **12 failed**, and the
  failures were exactly the 6 new `.agents/` tests. The new tests are not vacuous and cause no collateral damage.

## Open issue — branch state (verified, nothing lost, needs a user decision)

Reconstructed from reflog:

- PR #5 merged `feat/installer-update-detection` into `main` as `ab96c9d` on **2026-08-10**, i.e. *before*
  this session. That branch's work is fully preserved in `origin/main`, and the tip `dc675f0` still exists
  on the remote as `origin/feat/installer-update-detection`.
- At **12:26:04** today a fetch fast-forwarded local `main` to `ab96c9d`; at **12:26:05** a checkout moved
  HEAD from `feat/installer-update-detection` to `main`, carrying the 5 modified files across. The local
  branch was then deleted. Neither was done by any agent in this run's implementation phase — both precede
  the first phase commit at 12:42.
- The three phase commits `54e0c1e`, `d5e1478`, `03bbf1c` are on **local `main` only, unpushed**
  (`origin/main...HEAD` = 0 behind, 3 ahead). Nothing is stashed.

**Consequence to surface, not decide:** the phase commits sit directly on `main` with no feature branch, and
they bundle in the pre-existing uncommitted edits to `install.sh` / `install.ps1` / the two test files that
were already in the working tree at session start. `README.md` remains uncommitted. Moving these commits onto
a branch is a history operation on the user's default branch — out of scope for autonomous action.

## Decisions under the ambiguity rule

1. `.agents/` merge is ungated by tool selection (rationale above).
2. Skill content is duplicated (`.agents/` + `.claude/skills/`) rather than symlinked, for Windows parity.
3. `pack_tree_hash` keeps `-type f` (no `-L`); PowerShell gains a matching exclusion. Corrects an existing
   divergence, in scope because both installers now handle these entries.

## Baseline (clean branch, before any edit)

- `bash tests/install-update.test.sh` → **107 run, 0 failed**, exit 0
- `bash tests/decide.test.sh` → **7 run, 0 failed**, exit 0
- `bash -n install.sh` → exit 0
- No pre-existing failures. Any FAIL after this point is a new regression.
- Known harmless stderr noise: a `grep: .../target/.claude/settings.json: No such file or directory`
  line during `subset selection still filters .claude/settings.json` (that assertion still passes).

## Deviations from blueprint

None yet.
