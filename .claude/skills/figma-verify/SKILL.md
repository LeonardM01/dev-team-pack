---
name: figma-verify
description: "Compare the implemented front-end against a Figma design using visual screenshots and structural analysis. Use after front-end implementation to verify design fidelity, or when the user says verify the design, check against Figma, does this match the mockup, or visual review. Requires a running dev server and a Figma URL. Produces a structured comparison report covering layout, colors, typography, content, and accessibility."
---

# Figma Visual Verification

Compare an implemented front-end against its Figma design source of truth. Produces a structured report of visual and structural differences.

## Preconditions

- A **Figma URL** is available (extract `fileKey` and `nodeId` from it)
- A **dev server is running** at a reachable URL
- If either is missing, prompt the user before proceeding

## Phase 1 — Capture

### Step 1: Get Figma Design

1. Extract `fileKey` and `nodeId` from the Figma URL:
   - `figma.com/design/:fileKey/:name?node-id=:nodeId` — convert `-` to `:` in nodeId
   - `figma.com/design/:fileKey/branch/:branchKey/:name` — use `branchKey` as fileKey
2. Call `get_screenshot(nodeId, fileKey)` to capture the design screenshot
3. Call `get_design_context(nodeId, fileKey)` to get structural metadata: component hierarchy, design tokens (colors, spacing, typography), and layout information

### Step 2: Get Implementation

1. Ask the user for the **dev server URL** if not obvious from the project (e.g., `localhost:3000`, `localhost:5173`)
2. Call `browser_navigate(url)` to load the page
   - If navigation fails, **stop** and ask the user to start the dev server
   - If the page requires authentication, ask the user to log in manually, then proceed
3. Determine viewport(s) to test:
   - **Default**: desktop (1280x800)
   - If the user specifies responsive verification, use: mobile (375x812), tablet (768x1024), desktop (1280x800)
   - If the Figma frame suggests a specific device, match its dimensions
4. For each viewport:
   - Call `browser_resize(width, height)` to set viewport
   - Call `browser_take_screenshot(filename)` to capture the implementation screenshot
   - Call `browser_snapshot()` to capture the accessibility tree

## Phase 2 — Compare

### Step 3: Structural Check (First)

Compare the Playwright accessibility tree against the Figma design context **before** visual comparison. This catches missing or mislabeled elements that a screenshot might not reveal.

Check:
- **Component presence**: Are all components from the Figma hierarchy present in the DOM?
- **Heading hierarchy**: Is h1 → h2 → h3 structure correct?
- **Text accuracy**: Do form labels, button text, link text, and headings match the design?
- **ARIA roles**: Are landmark roles, button roles, and form roles appropriate?
- **Tab order**: Is the interactive element order logical?

### Step 4: Visual Comparison

For each viewport screenshot, compare against the Figma design screenshot. Analyze:

| Dimension | What to check |
|-----------|--------------|
| **Layout** | Component positions, spacing ratios, alignment, grid structure |
| **Colors** | Primary, secondary, backgrounds, text colors, borders, shadows |
| **Typography** | Font families, sizes, weights, line heights, letter spacing |
| **Content** | Correct text, images, icons present and properly placed |
| **Interactive elements** | Buttons, inputs, links present with correct labels and styling |
| **Spacing** | Padding, margins, gaps match design intent |

Categorize every difference as one of:

- **Critical** — Missing sections, wrong layouts, incorrect data flows, broken interactive elements, wrong colors on key UI elements
- **Important** — Color drift beyond minor shade variation, typography inconsistencies (wrong weight, noticeably different size), spacing noticeably off, missing hover/focus states
- **Acceptable** — Font antialiasing differences, sub-pixel rounding, system font fallbacks, scrollbar styling, OS-level rendering differences, minor shadow/blur differences

### Step 5: Responsive Verification (When Applicable)

If testing multiple viewports, also check:
- Layout adapts correctly at each breakpoint (stack, reflow, hide/show)
- Touch targets are appropriately sized on mobile (minimum 44x44px)
- Content doesn't overflow or clip at any width
- Navigation collapses to mobile menu where expected

## Phase 3 — Report

### Step 6: Generate Report

Output a structured Markdown report:

```markdown
# Visual Verification Report

## Design Reference
- Figma URL: [url]
- Node: [nodeId]
- Screenshot: [path]

## Implementation Reference
- URL: [dev server url]
- Viewport(s): [list]

## Structural Comparison

### Component Presence
[Pass/Fail — list any missing components]

### Heading Hierarchy
[Pass/Fail — describe issues]

### Text Accuracy
[Pass/Fail — list mismatches]

### Accessibility
[Pass/Fail — ARIA issues, tab order problems]

## Visual Comparison

### Desktop (1280x800)

#### Critical Issues
[List or "None"]

#### Important Issues
[List or "None"]

#### Acceptable Variations
[List — these are informational, not blockers]

### Mobile (375x812) — if applicable
[same structure]

### Tablet (768x1024) — if applicable
[same structure]

## Overall Verdict

[PASS / PASS WITH NOTES / FAIL]

[1-2 sentence summary explaining the verdict]
```

### Verdict Rules

- **PASS** — No critical or important issues. Only acceptable variations exist.
- **PASS WITH NOTES** — No critical issues, but important issues exist that should be addressed soon. List them clearly.
- **FAIL** — One or more critical issues exist. Implementation does not match the design intent and needs rework before merging.

## Edge Cases

| Situation | Handling |
|-----------|----------|
| No Figma URL provided | Run structural-only check. Note in report that visual comparison was skipped. |
| Dev server not running | Stop and ask user to start it. Do not produce a report. |
| Page requires authentication | Ask user to log in manually, then proceed with capture. |
| Multiple Figma frames | Ask user which frame to verify, or iterate over all child frames. |
| Design uses components not yet in codebase | Flag as critical issue in report. |
| Responsive design specified | Default to testing all three viewports. User can override. |
