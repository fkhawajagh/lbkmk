---
title: Reconciliation Catalog — doc clarification design
version: "1.0"
date: 2026-05-22
status: approved
---

> **Document Version: 1.0** | 2026-05-22

## Context

LBK reviewed the v0.1 anchor docs (`docs/solution-proposal.md`, `docs/domain-model.md`) and reported that **transaction reconciliation is one of the main features of this app, but the docs do not clearly say what is being reconciled, between which sources, or what types of things are being reconciled**.

The docs *do* cover reconciliation — substantially — but they describe it through two lenses (the Sale Event lifecycle, and the per-sale / per-payout cadence model in §6) without ever presenting a single concrete catalog of *what gets compared against what, from which sources*. A reader has to assemble the picture from across the proposal and the domain model.

This change adds that catalog as a dedicated section, threads cross-references through existing sections, and resolves one open vocabulary question.

## The four kinds of reconciliation

The system performs four distinct reconciliations. Each has its own pair of sides, its own source systems, its own trigger, and its own definition of success.

| # | Kind | Left side | Right side | Source of left | Source of right | Trigger | Actor | Success criterion |
|---|---|---|---|---|---|---|---|---|
| 1 | **Sale ↔ Payment correlation** | A sale-side event | The payment-side event that paid for it | Squarespace, TicketTailor | Stripe (Square is unified — self-correlates) | On ingest of either side | System | Both sides linked; one Sale Event covers both rows |
| 2 | **Line totals ↔ event gross (internal)** | Sum of resolved Line Item amounts | The event's gross amount | Channel payload (lines) | Same channel payload (header) | On ingest | System | Difference within $0.50 tolerance |
| 3 | **Sale Event ↔ Xero Invoice** | Approved Sale Event in Phoenix | Posted Invoice in Xero | Phoenix DB | Xero API (idempotent on `Reference`) | Owner clicks Approve | System (writes), Owner (initiates) | Xero confirms `posted`; Invoice id stored on Sale Event |
| 4 | **Approved invoices ↔ Payout** | Sum of net amounts of approved Invoices for a (processor, date-window) | Payout amount landed in Xero via bank feed | Phoenix + Xero | Stripe / Square payout via Xero bank feed | Daily sweep | System flags, Owner reviews drift | Sums match within tolerance; else `drift_flagged` |

**LBK's "transaction reconciliation"** is the umbrella term for all four. The catalog makes the umbrella concrete.

## Where each kind physically happens

- **Kind 1 (sale ↔ payment correlation):** in the Phoenix `Reconciliation` context, triggered by webhook ingest from Make. The matching ladder (timestamp + amount + reference) runs here. Square does not need this step because its sale and payment arrive in one payload.
- **Kind 2 (line totals ↔ event gross):** also in the `Reconciliation` context, on ingest. A failure routes the Sale Event to `needs_resolution` with reason "lines do not sum to gross".
- **Kind 3 (Sale Event ↔ Xero Invoice):** in the Phoenix `Xero` adapter (or Make Xero scenario, per the §3 design rule). Triggered by owner approval. Idempotent on the `Reference` field carrying the Sale Event id.
- **Kind 4 (approved invoices ↔ payout):** in a scheduled `Reconciliation.sweep_payouts/0` job that fires daily. Pulls payout rows from Xero bank-feed view; pulls approved Invoice nets from local state; computes the comparison.

## Edits

### `solution-proposal.md`

| Section | Change |
|---|---|
| §3 Architecture, Reconciliation context bullet | Add parenthetical: "(handles kinds 1, 2, 3 from §6; the daily sweep is kind 4)" |
| **§6 (NEW) Reconciliation Catalog** | Brand-new section. Inserts the catalog table, the framing paragraph, the synonym note for LBK's "transaction reconciliation", and the "where each kind happens" prose. A small Mermaid diagram overlays the four kinds on the existing architecture. |
| **§7 (was §6) Reconciliation cadence — continuous vs daily** | Existing "two sides" section renumbered and renamed. Body unchanged except for cross-references: per-sale = "kinds 1, 2, 3 from §6"; per-payout = "kind 4 from §6". |
| §3 Flow 4 (Daily reconciliation sweep) heading | Add "(kind 4 from §6 catalog)" |
| §3 Reconciliation context row in the contexts table | Append: "Kinds 1–3 of the §6 catalog; kind 4 runs as a scheduled job inside this context." |
| Subsequent section numbers | All sections after old §6 shift down by one (Audit Trail becomes §8, etc.) |

### `domain-model.md`

| Section | Change |
|---|---|
| §3 Glossary, "Reconciliation" entry | Rephrase to: "Reconciliation is the family of comparisons that confirm what we recorded matches what actually happened. The four specific kinds — their sides, sources, triggers, and success criteria — are catalogued in `solution-proposal.md` §6." |
| §4 Payout entity, Lifecycle | Append cross-reference on `drift_flagged`: "(failure state of kind 4 — see `solution-proposal.md` §6)" |
| §6 Business Rules, "Reconciliation rules" subsection | Annotate each rule with the catalog kind it governs: rule 1 → kinds 1 + 2 (ingress); rule 2 → kind 1 (correlation); rule 3 → kind 2 (line totals); rule 4 → kind 3 (approval → Xero). |
| §7 Open vocabulary questions | Remove the "Reconciliation vs matching vs reconciling" bullet. LBK used "reconciliation" in feedback; vocabulary is settled. |

## Out of scope

- No changes to integration docs (`docs/integrations/*`) — those are still on `docs/diwan-foundation` and will be reconciled at merge.
- No changes to the v0.2 delta doc (`docs/2026-05-22-solution-proposal-delta.md`) — also on `docs/diwan-foundation`.
- No new diagrams beyond the one new overlay diagram in the catalog section. Existing Mermaid diagrams stay as-is.
- No domain-model entity changes. The catalog describes existing entities; it does not introduce new ones.

## Open questions resolved by this change

- **Vocabulary** — "reconciliation" is now the term of art. The `domain-model.md` §7 open question on this is closed.

## Open questions *not* touched by this change

- The remaining §7 / §8 open questions in `domain-model.md` (Approval term, Drift term, Channel SKU term, TicketTailor line-item availability, existing Xero state, event ticket caps, refund flow) are unaffected.

## Verification

After edits:
- Render docs with `scripts/build-docs.sh` and visually confirm catalog table, diagram, and cross-references.
- Grep for "see §" and "kind " in both docs to confirm all cross-references resolve.
- Confirm the §6 catalog answers LBK's three questions in order: *what* (the table's "Kind" column), *between what sources* (left/right source columns), *what types* (the four rows themselves).
