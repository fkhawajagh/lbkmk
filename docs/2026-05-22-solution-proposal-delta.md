---
title: Solution Proposal Delta — findings from integration research
audience: Owner + main session
status: Draft v1.0
date: 2026-05-22
depends_on: docs/solution-proposal.md, docs/integrations/*.md
---

> **Document Version: 1.0** | 2026-05-22
>
> What changed between `docs/solution-proposal.md v0.1` (2026-05-21) and the integration reference docs landed on 2026-05-22. Reviews the proposal section-by-section and flags every place where reality differs from the original sketch. Each finding has a recommended action — most are local edits to the proposal; one is an architectural decision that needs owner input.

## TL;DR

The proposal's overall shape — Make as integration spine, Phoenix as reconciliation cockpit, posted invoices clearing existing bank-feed deposits in Xero — survives the research intact. The deltas are mostly **mechanism-level**: the proposal sketches the right flows but mis-describes how some of them actually work.

Five findings are **blocking** (rewrites required before any code ships). The rest are corrections, missing footguns to document, and operational scope additions.

## Blocking deltas

### B1. Flow 1 (Squarespace ingestion) describes Stripe correlation backwards

**Proposal §4 Flow 1, step labelled "id_match strategy succeeds (charge.metadata.order_id == squarespace event id)"** assumes Stripe carries the Squarespace order id in `Charge.metadata`.

**Reality (`docs/integrations/squarespace.md` + `docs/integrations/stripe.md`):** the deterministic path runs the other direction. Squarespace's Transactions API (`GET /1.0/commerce/transactions/{orderId}` → `payments[].externalTransactionId`) publishes the Stripe `ch_...`. Stripe does NOT guarantee carrying the Squarespace order id — channels can populate `Charge.metadata` if they choose, but Stripe makes no such promise and lbkmk must not key correlation on it.

**Action:** rewrite Flow 1 so the Squarespace ingress scenario calls `GET /1.0/commerce/transactions/{orderId}` at enrichment time, captures the Stripe charge id on the Squarespace Sale Event, and then matches deterministically when the Stripe `charge.succeeded` arrives (matching on the captured `ch_...`, not on Stripe-side metadata).

### B2. Squarespace ingestion needs a synchronous enrichment step the proposal doesn't show

**Proposal §3 Make scenario #1 + §4 Flow 1** show Make receiving the Squarespace webhook and POSTing a normalized event (with line items) to Phoenix in one step.

**Reality (`docs/integrations/squarespace.md`):** the Squarespace `order.create` webhook payload contains only `{ orderId }` inside `data`. No line items, no totals, no customer. Make must call `GET /1.0/commerce/orders/{orderId}` to enrich the line items, plus `GET /1.0/commerce/transactions/{orderId}` to capture the Stripe charge id (per B1). That is **3 Make module executions per Squarespace order** (receive + 2 GETs + POST = 4 credits), not 1.

**Action:** update Make scenario #1 in §3 and Flow 1 in §4 to show the enrichment hops. Bump Make-ops estimate in §12 Q5 accordingly.

### B3. Stripe fees live on a separate object, not on the Charge

**Proposal §8 `sale_events` table** has `fee_cents` as a first-class column. **Proposal §9 sample POST `/sale-events`** shows `"fee_cents": 280` directly on the body.

**Reality (`docs/integrations/stripe.md`):** Stripe's `Charge` object does **not** carry `fee_cents`. The processing fee lives on the linked `balance_transaction` object — a separate fetch (`GET /v1/balance_transactions/{txn_...}`). The Stripe ingress scenario must either expand the charge with `balance_transaction` in the API call or do a follow-up GET. Without this, every Stripe-side Sale Event would have `fee_cents = NULL`, breaking the proposal's per-payout reconciliation math (§6).

**Action:** add a fee-enrichment step to Make scenario #1 (Stripe ingress) in §3. Document the dependency in §9 sample payload comment.

### B4. Make has no native HTTP-module retries — §5.4 Flow is wrong

**Proposal §5.4 Approval failure recovery** has a diamond labelled "Within Make retry budget?" with a "Yes → Make retries with backoff" branch.

**Reality (`docs/integrations/make.md`):** Make's HTTP module does NOT retry automatically. Retries require an explicit **Break** error handler with a configured attempt count. Without the Break handler, a single 5xx from Xero terminates the scenario run and the event is lost from the live path (only recoverable via the daily sweep).

**Action:** rewrite §5.4 to show the Break handler explicitly. Make scenario #3 (Xero-write) in §3 must list a Break handler with attempt count + backoff as a mandatory part of the scenario shape, not an optional polish.

### B5. The bank-feed reconciliation question (§12 Q2) is the load-bearing one — and the answer is almost certainly "yes"

**Proposal §12 Q2** flags this as an owner question without a leaning answer.

**Reality (`docs/integrations/xero.md`):** LBK almost certainly has Stripe and Square already connected to Xero via Xero's official direct feeds. Stripe creates a virtual bank account mirroring every charge/fee/refund/payout. Square posts daily summary BankTransactions. **The risk is double-counting:** if a Xero bank rule auto-categorises a Stripe-feed deposit as revenue while lbkmk also posts a revenue-crediting Invoice, the books are doubled.

**Action:** §12 Q2 should be the first owner question answered, not one of seven. Until resolved, treat **the entire posting strategy as in-flux** — including whether lbkmk posts `ACCREC AUTHORISED` invoices that the feed clears (the recommended path) vs. some other shape. Filed as issue #51.

## Mechanism-level corrections

### C1. TicketTailor §12 Q1 is already resolved

**Proposal §12 Q1**: "Does TicketTailor expose line items in webhooks/API, or do we need enrichment?" — listed as open.

**Reality (`docs/integrations/tickettailor.md`):** affirmative. `order.created` and `order.updated` webhooks ship the full `line_items[]` plus `issued_tickets[]`. No enrichment call needed.

**Action:** remove Q1 from §12 or mark as resolved.

### C2. TicketTailor ↔ Stripe correlation is still heuristic, not deterministic

**Proposal §5.2 strategy ladder** routes TicketTailor's Stripe pairing through `id_match` then `metadata_match` then `amount_time_window`. The owner-facing flow assumes one of the deterministic paths will usually succeed.

**Reality (`docs/integrations/tickettailor.md` Q2 + `docs/integrations/stripe.md`):** TicketTailor's webhook carries `payment_method.external_id`, which **probably** contains the Stripe `ch_...` or `pi_...` when Stripe is the processor — but this is unverified against a real LBK order. Until empirical confirmation (filed as issue #3 + #29), TicketTailor↔Stripe correlation is `amount_time_window` only, `confidence: medium`, routed to `needs_resolution` per the proposal's own ladder. **The owner will see far more "confirm fuzzy match" prompts than the proposal implies until that one empirical test resolves the question.**

**Action:** call out in §5.2 that TicketTailor ↔ Stripe is heuristic-only until issue #3/#29 closes; note that resolution would upgrade most TicketTailor sales to `confidence: high` and remove the owner-prompt step.

### C3. Square's HMAC signs `URL + body`, not just `body`

**Proposal §10** does not describe per-channel signature verification specifics.

**Reality (`docs/integrations/square.md`):** Square's HMAC algorithm signs the concatenation of `notification_url + raw_body`, **not** just `raw_body`. A naive verifier reusing TicketTailor's "HMAC over raw body" code silently fails on every Square delivery. Plus the URL must match byte-for-byte against the registered string — any edge rewrite (trailing slash, www, HTTPS canonicalization) breaks verification.

**Action:** add to §10 Operational concerns: "Signature verification is per-channel. See `docs/integrations/<channel>.md` for the exact algorithm and canonicalization each channel requires."

### C4. Square's 10-second response window is the tightest of the four channels

**Proposal §10** does not enumerate channel ACK windows.

**Reality (`docs/integrations/square.md`):** 10-second hard timeout. Combined with the 3-week subscription auto-disable on sustained failure, lbkmk must ack immediately and enrich async on the Square path. TicketTailor allows 72 hours of retry tolerance before counting failure; Stripe gives a generous retry window over 3 days. Square is the constraint that determines lbkmk's ingress design.

**Action:** add to §10 — Phoenix `/sale-events` ingress should return 202 within ~2 seconds for all channels, with enrichment happening in a background job. Do not attempt synchronous enrichment in the request thread.

### C5. Per-channel webhook auto-disable thresholds vary wildly — heartbeat alarms must be per-channel

**Proposal §10 Observability** mentions structured logs and error tracking but does not specify channel-specific monitoring.

**Reality (cross-channel synthesis):**
- TicketTailor: warning at 5 days, auto-disable at 10 days (re-enable in dashboard).
- Squarespace: **silent deletion** after "multiple unsuccessful requests" (threshold unknown — issue #18). Subscription is gone, not disabled — must recreate.
- Stripe: emails the merchant.
- Square: warning emails weeks 1/2/3, silent disable at 3 weeks.
- Make: webhooks not attached to scenarios auto-disable at 5 days → `410 Gone`.

**Action:** add to §10 — per-channel heartbeat alarm with thresholds set well below each channel's auto-disable cliff. Squarespace specifically needs the most aggressive alarm because the failure mode is silent deletion, not disable. Add the Make-side hook health check (`GET /hooks/:id` for each scenario's webhook) as part of the operational dashboard.

### C6. `raw_payload jsonb` carries PII — encryption-at-rest is implicit, not stated

**Proposal §8** stores `raw_payload jsonb` on `sale_events` without mentioning encryption requirements.

**Reality (`docs/integrations/stripe.md` anti-pattern):** Stripe events contain `card.last4` and `billing_details` (name, postcode, sometimes address). We never see PAN/CVC, but `last4 + name + postcode` is identifying PII. Squarespace and Square payloads carry similar fields.

**Action:** add to §8 — `raw_payload` and any column containing source webhook bodies must be encrypted at rest. Add access control: the column should be readable only by ingestion + audit roles, not by routine reporting queries.

### C7. Idempotency layer count is right, but Xero `Idempotency-Key` retention is unverified

**Proposal §10** lists four idempotency layers, including layer 4: "Xero `Invoice.Reference = lbkmk:<sale_event.id>` — Make checks for existing before creating."

**Reality (`docs/integrations/xero.md`):** Xero does support `Idempotency-Key` on `POST /Invoices` (since 2023), but the retention window is undocumented (filed as issue #58). The Reference-based fallback is correct — keep it. But the proposal could also use the `Idempotency-Key` header as a fifth layer for the same call, since it's free.

**Action:** §10 idempotency list — add Xero `Idempotency-Key` as belt-and-braces alongside the Reference check. No removal of existing layers.

## Footguns the proposal should document

Each of these is a real-world failure mode surfaced by research that the proposal currently does not flag:

| # | Footgun | Source | Where to document |
|---|---|---|---|
| F1 | Make egress IPs are 3 per zone, shared across all Make customers, rotating — cannot IP-allowlist Make on lbkmk's inbound side. Bearer + HMAC is the contract. | `make.md` anti-pattern #4 | §10 Observability / Security |
| F2 | Instant Make scenarios deactivate on the FIRST error, not after `Number of consecutive errors`. Mitigation: attach Break/Resume handler to every module. | `make.md` anti-pattern #2 | §3 Make scenario shape |
| F3 | TicketTailor's webhook delivery is counted as failed immediately on HTTP redirect (no 30x follow-through). Webhook URL must match exactly. | `tickettailor.md` anti-pattern #2 | §10 Deployment |
| F4 | Stripe event order is not guaranteed (`payment_intent.succeeded` / `charge.succeeded` / `charge.refunded` can arrive in any order). State machines branching on observed sequence are wrong; always re-derive from `data.object`. | `stripe.md` anti-pattern | §5 Decision points |
| F5 | Square's `idempotency_key` lives in the request body, not in a header (unique among the four channels). | `square.md` anti-pattern | §10 Idempotency |
| F6 | Squarespace hex secret must be byte-decoded before HMAC use — passing the hex string silently produces a wrong signature. | `squarespace.md` anti-pattern #2 | §10 Security |
| F7 | Xero `DRAFT` invoices don't decrement tracked inventory — must post as `AUTHORISED`. | `xero.md` anti-pattern | §4 Flow 3 |
| F8 | TicketTailor voids (single ticket) are NOT refunds and do NOT cancel the parent order — they invalidate one barcode only. | `tickettailor.md` anti-pattern #1 | §11 Scope ("refunds out of scope") |

## Scope items the proposal correctly defers but should reference research

- **Refund/return flow (§11):** the integration docs for all four channels documented refund event shapes. When v2 picks this up, `docs/integrations/{stripe,squarespace,square,tickettailor,xero}.md` already contain the per-channel mechanics — no fresh research needed.
- **Multi-currency (§11):** Xero multi-currency requires Premium tier (filed as issue #62). v1 single-currency is fine; the constraint is documented if the deferral ever lifts.
- **Multi-tenant (§11):** `docs/integrations/xero.md` recommends designing the data shape multi-tenant from day one even though v1 ships single-tenant (filed as issue #64). The proposal §8 schema does not yet include a `tenant_id` column on the Xero-touching entities — add it now to avoid a migration later.

## Make ops estimate refinement (§12 Q5)

The proposal's §12 Q5 is open ("expected monthly transaction volume"). The Make doc lets us tighten the planning estimate now:

| Channel | Modules per ingestion | Notes |
|---|---|---|
| TicketTailor | 3 (receive + transform + POST) | Line items in webhook |
| Stripe (direct or processor-side) | 4 (receive + transform + balance-transaction GET + POST) | Fee enrichment |
| Squarespace | 5 (receive + transform + orders GET + transactions GET + POST) | Line-item + Stripe-id enrichment |
| Square | 3-4 (receive + transform + maybe orders GET + POST) | Line-items unclear, issue #40 |

Assuming **300 sales/month total** across all four channels with Stripe firing 1 event per non-Square sale: ~300 sales + ~250 Stripe events ≈ **550 ingestion runs/month × ~4 modules avg = ~2,200 credits/month**. Comfortably under Core (10k). Pro upgrade triggers (priority execution + log search) become attractive once the system is live and depended on, not by credit count.

## Recommended next steps for the proposal

1. **Update v0.1 → v0.2** of `docs/solution-proposal.md` applying B1-B5 + C1-C7. Each is a local edit, not a redesign.
2. **Resolve §12 Q1** (TicketTailor line items) — affirmative, per integration research.
3. **Elevate §12 Q2** (Xero bank feeds) to the top — it gates the posting strategy.
4. **Add F1-F8 to the operational concerns section** as a "Per-channel footguns" sub-section.
5. **Treat the integration docs as canonical** for per-channel mechanics. The proposal should reference them by section name (e.g. "per `docs/integrations/stripe.md` §Webhooks") rather than re-describing.

None of these block continued planning. The proposal's shape stays. The fix-list is contained.
