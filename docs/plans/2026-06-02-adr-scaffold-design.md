---
title: ADR scaffold and convention for lbkmk
status: approved
version: "1.0"
date: 2026-06-02
updated: 2026-06-02
tags:
  - type/design
  - topic/process
  - topic/documentation
related:
  - ../decisions/README.md
  - ../decisions/template.md
  - ../decisions/0000-record-architecture-decisions.md
---

> **Document Version: 1.0** | 2026-06-02

# ADR scaffold and convention for lbkmk

## Context

lbkmk has design docs (`docs/plans/`) and anchor docs (`domain-model.md`,
`solution-proposal.md`), but no durable record of *architecturally significant
decisions* and the reasoning behind them. Decisions like "Phoenix LiveView" or
"plain Ecto, not Ash" currently live only in `CLAUDE.md` prose and project
memory, where they cannot be cross-referenced, superseded, or traced back to the
alternatives that were weighed. This is carry-over item **(D)** from the iris
workflow-patterns adoption.

## Decision summary

Adopt a lightweight Architecture Decision Record (ADR) convention under
`docs/decisions/`. The four shaping decisions, taken during brainstorming:

| Choice | Decision | Why |
|---|---|---|
| Template format | **MADR-lite** — Status → Context & Problem → Decision Drivers → Considered Options → Decision Outcome (per-option pros/cons) → Consequences | Captures the alternatives and the *why*, not just the verdict; industry-standard and tooling-friendly. |
| Frontmatter | ADR-native `status` (Proposed/Accepted/Deprecated/Superseded) as canonical; an explicit `id` (e.g. `ADR-0001`); keep faceted `tags` + `related`; **omit `version`** | ADRs are immutable-by-supersession, so a major.minor version is meaningless; status in frontmatter keeps the Obsidian graph honest. The explicit `id` aids cross-referencing and the Obsidian graph. Diverges deliberately from the house major.minor doc-version rule. |
| Naming | **`NNNN-slug.md`**, zero-padded; date in frontmatter | Stable sequential IDs let ADRs cross-reference each other ("superseded by ADR-0007"); ordered by decision sequence. Diverges from the date-prefixed `docs/plans/` style — intentional, ADRs are their own doc type. |
| Seed | `0000-record-architecture-decisions.md` (Accepted) only | A complete, non-controversial meta-ADR that documents the convention itself and doubles as the first worked example. No unsettled decision (e.g. "no Ash") is asserted as Accepted. |

## Scaffold contents

```
docs/decisions/
  README.md       # convention (when/format/status/naming/how-to) + index table
  template.md     # blank MADR-lite, copy to NNNN-slug.md
  0000-record-architecture-decisions.md   # meta-ADR, status Accepted
```

- `status` is mirrored in frontmatter (machine-canonical) and a one-line body
  `## Status` (human-facing MADR convention); the README declares frontmatter
  canonical and that the two stay in sync.
- Tagging uses only `type/adr` + a `topic/` value for now. The `domain/` and
  `phase/` facets are anchored once carry-over item **(C) doc tag vocabulary**
  lands; the README records this dependency.

## Relationship to existing docs

- **ADR vs design doc:** an ADR records *the decision and why*; a `docs/plans/`
  design doc records *the how / the plan*. They cross-link. This very document is
  the design doc for the scaffold; [ADR-0000](../decisions/0000-record-architecture-decisions.md)
  is the decision to adopt ADRs.
- **Superseding:** never edit an Accepted ADR's decision in place — write a new
  ADR and flip the old one's `status` to `Superseded`.

## Out of scope

- No automation/tooling (no `adr-tools`, no index-generation script) — the index
  in `README.md` is maintained by hand. Add tooling only if the ADR count makes
  manual upkeep painful (YAGNI).
- No backfill of past decisions (Phoenix LiveView, Make-mediated ingestion,
  etc.) into ADRs — those can be recorded later as the convention is exercised.
