---
title: Project-status YAML for lbkmk
status: approved
version: "1.0"
date: 2026-06-02
updated: 2026-06-02
tags:
  - type/design
  - topic/process
  - topic/documentation
related:
  - ../solution-proposal.md
  - ../tags.md
---

> **Document Version: 1.0** | 2026-06-02

# Project-status YAML for lbkmk

## Context

This is carry-over item **(E)** from the iris workflow-patterns adoption. The iris
project (`~/src/iris`) maintains `docs/project-status.yaml` — a canonical,
machine-readable record of every phase and sub-phase — so external
project-management tools can consume project status without scraping Markdown. It
is validated by a Mix task, documented by a CLAUDE.md "Project Status Tracking"
subsection, and **coexists** with the same "status is a query, not a tracker"
rule lbkmk already carries.

lbkmk has no such structured record today. Status lives only in the live query
(open PRs, issues, handoffs, git log) and in prose. This design carries the iris
pattern into lbkmk, adapted to two differences: lbkmk has **no Elixir app yet**
(so iris's Mix validator cannot be lifted), and lbkmk is far earlier — five
delivery phases, all pre-build.

## How this resolves the apparent conflict

lbkmk's CLAUDE.md says project status is "a query, not a tracker; do NOT create or
modify a status doc." iris carries the identical rule **and** a status YAML,
without contradiction, by separating two concepts:

- **Project status (the query)** — the live, human-facing "where are we" narrative,
  synthesized on demand from PRs/issues/handoffs/git. Never a stored document.
- **Project status tracking (the YAML)** — a structured, machine-readable record of
  the phase/sub-phase lattice for tooling. Not the human narrative.

The existing "Project Status" (query) section is left unchanged; a new "Project
Status Tracking" section documents the YAML alongside it.

## Decision summary

| Choice | Decision | Why |
|---|---|---|
| Verification | **Defer the validator.** Ship the YAML + JSON Schema + CLAUDE.md protocol; no validator script, no CI. | With 5 phases all pre-build, the file is tiny and rarely edited — a validator solves drift that does not exist yet (YAGNI). The schema still fixes the shape. Add a validator (Python, or a Mix task once `mix.exs` lands) when the file grows. |
| Coverage | **Five delivery phases (0–4) only**, as phase-level entries. | Mirrors §14 and aligns with the `phase/` tag facet. No sub-phases yet (added when a phase is decomposed). The doc-convention/process carry-over work is meta-infra, tracked via PRs/issues — not the product roadmap. |
| Schema shape | **Reuse iris's shape** (draft-07), minus dead weight. | Clean and general; a future shared tool/consumer sees the same contract. lbkmk tweaks: `schema_version` starts at `"1.0"`; drop iris's HTTPS `$id` (no lbkmk domain) and its unused top-level `questions` array. |
| `stage` for pre-build phases | **Keep iris's enum** (`Design → Plan → Implementation → Review → Merged`); all entries sit at `Design` for now, `status` carries the real signal. | Avoids inventing a new vocabulary for a transient state; when product work begins, phases advance through the real stages. |

## Schema

`docs/project-status.schema.json` — JSON Schema (draft-07), shape carried over from
iris:

- **Top level:** `schema_version` (string, `^\d+\.\d+$`), `updated_on` (ISO date),
  `phases` (array).
- **Phase entry** (`additionalProperties: false`, all fields required):
  `key` (`^\d+(\.\d+)*[a-z]?$`), `title`, `stage` (enum), `status` (enum),
  `doc_slug` (string|null, no `docs/` prefix, no `.md`), `depends_on` (array of
  keys), `pr_numbers` (array of int), `started_on` (date|null), `completed_on`
  (date|null), `open_questions` (array).
- **Open-question entry:** `slug` (kebab-case), `body`.

lbkmk tweaks: `schema_version` begins at `"1.0"`; iris's HTTPS `$id` and its
unused top-level `questions` array are dropped (a `title` is kept).

## Initial content

Five phase-level entries from [`solution-proposal.md`](../solution-proposal.md) §14:

| key | title | stage | status | depends_on | started_on |
|---|---|---|---|---|---|
| `0` | Discovery | Design | In Progress | `[]` | `2026-05-22` (approx.) |
| `1` | End-to-end proof (Squarespace + Stripe + Xero) | Design | Pending | `["0"]` | `null` |
| `2` | Add Square + TicketTailor | Design | Pending | `["1"]` | `null` |
| `3` | Reconciliation sweep + payouts | Design | Pending | `["2"]` | `null` |
| `4` | Hardening, audit UI, invoice void | Design | Pending | `["3"]` | `null` |

- `doc_slug: "solution-proposal"` for every entry (the doc that defines the phases;
  there are no per-phase docs yet).
- `pr_numbers: []` and `completed_on: null` everywhere (no product code shipped).
- Phase 0 `started_on` is the first anchor-doc date, marked approximate.

### Open questions

Populated by **referencing** the blocking issues, not duplicating the domain model:

- **Phase 1** carries the four blocking scope questions — bank-rule configuration
  (#51), Xero plan tier (#55), chart-of-accounts mapping (#56), event-specific
  ticket caps (#53) — as `open_questions`, since Phase 1 is the first phase that
  needs Xero.
- **Phase 0** carries the three §7 vocabulary questions (Approval / Drift / Channel
  SKU), since locking the vocabulary is a discovery task.

Each `body` is one or two sentences citing its issue.

## CLAUDE.md update protocol

A new "Project Status Tracking" subsection, adjacent to the existing "Project
Status" (query) section, stating:

- `docs/project-status.yaml` is the canonical machine-readable phase record; it
  coexists with the query rule (query = live narrative; YAML = structured record).
- The orchestrator hand-edits at three triggers:
  1. **Phase work starts** — set `status: In Progress`, `started_on: <today>`.
  2. **Stage / PR advances** — bump `stage`; append the PR number to `pr_numbers`.
  3. **Phase completes (PR merged, glean done)** — set `stage: Merged`,
     `status: Completed`, `completed_on: <merge date>`; copy any deferred-work items
     into `open_questions`.
- `updated_on` is set on every edit.
- The schema fixes the shape; adding a field bumps `schema_version` and the schema
  together, in the same commit.
- The validator is deferred; wire one in (Python, or a Mix task once `mix.exs`
  lands) when the file grows enough to drift.

## Out of scope

- No validator script and no CI workflow (deferred, per the decision above).
- No sub-phase decomposition (phases appear as phase-level entries until a phase is
  broken down).
- No generation of other docs from the YAML, no auto-derivation from PRs/git, no UI.
- The doc-convention/process carry-over work (handoff convention, ADR scaffold, tag
  vocabulary) is not tracked as a phase.
