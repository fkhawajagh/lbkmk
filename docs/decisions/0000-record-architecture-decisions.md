---
id: ADR-0000
title: Record architecture decisions
status: Accepted
date: 2026-06-02
tags:
  - type/adr
  - topic/process
  - topic/documentation
related:
  - ../solution-proposal.md
  - ../plans/2026-06-02-adr-scaffold-design.md
  - README.md
---

# ADR-0000: Record architecture decisions

## Status

Accepted

## Context and Problem Statement

lbkmk makes architecturally significant decisions — adopting Phoenix LiveView,
mediating all webhook ingestion through Make, keying idempotency on
`(channel, external_event_id)`, and still-open ones such as whether to use Ash.
Until now these have lived only in `CLAUDE.md` prose and project memory. In those
places a decision cannot be cross-referenced, cannot be cleanly superseded, and
loses the trail of alternatives that were weighed. How should the project keep a
durable, traceable record of these decisions and their reasoning?

## Decision Drivers

- **Traceability** — the *why* and the rejected alternatives must survive, not just the verdict.
- **Supersession** — a decision must be replaceable without rewriting history or losing the original.
- **Cross-reference** — decisions must be able to reference one another by a stable ID.
- **Low overhead** — the format must be light enough to actually get written.

## Considered Options

- **MADR-lite ADRs under `docs/decisions/`** — one markdown file per decision, with a sequential ID and a status lifecycle.
- **Keep decisions in `CLAUDE.md` / memory prose** — the status quo.
- **Heavyweight ADR tooling** (e.g. `adr-tools`, generated indexes) — full tooling around the same idea.

## Decision Outcome

Chosen option: **MADR-lite ADRs under `docs/decisions/`**, because it captures the
alternatives and the reasoning at low authoring cost, gives each decision a stable
ID for cross-referencing and supersession, and needs no tooling to start.

### Pros and cons of the options

#### MADR-lite ADRs under `docs/decisions/`
- Good: records the *why* and the rejected options; stable IDs enable supersession and cross-links; an industry-standard, tooling-friendly format; plain markdown that reviews in a PR.
- Bad: the index in `README.md` is maintained by hand.

#### Keep decisions in `CLAUDE.md` / memory prose
- Good: zero new structure.
- Bad: not cross-referenceable; cannot be superseded cleanly; alternatives and reasoning are usually lost; `CLAUDE.md` grows unboundedly.

#### Heavyweight ADR tooling
- Good: automated index and scaffolding.
- Bad: premature for a project with no ADRs yet (YAGNI); adds a dependency and a build step for no current benefit.

## Consequences

- Architecturally significant decisions are recorded as ADRs under `docs/decisions/`, following the convention in [README.md](README.md) and the [template](template.md).
- Each new ADR adds a row to the index table in `README.md` by hand; if that upkeep becomes painful, revisit the no-tooling decision.
- Tagging currently uses `type/adr` + a `topic/` facet only. The `domain/` and `phase/` facets are anchored once the doc tag vocabulary (carry-over item C) lands.
- Settled decisions already made (Phoenix LiveView, Make-mediated ingestion, the idempotency key) are **not** backfilled into ADRs; they can be recorded later as the convention is exercised.
