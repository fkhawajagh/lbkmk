---
title: Doc tag vocabulary for lbkmk
status: approved
version: "1.0"
date: 2026-06-02
updated: 2026-06-02
tags:
  - type/design
  - topic/process
  - topic/documentation
related:
  - ../tags.md
  - ../decisions/README.md
  - ../solution-proposal.md
---

> **Document Version: 1.0** | 2026-06-02

# Doc tag vocabulary for lbkmk

## Context

The global documentation conventions require document frontmatter tags to be
**faceted** and drawn from a **controlled vocabulary**, with each project defining
its own concrete values. lbkmk has begun tagging docs (the ADR scaffold uses
`type/`, `topic/`), but the controlled value lists were never written down, so
there is nothing to anchor tags against — the exact failure mode the global rule
warns about (`auth` vs `authz` vs `authorization` fragmenting the graph). The ADR
convention (`docs/decisions/README.md`) explicitly **deferred** anchoring the
`domain/` and `phase/` facets "until carry-over item (C) doc tag vocabulary
lands." This is that item.

## Decision summary

Add a single, self-contained, project-local reference doc — **`docs/tags.md`** —
that defines lbkmk's faceted tag vocabulary: the facets, their cardinality, the
controlled value lists, and the rules for applying and growing them. It is the
single source of truth for the vocabulary.

Shaping decisions taken during brainstorming:

| Choice | Decision | Why |
|---|---|---|
| Deliverable | A single reference doc, `docs/tags.md` (`type/reference`, `status: active`, `major.minor` version) | The global rules live in `~/.dotfiles` (outside this repo), invisible on GitHub; the project doc must restate the rules so it stands alone. |
| Record as ADR? | **No** — reference doc only | Mirrors how the ADR convention itself lives in `docs/decisions/README.md` (a reference doc, not an ADR). Avoids a decision-vs-detail split for a documentation convention. |
| Retro-tagging | **Out of scope** | Existing docs adopt the vocabulary lazily as they are next touched; no frontmatter sweep in this change. |

## Facets, cardinality, and seed values

Each value is anchored to a canonical source so the vocabulary cannot drift.

| Facet | Cardinality | Seed values | Anchored to |
|---|---|---|---|
| `type/` | exactly one (required) | `spec`, `design`, `plan`, `adr`, `reference`, `review` | this doc (`docs/tags.md`) |
| `phase/` | zero or one | `0-discovery`, `1-foundation`, `2-channels`, `3-reconciliation`, `4-hardening` | `solution-proposal.md` §14 |
| `domain/` | zero or more | `ingest`, `reconciliation`, `inventory`, `posting`, `audit` | `CLAUDE.md` Architecture Conventions (Phoenix contexts) |
| `external/` | zero or more | `squarespace`, `stripe`, `square`, `tickettailor`, `xero`, `make` | `docs/integrations/*` |
| `topic/` | zero or more | `process`, `documentation` (the values in use; the facet grows on first use) | this doc (open/growing facet) |

Notes on specific values:

- **`type/spec`** is for the contract docs (`domain-model.md`, `solution-proposal.md`),
  which are more than reference material — they are the contract the system is
  built around.
- **`phase/`** slugs combine the number (for ordering) and a short name, mapping to
  `solution-proposal.md` §14: 0 Discovery, 1 End-to-end proof, 2 Add Square +
  TicketTailor, 3 Reconciliation sweep + payouts, 4 Hardening.

## Application and growth rules

`docs/tags.md` will state:

1. Tags live in the YAML frontmatter `tags:` list as `facet/value` strings.
2. Every value must come from the controlled list in `docs/tags.md`.
3. `topic/` is the **one open facet** — a new `topic/` value is added to
   `docs/tags.md` in the same PR that first uses it (grow deliberately, never
   free-type).
4. The other facets are **closed**: they change only when their anchor source
   changes — a new delivery phase (§14), a new integration, or a new bounded
   context. Update both the anchor source and `docs/tags.md` together.
5. `docs/tags.md` is a living reference doc: `status: active`, `major.minor`
   version, bumped when facets or values change.

## Open-questions-gate handling

The `domain/` facet deliberately uses stable **engineering subsystem** names
(`ingest`, `reconciliation`, `inventory`, `posting`, `audit`) — the Phoenix
contexts — and **not** the owner-facing terms still open in `domain-model.md` §7
("Approval", "Drift", "Channel SKU"). Defining the vocabulary therefore does not
depend on, and does not pre-empt, those open vocabulary questions: it does not
trip the open-questions gate.

## Relationship to existing docs

- **ADR README touch-up (in scope).** `docs/decisions/README.md` currently says the
  `domain/` and `phase/` facets are "not yet anchored … until carry-over item (C)
  doc tag vocabulary lands." Since (C) is landing, that paragraph is updated to
  point at `docs/tags.md` and drop the "deferred" wording — otherwise it is an
  immediately-stale reference. This is the only edit outside the new file.
- **This design doc** dogfoods the vocabulary in its own frontmatter
  (`type/design`, `topic/process`, `topic/documentation`).

## Out of scope

- No retro-tagging or frontmatter migration of existing docs (anchor docs,
  integration docs, plans, branding). They adopt the vocabulary as they are next
  edited.
- No tooling — no tag linter or graph generator. Add only if drift becomes a real
  problem (YAGNI).
- No ADR recording this decision (reference doc only, per the table above).
