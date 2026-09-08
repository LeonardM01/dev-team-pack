---
name: grill-with-docs
description: A relentless interview to sharpen a plan or design, which also creates docs (ADR's and glossary) as we go. Invoked by the user via /grill-with-docs, or by the code-architect agent (Albus) at the start of a plan. No other agent or session should invoke it on its own.
---

Run a `/grilling` session, using the `/domain-modeling` skill.

Who may run this: the user (`/grill-with-docs`) and the code-architect agent (Albus), who invokes it before producing a blueprint. If you are any other agent, or the main session acting without an explicit user request, do not invoke this skill - ask the user or hand off to Albus instead.
