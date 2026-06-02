---
title: Document tag vocabulary
status: active
version: "1.0"
date: 2026-06-02
updated: 2026-06-02
tags:
  - type/reference
  - topic/process
  - topic/documentation
related:
  - plans/2026-06-02-doc-tag-vocabulary-design.md
  - decisions/README.md
  - solution-proposal.md
---

> **Document Version: 1.0** | 2026-06-02

# Document tag vocabulary

This is the **single source of truth** for the tags used in lbkmk document
frontmatter. Tags are **faceted** and drawn from a **controlled vocabulary**:
free-typed tags (`auth` vs `authz` vs `authorization`) fragment the document
graph into useless near-duplicates, so every value used in a doc must appear in
the lists below.

The design behind this vocabulary is
[`plans/2026-06-02-doc-tag-vocabulary-design.md`](plans/2026-06-02-doc-tag-vocabulary-design.md).

## How tags work

- Tags live in a document's YAML frontmatter, as a `tags:` list.
- Each tag is a `facet/value` string — the facet groups related values so the tag
  tree collapses cleanly (e.g. all `external/*` values sit under one node).
- Use only the values defined in this document. The one exception is the `topic/`
  facet, which grows deliberately (see [Growing and changing the vocabulary](#growing-and-changing-the-vocabulary)).

Example frontmatter:

```yaml
tags:
  - type/design
  - phase/1-foundation
  - domain/ingest
  - external/squarespace
  - topic/process
```

## Facets at a glance

| Facet | Cardinality | What it captures |
|---|---|---|
| `type/` | exactly one (required) | The kind of document. |
| `phase/` | zero or one | The delivery phase the document is scoped to. |
| `domain/` | zero or more | The engineering subsystem(s) / bounded context(s) it touches. |
| `external/` | zero or more | The third-party system(s) it concerns. |
| `topic/` | zero or more | Cross-cutting threads that link documents across phases and domains. |

## Controlled values

### `type/` — document kind (exactly one, required)

Anchored to this document.

| Value | Use for |
|---|---|
| `type/spec` | Contract documents the system is built around — `domain-model.md`, `solution-proposal.md`. |
| `type/design` | A design doc (what / why) for a feature or convention. |
| `type/plan` | An implementation plan (how / steps). |
| `type/adr` | An Architecture Decision Record (see `decisions/README.md`). |
| `type/reference` | Standing reference material — this document, the integration docs, conventions. |
| `type/review` | A review, analysis, or delta artifact. |

### `phase/` — delivery phase (zero or one)

Anchored to [`solution-proposal.md`](solution-proposal.md) §14. A standing or
cross-phase document omits this facet.

| Value | Phase |
|---|---|
| `phase/0-discovery` | Phase 0 — Discovery (close open questions). |
| `phase/1-foundation` | Phase 1 — End-to-end proof with Squarespace + Stripe + Xero. |
| `phase/2-channels` | Phase 2 — Add Square and TicketTailor; cross-channel correlation. |
| `phase/3-reconciliation` | Phase 3 — Reconciliation sweep + payouts view. |
| `phase/4-hardening` | Phase 4 — Hardening, audit UI, invoice void. |

### `domain/` — engineering subsystem (zero or more)

Anchored to the Phoenix contexts in `CLAUDE.md` (Architecture Conventions). These
are stable engineering names, deliberately **not** the owner-facing terms still
open in `domain-model.md` §7.

| Value | Subsystem |
|---|---|
| `domain/ingest` | Webhook ingestion and idempotency (`Lbkmk.Ingest`). |
| `domain/reconciliation` | Sale/payment correlation and drift (`Lbkmk.Reconciliation`). |
| `domain/inventory` | Stock tracking, decrement, channel-SKU mapping (`Lbkmk.Inventory`). |
| `domain/posting` | Itemized invoice posting to Xero. |
| `domain/audit` | Audit trail and traceability. |

### `external/` — third-party system (zero or more)

Anchored to the per-tool references under [`integrations/`](integrations/).

`external/squarespace`, `external/stripe`, `external/square`,
`external/tickettailor`, `external/xero`, `external/make`.

### `topic/` — cross-cutting thread (zero or more)

The **open** facet. Seed values:

`topic/process`, `topic/documentation`.

These are the only `topic/` values currently in use; the facet grows from here as
documents introduce new cross-cutting threads (see
[Growing and changing the vocabulary](#growing-and-changing-the-vocabulary)).

## Growing and changing the vocabulary

- **`topic/` is open.** When a document needs a cross-cutting thread not listed
  above, add the new value to the `topic/` list here in the **same PR** that first
  uses it. Never free-type a `topic/` value that is not in this list.
- **The other facets are closed.** `type/`, `phase/`, `domain/`, and `external/`
  change only when their anchor source changes — a new delivery phase
  (`solution-proposal.md` §14), a new integration (`integrations/`), or a new
  bounded context (`CLAUDE.md`). Update the anchor source and this document
  together, in the same change.
- This document is a living reference: bump its `major.minor` version when facets
  or values change (major when a facet is added or removed, minor when values
  within a facet change).
