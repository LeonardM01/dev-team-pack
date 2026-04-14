#!/usr/bin/env node
// sync-cursor.mjs — generates .cursor/ files from .claude/ sources
// Pure Node >=18, zero deps. Run: node scripts/sync-cursor.mjs
// See blueprint §5 for behavior spec.

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const REPO = join(__dirname, '..');

// Guard: must run from (or resolve to) a repo that has .claude/
if (!existsSync(join(REPO, '.claude'))) {
  console.error('ERROR: .claude/ not found. Run this script from the dev-team repo root.');
  process.exit(1);
}

// ─── helpers ────────────────────────────────────────────────────────────────

function read(relPath) {
  const abs = join(REPO, relPath);
  if (!existsSync(abs)) {
    console.error(`ERROR: missing source file: ${abs}`);
    process.exit(1);
  }
  return readFileSync(abs, 'utf8');
}

function writeIdempotent(relPath, content) {
  const abs = join(REPO, relPath);
  mkdirSync(dirname(abs), { recursive: true });
  // Normalise to LF
  const normalised = content.replace(/\r\n/g, '\n');
  if (existsSync(abs)) {
    const existing = readFileSync(abs, 'utf8').replace(/\r\n/g, '\n');
    if (existing === normalised) {
      console.log(`UNCHANGED  ${relPath}`);
      return false;
    }
  }
  writeFileSync(abs, normalised, 'utf8');
  console.log(`WROTE      ${relPath}`);
  return true;
}

// Strip the Claude-specific YAML frontmatter (everything between first two ---).
// The .claude/agents/*.md files actually contain TWO frontmatter blocks (one
// with model/color/memory, one with tools/description). Strip both, keep body.
function stripClaudeFrontmatter(src) {
  // Each block: starts with ---, ends with ---
  // Strip all leading frontmatter blocks
  let text = src.trimStart();
  while (text.startsWith('---')) {
    const closeIdx = text.indexOf('\n---', 3);
    if (closeIdx === -1) break;
    text = text.slice(closeIdx + 4).trimStart(); // skip past closing ---
  }
  return text;
}

// ─── shared preface text (§3.3) ─────────────────────────────────────────────

const CURSOR_PREFACE = `## Cursor mode — persona switching (READ FIRST)

You are operating inside Cursor, not Claude Code. Cursor has no subagent primitive, so the
"delegation chain" from the Claude Code setup is expressed as **explicit persona switches
inside this single session**.

When this rule tells you to "delegate to Harry", you MUST:
  1. Announce the handoff: "Switching to Harry (fullstack-developer)."
  2. Load the target rule into context by telling the user to @-mention it, OR by
     reading \`.cursor/rules/<target>.mdc\` yourself and treating its body as your new
     system prompt for the next phase of work.
  3. Continue execution under that persona until the persona's exit condition is met,
     then announce the next switch.

Do NOT try to call a subagent tool — it does not exist here. Do NOT silently merge personas.
Always be explicit about which persona is currently active so the user can follow along.

Tools you had in Claude Code that don't exist in Cursor: the \`Agent\`/\`Task\` subagent tool,
the \`Skill\` tool, \`TodoWrite\` as a structured artifact. Substitutes: plain markdown task
lists in chat; \`@rule\` mentions instead of skill invocation; file reads instead of agent dispatch.

`;

// ─── shared memory section appended to every persona rule (§3.6) ────────────

function memorySection(persona, claudeAgentFile) {
  return `
## Persistent knowledge base

You share a persistent, versioned memory with the Claude Code version of this persona at
\`.claude/agent-memory/${persona}/\`. **Read from it** whenever a memory seems relevant.
**Writing to it from Cursor is allowed but must follow the same schema** (see
\`.claude/agents/${claudeAgentFile}\` for the "Persistent Agent Memory" section). Prefer
appending over editing. Commits to this directory are how the team accumulates knowledge
across both tools.
`;
}

// ─── frontmatter templates (§6) ─────────────────────────────────────────────

const FRONTMATTER = {
  albus: `---
description: "Albus — senior architect persona. Invoke at the start of any non-trivial feature or Jira ticket kickoff. Analyzes existing patterns, designs the architecture, breaks work into tasks, and orchestrates the Harry → Hermione → Ron chain via explicit persona switches."
alwaysApply: false
---`,

  harry: `---
description: "Harry — fullstack implementation persona. Adopt after Albus has produced an architecture blueprint. Implements DB / API / frontend changes following the blueprint. Hands off to Hermione when a reviewable diff is ready."
alwaysApply: false
---`,

  hermione: `---
description: "Hermione — code review persona. Adopt after Harry produces a diff. Reviews for correctness, edge cases, security, and adherence to Albus's blueprint. Hands off to Ron when the diff is approved."
alwaysApply: false
---`,

  ron: `---
description: "Ron — docs maintainer persona. Adopt after Hermione approves a diff. Updates README, CLAUDE.md, and other docs so they stay in sync with merged changes."
globs: ["**/README*", "**/*.md", "CLAUDE.md", ".cursor/rules/**"]
alwaysApply: false
---`,

  jiraStart: `---
description: "Kick off work on a Jira ticket: prompt for ticket key + repo path, fetch via Atlassian MCP, create a git worktree at .worktrees/<KEY>, write a structured brief, then switch to the Albus persona. Trigger via @jira-start or phrases like 'start jira ticket', 'work on PROJ-123', 'new ticket'."
alwaysApply: false
---`,
};

// ─── handoff footers (§3.3 + task 1.2) ─────────────────────────────────────

const FOOTERS = {
  albus: `
---

> **Handoff — Albus → Harry:** When the architecture is ready and tasks are broken down,
> switch to Harry by reading \`.cursor/rules/harry-developer.mdc\` and adopting that persona
> for implementation. Announce: "Switching to Harry (fullstack-developer)."
> After Harry's work, switch to Hermione (\`.cursor/rules/hermione-reviewer.mdc\`) for review,
> then Ron (\`.cursor/rules/ron-docs.mdc\`) for docs.
`,

  harry: `
---

> **Handoff — Harry → Hermione:** When implementation is complete and a reviewable diff is
> ready, switch to Hermione by reading \`.cursor/rules/hermione-reviewer.mdc\` and adopting
> that persona. Announce: "Switching to Hermione (code-reviewer)."
`,

  hermione: `
---

> **Handoff — Hermione → Ron:** When the diff is approved, switch to Ron by reading
> \`.cursor/rules/ron-docs.mdc\` and adopting that persona. Announce: "Switching to Ron
> (docs-maintainer)."
`,

  ron: `
---

> **Terminal persona — Ron:** Ron has no automatic handoff. When documentation is updated,
> summarize every file you changed or created and report back to the user. The chain is
> complete.
`,
};

// ─── persona rule generator ──────────────────────────────────────────────────

function buildPersonaRule(frontmatter, body, footer, memSection) {
  return `${frontmatter}\n\n${CURSOR_PREFACE}${body}\n${memSection}${footer}`;
}

// ─── jira-start transformer (§3.4) ──────────────────────────────────────────

function buildJiraStartRule(rawSkillMd) {
  // Strip skill YAML frontmatter
  let body = stripClaudeFrontmatter(rawSkillMd);

  // Apply Cursor-specific string replacements (§3.4 transformation table)
  const replacements = [
    // Step 1 — inputs: replace AskUserQuestion with plain chat instruction
    [
      `Use \`AskUserQuestion\` to ask for:

1. **Jira ticket key** (e.g. \`PROJ-123\`). Free text. Validate format \`^[A-Z][A-Z0-9]+-\\d+$\`.
2. **Target repo absolute path**. Free text. Default to the current working directory if it's a git repo.

Do not guess — always ask, even if a key appears elsewhere in context.`,
      `Ask the user in chat for:

1. **Jira ticket key** (e.g. \`PROJ-123\`). Free text. Validate format \`^[A-Z][A-Z0-9]+-\\d+$\` before proceeding. Do not guess.
2. **Target repo absolute path**. Free text. Default to the current working directory if it's a git repo.

Do not guess — always ask, even if a key appears elsewhere in context.`,
    ],

    // Step 4 — branch already exists: replace AskUserQuestion reference
    [
      `ask the user via \`AskUserQuestion\` whether to (a) reuse it`,
      `ask the user in chat whether to (a) reuse it`,
    ],

    // Step 4 — worktree already exists: replace AskUserQuestion reference
    [
      `ask whether to reuse it, remove+recreate, or abort.`,
      `ask the user in chat whether to reuse it, remove+recreate, or abort.`,
    ],

    // Step 5 — delegate to code-architect: replace Agent tool invocation
    [
      `## Step 5 — Delegate to code-architect (Albus)

Invoke the agent via the \`Agent\` tool:

- \`subagent_type: "code-architect"\`
- \`description\`: "Kick off <TICKET>: <short summary>"
- \`prompt\`: include the full \`.jira-brief.md\` contents inline, the worktree absolute path, the Jira URL, and an explicit instruction: "Treat \`<worktree path>\` as your working directory. Follow your normal chain: analyze patterns, design the architecture, delegate implementation to the fullstack-developer (Harry), then hand off to hermione-code-reviewer and ron-docs-maintainer as appropriate. Do not modify files outside the worktree."
- Do NOT pass \`isolation: worktree\` — the worktree we created IS the isolation.`,
      `## Step 5 — Switch to Albus persona

Read \`.cursor/rules/albus-architect.mdc\` and adopt that persona. Pass the full
\`.jira-brief.md\` contents inline as your working context. Treat \`<worktree path>\` as cwd.
Follow Albus's normal chain (persona switches per the Cursor preface): analyze patterns,
design the architecture, then switch to Harry for implementation, Hermione for review,
and Ron for docs. Do not modify files outside the worktree.`,
    ],

    // Step 6 — parallel tickets note: replace Claude-specific session wording
    [
      `Tell the user they can open a separate Claude session with \`cwd=<worktree>\` to continue work in parallel with other tickets.`,
      `Tell the user they can open the worktree as a separate Cursor workspace/window (File → Open Folder → \`<repo>/.worktrees/<KEY>\`) to work on tickets in parallel.`,
    ],

    // Parallel tickets section — replace Claude session wording with Cursor workspace wording
    [
      `open each worktree in its own Claude session to work on tickets concurrently.`,
      `open each worktree as its own Cursor workspace/window (File → Open Folder → \`<repo>/.worktrees/<KEY>\`) to work on tickets concurrently.`,
    ],
  ];

  for (const [from, to] of replacements) {
    if (!body.includes(from)) {
      console.error(`WARNING: jira-start replacement not found in source:\n  "${from.slice(0, 80)}..."`);
    }
    body = body.replace(from, to);
  }

  // Guardrails addendum (§3.4)
  const guardrailAddendum = `- **Do not open a new Cursor window per ticket expecting session isolation** — Cursor sessions don't map 1:1 to worktrees the way Claude Code sessions do. Instead, open the worktree as a separate Cursor workspace/window (\`File → Open Folder → <repo>/.worktrees/<KEY>\`) if parallel work is desired.`;

  body = body.replace(
    '## Parallel tickets',
    `${guardrailAddendum}\n\n## Parallel tickets`,
  );

  return `${FRONTMATTER.jiraStart}\n\n${body}`;
}

// ─── main ────────────────────────────────────────────────────────────────────

let wrote = 0;
let unchanged = 0;

function track(didWrite) {
  if (didWrite) wrote++;
  else unchanged++;
}

// 1. .cursor/mcp.json — byte-identical copy of .mcp.json (§5.4, §8 no env-expand)
const mcpJson = read('.mcp.json');
track(writeIdempotent('.cursor/mcp.json', mcpJson));

// 2. .cursor/README.md (§5.8)
const cursorReadme = `# .cursor/ — generated files

> **Do not edit these files by hand.**
> They are generated from \`.claude/\` by \`scripts/sync-cursor.mjs\`.
> After editing any \`.claude/agents/*.md\` or \`.mcp.json\`, run:
>
>     node scripts/sync-cursor.mjs
>
> Then commit the regenerated \`.cursor/\` files alongside the \`.claude/\` changes.

## What's here

| File | Source |
|------|--------|
| \`mcp.json\` | \`.mcp.json\` (byte-identical copy) |
| \`rules/albus-architect.mdc\` | \`.claude/agents/code-architect.md\` |
| \`rules/harry-developer.mdc\` | \`.claude/agents/fullstack-developer.md\` |
| \`rules/hermione-reviewer.mdc\` | \`.claude/agents/hermione-code-reviewer.md\` |
| \`rules/ron-docs.mdc\` | \`.claude/agents/ron-docs-maintainer.md\` |
| \`rules/jira-start.mdc\` | \`.claude/skills/jira-start/SKILL.md\` |

## MCP server approval

On first open, Cursor will prompt you to approve MCP servers from \`mcp.json\`.
Approve all four: **context7**, **figma**, **playwright**, **atlassian**.
Set \`FIGMA_API_KEY\` in your environment if you use the Figma server.
`;
track(writeIdempotent('.cursor/README.md', cursorReadme));

// 3. Persona rules
const personas = [
  {
    source: '.claude/agents/code-architect.md',
    target: '.cursor/rules/albus-architect.mdc',
    frontmatter: FRONTMATTER.albus,
    footer: FOOTERS.albus,
    memPersona: 'code-architect',
    memFile: 'code-architect.md',
  },
  {
    source: '.claude/agents/fullstack-developer.md',
    target: '.cursor/rules/harry-developer.mdc',
    frontmatter: FRONTMATTER.harry,
    footer: FOOTERS.harry,
    memPersona: 'fullstack-developer',
    memFile: 'fullstack-developer.md',
  },
  {
    source: '.claude/agents/hermione-code-reviewer.md',
    target: '.cursor/rules/hermione-reviewer.mdc',
    frontmatter: FRONTMATTER.hermione,
    footer: FOOTERS.hermione,
    memPersona: 'hermione-code-reviewer',
    memFile: 'hermione-code-reviewer.md',
  },
  {
    source: '.claude/agents/ron-docs-maintainer.md',
    target: '.cursor/rules/ron-docs.mdc',
    frontmatter: FRONTMATTER.ron,
    footer: FOOTERS.ron,
    memPersona: 'ron-docs-maintainer',
    memFile: 'ron-docs-maintainer.md',
  },
];

for (const p of personas) {
  const raw = read(p.source);
  const body = stripClaudeFrontmatter(raw);
  const mem = memorySection(p.memPersona, p.memFile);
  const content = buildPersonaRule(p.frontmatter, body, p.footer, mem);
  track(writeIdempotent(p.target, content));
}

// 4. jira-start rule
const skillMd = read('.claude/skills/jira-start/SKILL.md');
const jiraContent = buildJiraStartRule(skillMd);
track(writeIdempotent('.cursor/rules/jira-start.mdc', jiraContent));

// ─── summary ─────────────────────────────────────────────────────────────────
console.log(`\nSynced ${wrote + unchanged} files, ${unchanged} unchanged.`);
