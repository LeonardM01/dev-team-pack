---
name: prd-generator
description: "Generate comprehensive Product Requirements Documents (PRDs) through a discovery conversation. Use when users ask to create a PRD, write product requirements, document a feature, write requirements, or need help structuring product specifications. Supports standard, lean, one-pager, and technical PRD formats."
---

# PRD Generator

Generate well-structured Product Requirements Documents that align stakeholders and guide development.

## Step 1 — Discovery

Before generating the PRD, collect essential information. Ask these questions, skipping any the user has already answered in their brief:

```
1. What are we building? (Feature/Product Name)
2. What problem does this solve? (Problem Statement)
3. Who is this for? (Target Users)
4. What are the key business objectives? (Business Goals)
5. How will we measure success? (Success Metrics)
6. Any deadlines or technical constraints? (Timeline/Constraints)
7. What is explicitly out of scope?
```

If the user provides a detailed brief upfront, proceed directly to Step 2. Always ask for clarification on missing critical information.

## Step 2 — Generate PRD

Produce the PRD with these sections (adapt depth based on format):

1. **Executive Summary** — 2-3 paragraph high-level overview
2. **Problem Statement** — Clear articulation of the problem and its impact
3. **Goals & Objectives** — What we're trying to achieve, tied to business value
4. **User Personas** — Who we're building for, their needs and pain points
5. **User Stories & Requirements** — Detailed functional requirements (see Step 3)
6. **Success Metrics** — KPIs and measurement criteria (see Step 4)
7. **Scope** — Explicitly what's in scope AND out of scope
8. **Technical Considerations** — Architecture, dependencies, security, performance, compatibility
9. **Design & UX Requirements** — UI/UX considerations, accessibility (WCAG), responsive design. **Include Figma links here if available.**
10. **Timeline & Milestones** — Key dates and phases
11. **Risks & Mitigation** — Potential issues and solutions
12. **Dependencies & Assumptions** — What we're relying on
13. **Open Questions** — Unresolved items needing resolution

## Step 3 — User Stories

For each major requirement, generate user stories:

```
As a [user type],
I want to [action],
So that [benefit/value].

Acceptance Criteria:
- [Specific, testable criterion 1]
- [Specific, testable criterion 2]
- [Specific, testable criterion 3]
```

Stories should be independent, user-focused, and small enough to estimate. Include clear acceptance criteria. Don't include implementation details.

## Step 4 — Success Metrics

Choose one primary framework based on the product type:

- **AARRR (Pirate Metrics)** — Acquisition, Activation, Retention, Revenue, Referral. Best for growth-focused features.
- **HEART Framework** — Happiness, Engagement, Adoption, Retention, Task Success. Best for UX improvements.
- **North Star Metric** — Single key metric representing core value. Best for product launches.
- **OKRs** — Objectives and Key Results. Best for strategic initiatives.

Define measurable targets for each metric. Include both leading and lagging indicators.

## Step 5 — Quality Checklist

Before finalizing, verify:

- [ ] Problem is clear to anyone reading
- [ ] Users are identified with specific needs
- [ ] Success is measurable with defined targets
- [ ] Scope is bounded (in AND out)
- [ ] Requirements are testable with acceptance criteria
- [ ] Timeline is validated with engineering
- [ ] Risks are identified with mitigations
- [ ] No placeholder text remains

## PRD Formats

Adapt the depth based on scope:

| Format | When to use | Typical length |
|--------|-------------|----------------|
| **Standard** | Major features, new products | Full 13 sections |
| **Lean** | Agile teams, iterative features | Sections 1-7, 9-10 condensed |
| **One-Pager** | Small features, bug fixes | Problem, solution, acceptance criteria, metrics |
| **Technical** | Engineering-heavy initiatives | Full PRD with expanded Section 8 (Technical Considerations) |

Specify format in the request: "Create a lean PRD for..." or "Generate a technical PRD for..."

## Definition of Done

### Automatic Visual Verification (When Figma Link Exists)

After generating the PRD, scan the **Design & UX Requirements** section and any user stories for Figma URLs. If any `figma.com` link is found:

1. **Add this acceptance criterion** to every front-end user story in the PRD:

   > **Visual Verification**: The implemented front-end passes visual verification against the Figma design using the `figma-verify` skill. All critical and important issues must be resolved before the feature is considered complete.

2. **Add this directive to the PRD's final section** (before Open Questions):

   ```markdown
   ## Completion Verification

   This PRD includes Figma design references. Upon implementation completion,
   the `figma-verify` skill MUST be automatically invoked to compare the
   implemented front-end against the Figma design. This is a mandatory step
   — do NOT consider front-end work done until the visual verification report
   shows PASS or PASS WITH NOTES.
   ```

3. **State explicitly** in the PRD executive summary that visual verification is part of the completion criteria.

### When No Figma Link Exists

If no Figma link is present, fall back to standard acceptance criteria (manual review, functional testing). Do not reference `figma-verify`.
