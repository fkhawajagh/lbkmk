---
title: Architecture Decision Records
status: active
version: "1.0"
date: 2026-06-02
updated: 2026-06-02
tags:
  - type/reference
  - topic/process
  - topic/documentation
related:
  - ../plans/2026-06-02-adr-scaffold-design.md
  - template.md
  - 0000-record-architecture-decisions.md
---

> **Document Version: 1.0** | 2026-06-02

# Architecture Decision Records

This directory records lbkmk's **architecturally significant decisions** — the
choices that shape the system's structure, the alternatives that were weighed,
and the reasoning behind the verdict. An ADR is a short, immutable-by-supersession
markdown file; the set of ADRs is the project's decision log.

The convention itself is recorded as [ADR-0000](0000-record-architecture-decisions.md),
which doubles as the first worked example. The design behind this scaffold is
[`../plans/2026-06-02-adr-scaffold-design.md`](../plans/2026-06-02-adr-scaffold-design.md).

## When to write an ADR

Write an ADR when a decision is **architecturally significant** — it affects the
system's structure, dependencies, public interfaces, a cross-cutting concern, or
is costly to reverse. Examples: choosing a framework, a persistence approach, an
integration boundary, or an idempotency strategy.

Do **not** write an ADR for routine implementation choices, naming, or anything
already captured fully in a `docs/plans/` design doc. When in doubt, ask: "would a
future maintainer be surprised by this, and need to know *why* we chose it over
the alternative?" If yes, write the ADR.

## Format

ADRs follow a lightweight [MADR](https://adr.github.io/madr/) structure. The
section sequence, captured in [`template.md`](template.md), is:

1. **Status** — one line, mirrors the frontmatter `status`.
2. **Context and Problem Statement** — the forces at play and the question that needs a decision.
3. **Decision Drivers** — the criteria that matter for choosing.
4. **Considered Options** — the candidate options, named.
5. **Decision Outcome** — the chosen option and its justification, with per-option pros and cons.
6. **Consequences** — what becomes easier or harder as a result.

## Status vocabulary

The lifecycle status is **ADR-native**, not the house `major.minor` document
version (ADRs carry no `version` — they are immutable by supersession). Allowed
values:

| Status | Meaning |
|---|---|
| `Proposed` | Under discussion; not yet adopted. |
| `Accepted` | Adopted; the decision is in force. |
| `Deprecated` | Discouraged, but not replaced by a specific later decision. |
| `Superseded` | Replaced by a later ADR (link it: "Superseded by ADR-NNNN"). |

The frontmatter `status` is **canonical** (it keeps the Obsidian graph honest);
the one-line `## Status` in the body mirrors it. Keep the two in sync.

## Naming

ADR files are named **`NNNN-slug.md`** — a zero-padded four-digit sequential ID
(the next free integer) plus a short kebab-case slug. The decision date lives in
the frontmatter, **not** in the filename. This deliberately diverges from the
date-prefixed `docs/plans/` style: ADRs are their own document type, and a stable
sequential ID is what lets one ADR cross-reference another.

In prose, refer to an ADR by its ID — "ADR-0007", "Superseded by ADR-0012".

## How to add an ADR

1. Copy [`template.md`](template.md) to `NNNN-slug.md`, using the next free
   zero-padded ID.
2. Fill in the frontmatter (`id`, `title`, `status`, `date`, `tags`, `related`)
   and every section; delete the copy note.
3. Set `status: Proposed` while the decision is under discussion, or `Accepted`
   if it is already settled.
4. Add a row to the [index](#index) below.
5. Commit.

## ADR vs design doc

An **ADR** records *the decision and why* — it is immutable by supersession. A
`docs/plans/` **design doc** records *the how / the plan* — it is revised in place
and carries a `major.minor` version. They cross-link: a design doc references the
ADR that justifies its approach, and an ADR can point to the design doc that
elaborates the chosen option.

## Superseding an ADR

Never edit an Accepted ADR's decision in place. Instead:

1. Write a new ADR that records the replacement decision; note "Supersedes ADR-NNNN" in it.
2. Set the old ADR's `status` to `Superseded` (in both frontmatter and the body), and add "Superseded by ADR-MMMM".

The original ADR stays in the log as the historical record.

## Tagging

Every ADR carries `type/adr` plus at least one `topic/` facet, and may add
`domain/`, `phase/`, or `external/` facets where relevant. All values come from
the controlled vocabulary in [`../tags.md`](../tags.md) — choose existing values
rather than free-typing new ones; a new `topic/` value is added to `../tags.md`
in the same PR that first uses it.

## Index

Maintained by hand — add a row when you add an ADR.

| ADR | Title | Status | Date |
|---|---|---|---|
| [ADR-0000](0000-record-architecture-decisions.md) | Record architecture decisions | Accepted | 2026-06-02 |
