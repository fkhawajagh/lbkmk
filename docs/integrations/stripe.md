# Stripe — Integration Reference

> Document Version: 1.0 | 2026-05-22

## Role in lbkmk

Stripe plays **two roles** for LBK:

1. **Direct sales channel.** LBK takes some payments via Stripe Checkout, Payment Links, or Stripe-hosted invoices, independent of any other platform. For those, the Stripe `charge.succeeded` (or `checkout.session.completed` / `payment_intent.succeeded`) event is both the **sale-side** and **payment-side** record — the Sale Event self-correlates on the Stripe side, like Square does (per `docs/domain-model.md` §4.2 Correlation invariants).
2. **Payment processor under other channels.** Stripe sits beneath both **Squarespace** and **TicketTailor** as the card processor. When a customer pays for a Squarespace order or a TicketTailor ticket, the resulting Stripe `charge.succeeded` is the **payment-side** record. The sale-side record arrives via the channel's own webhook (`order.create` from Squarespace, `order.created` from TicketTailor). lbkmk joins the two via a `Correlation` row (`docs/domain-model.md` §4.2).

```
                        ┌─ Stripe-direct sale ────────────────┐
                        │  (Sale + Payment in one event)      │
Stripe (charge.succeeded, payment_intent.succeeded, ──┐
        checkout.session.completed)                   │
                        │                             │  Make scenario
                        └─ Payment-side for ──────────┤  (Custom Webhook trigger)
                           Squarespace / TicketTailor │
                                                      │  HMAC verified
                                                      ▼
                                          lbkmk /webhooks/stripe
                                                      │
                                                      ▼
                                  correlate with Squarespace order /
                                  TicketTailor order (or self-correlate
                                  if Stripe-direct)
                                                      │
                                                      ▼
                                          decrement Inventory Item(s)
                                          (only for Stripe-direct;
                                           Squarespace/TicketTailor
                                           sale-side does the line items)
                                                      │
                                                      ▼
                                          post itemized Invoice to Xero
```

The lbkmk app never talks to Stripe directly — Make is the sole intermediary (`docs/domain-model.md` §6 rule 14). Even forensic re-fetches against Stripe's REST API would be mediated by a Make scenario.

## Authentication & credentials

| Aspect | Value | Source |
|---|---|---|
| Base URL | `https://api.stripe.com` | [versioning][versioning] |
| Transport | HTTPS only, TLS 1.2+ required in live mode | [webhooks][webhooks] |
| API key types | **Publishable** (`pk_live_...` / `pk_test_...`, client-side, safe to expose), **Secret** (`sk_live_...` / `sk_test_...`, server-side, write access), **Restricted** (`rk_live_...`, per-resource scope-limited) | [versioning][versioning] |
| Where to use which | lbkmk never calls Stripe from the client — only the **Secret** key (or a **Restricted** key) ever lives in the server-side / Make secret store | [versioning][versioning] |
| Webhook signing secret | `whsec_...` (one per **endpoint**, not one per account). Retrieved via Dashboard → Workbench → Webhooks → endpoint → "Click to reveal" | [sig-verif][sig-verif] |
| Webhook secret rotation | Dashboard → Webhooks → endpoint → ⋯ menu → "Roll secret". **24-hour grace window**: during rotation the endpoint receives multiple `v1=` signatures in the `Stripe-Signature` header and verification succeeds if any signature matches | [sig-verif][sig-verif] |
| Test vs. live | Completely separate worlds: separate Secret keys (`sk_test_...` / `sk_live_...`), separate webhook endpoints (each with its own `whsec_...`), separate dashboards. Test webhooks may target HTTP; live webhooks must be HTTPS | [webhooks][webhooks] |
| OAuth (for Connect) | OAuth token exchange used when a **platform** (Squarespace, TicketTailor, third-party SaaS) needs to act on a connected account's behalf. LBK is not a Connect platform — see Connect section below | [connect-charges][connect-charges] |
| Published source IPs (Stripe → lbkmk webhook receiver) | 15+ IPs across multiple AWS regions, machine-readable lists at `https://stripe.com/files/ips/ips_webhooks.txt` and `.json`. Stripe gives **7 days' notice** before changing the list via the [API announce mailing list][ip-announce] | [ips][ips] |

For lbkmk: store the Stripe **Secret key** and the **webhook signing secret** in the application's secret store (env vars / vault), and surface them to Make via a Keychain (see `docs/integrations/make.md` §"Critical question 7 — secret storage"). Use a **Restricted key** if any Stripe write paths are ever needed — limit to `Charges: Read`, `PaymentIntents: Read`, `Refunds: Read`, `Balance Transactions: Read`. Roll the webhook secret on a fixed cadence (quarterly) using the 24-hour overlap window — old and new secrets co-sign during the rotation, so lbkmk can update without dropping deliveries.

## Key concepts / data model

Stripe's resource graph relevant to lbkmk:

| Stripe resource | lbkmk mapping | Notes |
|---|---|---|
| **PaymentIntent** (`pi_...`) | (intermediate state, not directly mapped) | The lifecycle object for a payment. Goes through `requires_payment_method` → `requires_confirmation` → `requires_action` → `processing` → `succeeded` (or `canceled` / `requires_payment_method` on failure). Carries `metadata`, `description`, `statement_descriptor`. On success, produces a `Charge` reachable via `latest_charge`. ([pi-obj][pi-obj]) |
| **Charge** (`ch_...`) | `Sale Event` (channel = Stripe) for direct sales, **payment side** of a Correlation for cross-channel | The settled payment record. Carries `amount` (minor units), `currency`, `paid`, `captured`, `refunded`, `disputed`, `payment_intent` (back-reference), `customer`, `metadata`, `description`, `transfer_group`, `application` (set if a Connect platform created the charge), `application_fee_amount`, `on_behalf_of`, `payment_method_details.card.{last4, brand, country, fingerprint, funding}`, `billing_details.{name, email, address}`, `balance_transaction`. ([charge-obj][charge-obj]) |
| **Customer** (`cus_...`) | (out of scope for v1) | Optional. LBK does not need customer reconciliation today; the charge carries enough buyer detail in `billing_details`. |
| **Invoice** (`in_...`) | (Stripe-hosted invoice path only) | Created when LBK uses Stripe's invoicing product directly. Not the same thing as Xero invoices. Fires `invoice.payment_succeeded` and `invoice.paid` when paid. ([webhooks][webhooks]) |
| **Checkout Session** (`cs_...`) | `Sale Event` for Stripe-Checkout-direct sales | Created when LBK uses Stripe Checkout (the Stripe-hosted checkout page). Fires `checkout.session.completed` with the resulting `payment_intent` reachable on the session. ([webhooks][webhooks]) |
| **Refund** (`re_...`) | Triggers refund handling on the corresponding Sale Event | A refund of a Charge. Carries `charge` (back-reference), `amount`, `status`, `reason`, `metadata`, `balance_transaction`. ([webhooks][webhooks]) |
| **Dispute** (`du_...`) | (out of scope for v1; flag for owner) | A chargeback. Lifecycle: `needs_response` → (evidence submitted) → `under_review` → `won` / `lost` / `warning_closed`. Funds-impact events: `charge.dispute.funds_withdrawn`, `charge.dispute.funds_reinstated`. ([events-types][events-types]) |
| **Balance Transaction** (`txn_...`) | (used for fee detail and payout reconciliation) | The ledger entry for every balance-impacting event. Carries `amount`, `fee`, `net`, `fee_details[]`, `available_on`, `reporting_category`, `source` (back-reference to `ch_...`, `re_...`, etc.). **This is where Stripe's processing fees live** — the Charge object does not carry the fee directly. ([balance-tx-obj][balance-tx-obj]) |
| **Payout** (`po_...`) | `Payout` (`docs/domain-model.md` §4.2) | The bank deposit Stripe sends to LBK's bank account, net of all charges and fees over a settlement period. The existing Xero bank feed already ingests these; lbkmk's job is to ensure the sum of approved Stripe-side Invoices matches the Payout net (per `docs/domain-model.md` Drift). |
| **Connected Account** (`acct_...`) | (potentially relevant — see Connect) | If a **platform** (Squarespace, TicketTailor, a third-party SaaS) is using Stripe Connect with LBK as the connected merchant, then events for LBK arrive at the platform's webhook endpoint, not LBK's directly. The Stripe Dashboard for LBK's account shows the charges natively if LBK's Stripe account is the one that holds the funds. See open question §1. |
| **Event** (`evt_...`) | (delivery envelope) | The webhook envelope. Carries `id`, `type`, `created`, `livemode`, `api_version`, `pending_webhooks`, `data.object` (the resource that triggered the event), `account` (set only for events on a connected account from a platform's perspective). ([webhooks][webhooks]) |

**Currency convention:** all monetary values are integers in the **smallest currency unit** (pence for GBP, cents for USD, etc.) — same convention as TicketTailor, opposite of Squarespace's decimal-string-with-multiplier shape. Normalization on the lbkmk side: no conversion needed for Stripe; convert Squarespace decimals to minor units before joining.

**Identifier prefixes** to expect on the wire: `pi_` PaymentIntents, `ch_` Charges, `cs_` Checkout Sessions, `re_` Refunds, `du_` Disputes, `txn_` Balance Transactions, `po_` Payouts, `cus_` Customers, `in_` Invoices, `evt_` Events, `acct_` Connected Accounts, `whsec_` webhook signing secrets, `pm_` payment methods. ([charge-obj][charge-obj], [pi-obj][pi-obj])

## Webhooks / events

### Headline finding — the cross-channel correlation story

**The reverse direction (Stripe → channel) is NOT deterministic without merchant cooperation.** The Stripe `Charge` object does carry `metadata`, `description`, `statement_descriptor`, and `transfer_group` fields, **but whether Squarespace or TicketTailor populate any of those with their own order id is platform behaviour, not Stripe behaviour**, and the Stripe public docs do not promise any particular shape ([charge-obj][charge-obj], [metadata][metadata]).

What lbkmk can rely on:

1. **Forward direction is deterministic for Squarespace.** As established in `docs/integrations/squarespace.md`, Squarespace publishes the Stripe charge id (`ch_...`) on its Transactions API at `GET /1.0/commerce/transactions/{orderId}` → `payments[].externalTransactionId`. lbkmk should treat this as the **authoritative join key** for Squarespace ↔ Stripe correlation — fetch the Transaction Document at sale-side enrichment time, store the Stripe charge id on the Squarespace Sale Event, then match it deterministically when the Stripe `charge.succeeded` arrives.
2. **Forward direction for TicketTailor needs empirical verification.** The TicketTailor open question §Q2 in `docs/integrations/tickettailor.md` flags this: `payload.payment_method.external_id` *probably* contains the Stripe charge id or PaymentIntent id when Stripe is the processor, but this is unconfirmed against a live LBK order. Until verified, TicketTailor ↔ Stripe correlation must fall back to the `amount + currency + time-window` heuristic (`docs/domain-model.md` §4.2 `match_strategy: amount_time_window`), which produces `confidence: medium` at best and is fragile against same-amount tickets sold seconds apart.
3. **Reverse direction (Stripe carrying the channel order id) is unreliable.** Whether Squarespace populates `metadata.order_id` or any other field on the Stripe `Charge` is undocumented in Stripe's public references and would require either a documented behavior from Squarespace's support team or empirical inspection of a real LBK charge. lbkmk should not assume Stripe-side carries the upstream id.

**Implication for lbkmk:** the Squarespace ingestion pipeline **must** call the Squarespace Transactions API at enrichment time to capture the `externalTransactionId` (the Stripe charge id) on the Squarespace Sale Event. This is what upgrades the Squarespace ↔ Stripe Correlation from `amount_time_window` (heuristic, `confidence: medium`) to `id_match` (deterministic, `confidence: high`) under `docs/domain-model.md` §4.2.

### Event types lbkmk needs

The minimum set covering both the direct-channel sale recording and the cross-channel correlation use case ([events-types][events-types], [webhooks][webhooks]):

| Event type | Why lbkmk needs it | When it fires |
|---|---|---|
| `charge.succeeded` | **Primary** payment-side event for both Stripe-direct sales and cross-channel correlation. The `Charge` object carries the back-reference to `payment_intent`, the `metadata`, and the data needed to join to a Squarespace/TicketTailor sale-side Sale Event | When a charge completes successfully |
| `charge.refunded` | Refund detection. Carries the `Charge` object (not the `Refund` object) with `amount_refunded` and `refunded: true`. Fires on full or partial refund | When a charge is refunded (including partial refunds), or when the application fee is refunded directly ([events-types][events-types]) |
| `charge.updated` | Captures metadata changes and asynchronous-capture confirmations. Lower-priority but useful for forensic completeness | When charge description / metadata is updated, or upon asynchronous capture |
| `refund.created` | Detailed refund event with the `Refund` object as `data.object`. Use **in addition to** `charge.refunded` because the Charge envelope does not carry per-refund detail (refund id, reason, timestamp) — only the cumulative `amount_refunded` | When a refund is initiated |
| `refund.updated` | Refund status transitions (`pending` → `succeeded` / `failed` / `canceled`). Some refund methods (ACH, SEPA) take days to settle | When a refund is updated |
| `refund.failed` | Critical for owner notification — a failed refund leaves the customer expecting money back that hasn't arrived | When a refund attempt fails |
| `checkout.session.completed` | Primary trigger for sales originating in Stripe Checkout (Stripe-direct sales path). Carries the `Checkout Session` with the resulting `payment_intent` link | When a Checkout Session completes |
| `checkout.session.async_payment_succeeded` | For Checkout Sessions paid via delayed methods (bank transfer, OXXO). The session completes synchronously but the actual money arrives later | When a delayed-method PaymentIntent finally succeeds for a Checkout Session |
| `checkout.session.async_payment_failed` | Inverse of the above — the customer abandoned a delayed payment | When a delayed-method PaymentIntent fails for a Checkout Session |
| `payment_intent.succeeded` | Useful as an early signal; semantically equivalent to `charge.succeeded` but fires fractionally earlier. lbkmk can pick one of `charge.succeeded` and `payment_intent.succeeded` as the primary — **`charge.succeeded` is the safer choice** because the `Charge` object carries the settlement data (`balance_transaction`, `payment_method_details`) | When a PaymentIntent completes |
| `payment_intent.payment_failed` | Useful for owner-facing UI (failed cart, retry prompt). Not strictly required for reconciliation | When a PaymentIntent fails |
| `charge.dispute.created` | Owner notification for a chargeback. Disputes are out of scope for the lbkmk v1 reconciliation pipeline but the owner needs to know they happened | When a customer disputes a charge |
| `charge.dispute.closed` | Resolution outcome (`won` / `lost` / `warning_closed`) | When a dispute closes ([events-types][events-types]) |
| `charge.dispute.funds_withdrawn` | The dispute hits the balance — money is removed | When funds are withdrawn for a dispute |
| `charge.dispute.funds_reinstated` | The merchant won the dispute or it was a partial refund — money is restored | When funds are reinstated after a dispute |
| `invoice.payment_succeeded` / `invoice.paid` | Only needed if LBK ever uses Stripe's hosted invoicing product directly. Skip otherwise | When a Stripe-hosted Invoice is paid |

For lbkmk's v1 sales-recording purpose, the **minimum subscription** is: `charge.succeeded`, `charge.refunded`, `refund.created`, `refund.updated`, `refund.failed`, `checkout.session.completed`. Add disputes (`charge.dispute.*`) once the dispute-handling workflow lands.

### Envelope structure

Every webhook delivery is an `application/json` POST with these headers ([webhooks][webhooks], [sig-verif][sig-verif]):

```
User-Agent: Stripe/1.0 (+https://stripe.com/docs/webhooks)
Content-Type: application/json
Stripe-Signature: t=<unix-seconds>,v1=<hex-hmac-sha256>,v0=<test-only>
```

And this top-level body shape ([webhooks][webhooks]):

```json
{
  "id": "evt_1NG8Du2eZvKYlo2C9XMqbR9q",
  "object": "event",
  "api_version": "2026-04-22.dahlia",
  "created": 1685000000,
  "livemode": true,
  "type": "charge.succeeded",
  "pending_webhooks": 1,
  "request": { "id": "req_...", "idempotency_key": null },
  "data": {
    "object": { /* the affected resource — Charge, Refund, Dispute, etc. */ },
    "previous_attributes": { /* present on .updated events */ }
  },
  "account": "acct_..." /* present ONLY for Connect events on connected accounts */
}
```

- **`id`** — unique event id (`evt_...`). **Use this for dedupe.** ([webhooks][webhooks])
- **`type`** — lowercase, dot-separated (`charge.succeeded`, `charge.refunded`, `payment_intent.succeeded`, etc.).
- **`api_version`** — the API version pinned to the webhook endpoint at the time the event was generated. Locked at endpoint-create time (see "Versioning" below).
- **`livemode`** — `true` for live-mode events, `false` for test-mode. lbkmk should reject `livemode: false` events in production unless they originate from an explicit test endpoint.
- **`pending_webhooks`** — count of webhook deliveries still in flight for this event. Mostly informational.
- **`data.object`** — the resource at event time. **For `charge.succeeded`**, this is a full `Charge`; the `payment_intent` reference inside it is a string (not an expanded object).
- **`data.previous_attributes`** — present only on `.updated`-suffix events; shows the old values of changed fields.
- **`account`** — present **only** if the event is for a Connect-connected account from a platform's perspective. For LBK's direct Stripe account, this field is absent. See Connect section.

### Signing / verification

- **Header:** `Stripe-Signature: t=<unix-seconds>,v1=<hex>` (the `v0=...` value is a test-mode-only scheme — production code must ignore it). ([sig-verif][sig-verif])
- **Algorithm:** **HMAC-SHA256** keyed by the endpoint's `whsec_...` signing secret, over the **signed payload** = `<timestamp>.<raw_request_body>` (literal `.` separator, no whitespace normalization). ([sig-verif][sig-verif])
- **Comparison:** constant-time string compare against the `v1=` value. Stripe's official SDKs do this in `Webhook.construct_event`. ([sig-verif][sig-verif])
- **Timestamp tolerance:** **5 minutes (300 seconds)** default — reject deliveries where `now - t > 300`. **Do not set tolerance to 0** — that disables the recency check entirely. Stripe explicitly warns against this. ([sig-verif][sig-verif])
- **Key rotation:** during the 24-hour overlap window after `Roll secret`, the header carries multiple `v1=` values, one per active secret. Verification succeeds if **any** match. ([sig-verif][sig-verif])
- **Critical:** the HMAC is computed over the **raw request body bytes** as Stripe sent them. Any JSON re-serialization (key-reordering, whitespace stripping, BOM-adding) breaks verification. See `docs/integrations/make.md` §"Inbound payload — raw body forwarding to lbkmk" for the Make-side configuration that preserves byte fidelity.

For lbkmk: enable `JSON pass-through` and `Get request headers` on the Make Custom Webhook trigger for Stripe, forward `{{1.body}}` verbatim as `text/plain` to lbkmk's `/webhooks/stripe`, map `Stripe-Signature` into a custom outbound header, and verify on the raw body in lbkmk before JSON parsing. The trust boundary is at lbkmk.

### Retry policy

- **Successful delivery** = endpoint returns a `2xx` status code. ([webhooks][webhooks])
- **Any non-2xx response, redirect, timeout, or TLS failure** = unsuccessful. Stripe retries.
- **Live mode retry curve:** up to **3 days** with **exponential backoff**. ([webhooks][webhooks])
- **Sandbox (test mode) retry curve:** a few retries over hours, not days.
- **Manual retry windows:** Dashboard "Resend" works for up to **15 days** after event creation; CLI `stripe events resend <event_id>` works for up to **30 days**. ([webhooks][webhooks])
- **Each retry generates a new `t=` timestamp and new `v1=` signature**, but the **event `id` stays the same** — this is the key to dedupe.
- **Auto-disable on sustained failure:** Stripe does **not** auto-disable a webhook endpoint that keeps failing the way TicketTailor does at 10 days. Instead, the Dashboard surfaces health metrics and Stripe sends emails to the merchant after sustained failure. Long-term failure is the merchant's problem to fix.

For lbkmk: Stripe's 3-day window is the longest of the four channels (Squarespace 48h, TicketTailor 72h, Square ~72h). This is operationally generous but it also means lbkmk has a 3-day buffer to catch and replay — combined with Make's Break-handler retry and lbkmk-side idempotency, the chance of a permanently-lost Stripe event is vanishingly small. Monitor delivery success rate via Dashboard → Webhooks → endpoint → success-rate gauge.

### Idempotency

Stripe's own guidance ([webhooks][webhooks]):

> "In some cases, two separate Event objects are generated and sent. To identify these duplicates, use the ID of the object in `data.object` along with the `event.type`."

And on retries: the same `event.id` (`evt_...`) is re-delivered, but the `Stripe-Signature` timestamp is freshly generated. Implementations must dedupe on the event id, **not** the signature timestamp.

For lbkmk: the `evt_...` is the **per-delivery idempotency key**. The `data.object.id` (the `ch_...`, `re_...`, etc.) is the **per-resource idempotency key**. lbkmk's `(channel, external_event_id)` uniqueness should key on the `data.object.id` since multiple Stripe events (`payment_intent.succeeded` + `charge.succeeded` + retries of either) all describe the same underlying business transaction. Belt-and-braces: dedupe on both the envelope `evt_...` (per-delivery) and the inner object id (per-resource).

**Note on the "two separate Event objects" case:** the docs warn that under some race conditions Stripe may emit two events with different `evt_...` ids describing the same state change. The dedupe key needs to be `(type, data.object.id)` rather than just `evt_...` to absorb this. ([webhooks][webhooks])

### Event ordering

**Stripe does NOT guarantee delivery order** ([webhooks][webhooks]):

> "Creating a subscription may generate `customer.subscription.created`, `invoice.created`, `invoice.paid`, and `charge.created` events. Your code must not assume sequence."

In practice for lbkmk this means: `payment_intent.succeeded` and `charge.succeeded` describing the same payment can arrive in either order, and `charge.refunded` can arrive before `refund.created`. The right pattern is: on every event, re-derive the current state from `data.object` (or, if needed, re-fetch via `GET /v1/charges/{id}`) and update lbkmk's Sale Event idempotently. Never trust the *order* of events as a causality signal.

### Connected accounts

When a **platform** uses Stripe Connect, its webhook endpoint receives events for **all** of its connected accounts. The platform tells them apart via the top-level **`account: "acct_..."`** field on the Event envelope. ([connect-webhooks][connect-webhooks])

For lbkmk this is relevant **only if** Squarespace or TicketTailor use Stripe Connect with LBK as a *connected account on their platform* (rather than LBK holding its own Stripe account that receives the funds directly). The two paths are:

| Mode | Where the Charge appears | Who receives `charge.succeeded` | Implication for lbkmk |
|---|---|---|---|
| **LBK's own Stripe account holds the funds** (most likely) | In LBK's Stripe Dashboard | LBK's own webhook endpoint receives the event with no `account` field | Standard case. lbkmk receives Stripe events directly via its own configured endpoint. |
| **Squarespace/TicketTailor uses Stripe Connect with LBK as connected account** | Depends on Direct vs Destination charge type | The **platform's** webhook endpoint receives events for `acct_LBK`; LBK's account may also receive events depending on charge type | lbkmk would need the platform to forward those events, or LBK would need to be set up as a webhook recipient on the connected account. **Confirm with the owner what LBK actually sees in its Stripe Dashboard today** — see open question §1 below. |

If LBK's Stripe Dashboard shows the Squarespace and TicketTailor charges natively (with `ch_...` ids, billing details, and the ability to refund), then the funds flow into LBK's Stripe account directly (Mode 1) and the Connect complication does not apply. This is the assumption lbkmk's design proceeds on until owner confirmation.

## API surface we'll use

Base URL: `https://api.stripe.com`. All endpoints accept `Authorization: Bearer <secret_key>` (HTTP Basic with the secret key as the username and an empty password is also accepted). Set `Stripe-Version: <YYYY-MM-DD>.<codename>` to pin the API version on a per-request basis ([versioning][versioning]).

| Purpose | Endpoint | Notes |
|---|---|---|
| Re-fetch a charge (forensic, backfill) | `GET /v1/charges/{ch_id}` | Returns the full `Charge` including `payment_intent`, `metadata`, `payment_method_details`, `billing_details`, `balance_transaction`. Same shape as the webhook `data.object`. ([charge-obj][charge-obj]) |
| List charges for backfill | `GET /v1/charges?created[gte]=...&created[lt]=...&limit=100` | Cursor pagination via `starting_after` / `ending_before`. Up to 100 per page. ([charge-obj][charge-obj]) |
| Re-fetch a payment intent | `GET /v1/payment_intents/{pi_id}` | Returns the `PaymentIntent` with `latest_charge` linking to the resulting `Charge`. ([pi-obj][pi-obj]) |
| Re-fetch a refund | `GET /v1/refunds/{re_id}` | Returns the `Refund` with `charge` back-reference, `amount`, `status`, `reason`, `balance_transaction`. |
| List refunds | `GET /v1/refunds?charge={ch_id}` | All refunds for a given charge. Useful when reconciling cumulative `amount_refunded` against individual refund history. |
| Re-fetch the balance transaction (for fee detail) | `GET /v1/balance_transactions/{txn_id}` | **The fee lives here, not on the Charge.** Returns `amount` (gross), `fee`, `net`, `fee_details[]` (with `stripe_fee`, `application_fee`, `tax` breakdown), `available_on`, `reporting_category`, `source` (the `ch_...` / `re_...` that caused it). ([balance-tx-obj][balance-tx-obj]) |
| Reconcile a payout | `GET /v1/balance_transactions?payout={po_id}&expand[]=data.source&limit=100` | All balance transactions that summed into a given payout. Foundational for the lbkmk Drift detection (`docs/domain-model.md` §4.2 Drift) — sum the `net` of `type=charge` and `type=refund` rows against the payout `amount`. |
| Re-fetch a checkout session | `GET /v1/checkout/sessions/{cs_id}` | Returns the `Checkout Session` with `payment_intent` and (on `?expand[]=line_items`) the line items if Stripe-direct sales are line-itemised via Checkout. |
| Resend a missed webhook | `POST /v1/webhook_endpoints/{we_id}/...` or via CLI `stripe events resend <evt_id>` | Up to 30 days via CLI; 15 days via Dashboard. ([webhooks][webhooks]) |
| Create a refund (writeback) | `POST /v1/refunds` with `Idempotency-Key: <uuid-v4>` header | **lbkmk does not call this in v1** — refunds are out of scope per `docs/domain-model.md` §8. Listed for completeness. |

### Rate limits

| Scope | Limit | Behaviour |
|---|---|---|
| Global, live mode | **100 operations / second** | `429 Too Many Requests` over the line, with the `Stripe-Rate-Limited-Reason` response header explaining which limit triggered ([rate-limits][rate-limits]) |
| Global, sandbox / test mode | **25 operations / second** | Same `429` behaviour |
| Default per-endpoint | **25 requests / second** | Counts against the global pool |
| PaymentIntent updates | 1,000 / hour / PaymentIntent | Resource-specific |
| Read API allocation | 500 / transaction (rolling 30-day average), minimum 10,000 / month | Affects backfill loops |
| `Retry-After` header | **Not provided.** Stripe documents `429` and the `Stripe-Rate-Limited-Reason` header but does not promise a `Retry-After`. Client-side exponential backoff is required ([rate-limits][rate-limits]) |

For lbkmk: at any plausible LBK volume the 100/second live-mode limit is non-binding for steady-state ingestion. Watch the limit only during initial backfill or a multi-month catch-up against the Charges or Balance Transactions list endpoints — at 100 ops/sec a year of Stripe charges clears in minutes.

### API versioning

This is the area Stripe is most rigorously good at, and lbkmk should adopt the pattern verbatim.

- **Versions are date-coded with a codename:** e.g. `2026-04-22.dahlia` (current at retrieval date 2026-05-22). ([versioning][versioning])
- **Account default:** every Stripe account has a *default* API version pinned in the Dashboard → Workbench. All requests use this version unless explicitly overridden via the `Stripe-Version` header.
- **Webhook endpoint version pinning:** **each webhook endpoint is independently pinned** at creation time to the account's then-current default. This means the `data.object` shape stays stable across Stripe's API releases even if the account's default moves. The pinned version surfaces on every event as `event.api_version`. ([versioning][versioning], [webhooks][webhooks])
- **Major vs monthly releases:** named major releases (e.g. *Acacia*, *Dahlia*) contain **non-backward-compatible** changes. Monthly point releases within the same major name contain **only backward-compatible** changes and are safe to upgrade without code review. ([versioning][versioning])
- **Per-request override:** any individual API call can pin its own version via `Stripe-Version: 2026-04-22.dahlia`, overriding the account default. Useful when a single endpoint needs a fresher behaviour than the rest of the integration.
- **No published sunset timeline.** Stripe famously never breaks older versions — but they also do not publish an EOL. The pattern is "old versions keep working forever" rather than "version X.Y sunsets on date Z." ([versioning][versioning])
- **Preview / beta versions:** not surfaced on the standard versioning page. Specific products (e.g. Issuing, Identity) may have preview versions accessed via `Stripe-Version: <YYYY-MM-DD>; <feature>=v<n>` parameters, but those are scoped per-feature.

For lbkmk: **pin a specific Stripe API version at both the account level and the webhook endpoint level**, and pass `Stripe-Version` explicitly on every outbound API call. Document the pinned version in the lbkmk configuration. Upgrade deliberately — when a major release comes out, read the [API changelog][changelog], plan a minor lbkmk version bump (`docs/CLAUDE.md` semver policy), test against the new version using a staging webhook endpoint pinned to the new version, then swap.

## Best practices

1. **Pin the API version.** Both the account default and every webhook endpoint should be pinned to a specific dated version. Pass `Stripe-Version` on outbound API calls. Upgrade deliberately on a minor-version bump cycle, not opportunistically. ([versioning][versioning])
2. **Verify HMAC-SHA256 on the raw body, signed payload = `t.body`.** Constant-time compare. Enforce the 5-minute timestamp tolerance. Reject anything older. Use the official SDK's `Webhook.construct_event` in tests as a known-good reference. ([sig-verif][sig-verif])
3. **Dedupe on `data.object.id` (e.g. the `ch_...`), keyed alongside `event.type`.** Belt-and-braces with the envelope `evt_...`. Multiple events (`payment_intent.succeeded` + `charge.succeeded` + their retries) describing one payment all converge on one lbkmk Sale Event row. ([webhooks][webhooks])
4. **Always respond `2xx` quickly.** Enqueue heavy processing asynchronously. Any non-2xx (or timeout, or HTTP redirect) starts the 3-day retry curve and increases lbkmk's `pending_webhooks` count for the event. ([webhooks][webhooks])
5. **Use `charge.succeeded` as the primary payment-side trigger**, not `payment_intent.succeeded`. The `Charge` object carries the settlement-side data (`balance_transaction`, `payment_method_details`, `billing_details`) that lbkmk's reconciliation needs.
6. **Subscribe `refund.created` *and* `charge.refunded`.** They are not redundant — `charge.refunded` gives you the parent Charge with cumulative `amount_refunded`; `refund.created` gives you the individual `Refund` with its own id, reason, and `balance_transaction`. The pair covers both "this charge was refunded" and "here's a specific refund record." ([events-types][events-types])
7. **Fetch the `balance_transaction` for fee detail.** The Stripe processing fee does not live on the Charge — it lives on the linked `txn_...`. lbkmk's `Sale Event.fee` field should be populated from `balance_transaction.fee`, and `Sale Event.net` from `balance_transaction.net`. ([balance-tx-obj][balance-tx-obj])
8. **Reconcile payouts via `GET /v1/balance_transactions?payout={po_id}`.** This is the deterministic way to answer "what charges and refunds settled into payout `po_X`?" — foundational for `docs/domain-model.md` §4.2 Drift detection.
9. **Skip events where `livemode: false` in production.** A test-mode Stripe Dashboard click can fire test events at a live endpoint; route them to `rejected` automatically.
10. **Use `Idempotency-Key: <uuid-v4>` on every POST.** Stripe's idempotency model is best-in-class — keys are retained for **at least 24 hours**, the cached result is returned byte-for-byte on retry, and replaying the same key with **different parameters** errors out (which is exactly the safety net wanted when a write retries with subtly-changed input). Generate a fresh v4 UUID per logical write attempt. ([idempotency][idempotency])
11. **Roll the webhook signing secret quarterly.** Use the 24-hour overlap window: rotate, deploy the new secret to lbkmk's secret store inside the window, no events dropped. ([sig-verif][sig-verif])
12. **Treat the Stripe ↔ Squarespace correlation as authoritative.** Always fetch the Squarespace Transactions API (`GET /1.0/commerce/transactions/{orderId}` → `payments[].externalTransactionId`) at Squarespace sale enrichment time and store the `ch_...` on the Squarespace Sale Event. This upgrades the Correlation strategy from `amount_time_window` (heuristic) to `id_match` (deterministic).
13. **Capture the source IP list and IP-allowlist Stripe at the network edge.** Stripe publishes the webhook source IPs at `https://stripe.com/files/ips/ips_webhooks.json` with 7-day notice on changes via the API announce mailing list. ([ips][ips], [ip-announce][ip-announce]) Even with HMAC verification, IP-allowlisting is a cheap second layer.

## Anti-patterns / footguns

1. **Trusting event order.** Stripe explicitly says event delivery is unordered ([webhooks][webhooks]). `charge.succeeded` and `payment_intent.succeeded` for the same payment can arrive in either order, and `charge.refunded` can land before `refund.created`. Any state machine that branches on "if I see event X before event Y" is broken — always re-derive state from `data.object`, treating events as commutative updates rather than sequenced commands.

2. **Assuming Squarespace/TicketTailor attach metadata to Stripe charges.** Stripe's `Charge.metadata` field is the platform's to populate, not Stripe's. Squarespace and TicketTailor *might* set `metadata.order_id` (or use `description` / `statement_descriptor`), but neither party's public docs guarantee it. **Do not key correlation on `Charge.metadata.order_id`**. Use the channel-side forward-direction join (Squarespace Transactions API's `externalTransactionId`, TicketTailor's `payment_method.external_id`) as the authoritative key, and only fall back to amount+time-window heuristics if forward-direction data is missing. See open question §2.

3. **Storing `card.last4`, `card.brand`, `billing_details.address`, or `billing_details.name` in lbkmk's database casually.** These are exposed in the Charge payload and are **PII** under most data-protection regimes (UK GDPR / California CCPA). lbkmk never sees the full PAN or CVC (those never leave Stripe), but `last4 + name + postcode` is enough to identify a customer. Treat the Charge payload as PII: store the `ch_...` and the `amount` / `currency` / `fee` / `net` on the Sale Event, but **do not** persist the cardholder name, full billing address, or card last4 unless the owner has a documented business need. The raw payload kept verbatim per `docs/domain-model.md` §4.2 Sale Event invariants should be encrypted at rest and access-controlled. ([metadata][metadata])

4. **Using the test-mode `v0=` signature scheme in production verifiers.** The `Stripe-Signature` header carries both `v1=` (the real HMAC) and, on test events, `v0=` (a fake scheme used by older SDKs for test fixtures). Production verifiers must **only** check `v1=`. Accepting `v0=` makes it trivial to forge events. ([sig-verif][sig-verif])

5. **Setting the signature tolerance to 0 or to a very long window.** Stripe documents the 5-minute default and explicitly warns against setting it to zero. A zero tolerance disables the timestamp check entirely (because then the *only* condition `current - t > 0` triggers immediately). A very long window (hours, days) defeats replay protection. Stay at 300 seconds unless you have a clock-skew problem worth diagnosing. ([sig-verif][sig-verif])

6. **Forgetting that the Stripe processing fee is NOT on the Charge object.** The Charge carries `amount` (gross) and `amount_refunded`, but **not** the fee. The fee lives on the linked `balance_transaction` (`txn_...`). Code that reads `charge.amount` and stores it as the "net" silently records the gross — which makes the Xero posting wrong (`gross != net`) and the payout reconciliation impossible. Always fetch the balance transaction. ([balance-tx-obj][balance-tx-obj])

7. **Not pinning the webhook endpoint API version.** When a webhook endpoint is created without an explicit `api_version`, it inherits the account's *current* default version — and if the account default is then bumped, the endpoint's payload shape shifts under the integration's feet. Pin explicitly at create time, ideally to the same version the lbkmk codebase is written against. ([webhooks][webhooks], [versioning][versioning])

8. **Treating `charge.refunded` and `refund.created` as the same event.** They overlap in semantics but carry different `data.object` types: `charge.refunded`'s `data.object` is a **Charge** (the parent), `refund.created`'s `data.object` is a **Refund** (the child). Code that switches on `event.type` but then tries to read `data.object.id` as a refund id breaks when `charge.refunded` arrives with a `ch_...` instead of a `re_...`. Type-discriminate at the handler boundary. ([events-types][events-types])

9. **Webhook endpoint signing secret is per-endpoint, not per-account.** Creating two webhook endpoints (one for live, one for test, or one per Make scenario) yields two distinct `whsec_...`. Confusing them across environments produces signature failures that look like "Stripe is broken" — they are not; the wrong secret is in use. Store the mapping `endpoint_url → whsec_...` explicitly. ([sig-verif][sig-verif])

10. **Assuming Stripe will auto-disable a failing endpoint after N days.** Unlike TicketTailor (which deactivates at 10 days) and Squarespace (which may silently delete a subscription after sustained failure), Stripe leaves the endpoint enabled indefinitely and surfaces health via emails + Dashboard metrics. A broken lbkmk endpoint stays "enabled but failing" — failure detection is the merchant's responsibility, not Stripe's. Monitor Dashboard → Webhooks → success-rate; alarm at <99%.

11. **Treating events with `livemode: false` as real sales.** A test-mode webhook is fully signed, fully delivered, and fully real-looking — the only flag is the `livemode: false` boolean on the Event envelope. Route these to `rejected` (per `docs/domain-model.md` §5) automatically; do not require human review.

12. **Sending the `Idempotency-Key` with sensitive data in it.** Stripe explicitly recommends UUID v4 and warns against using email addresses or personal identifiers as keys ([idempotency][idempotency]). The key is logged and visible in Stripe Dashboard request inspector; a PII key leaks PII into Stripe's logs.

13. **Not subscribing to `charge.dispute.funds_withdrawn`.** A chargeback hits the balance silently — without subscribing to the funds-withdrawn event, the first signal LBK gets is the next payout being smaller than expected. The Drift detection in `docs/domain-model.md` §4.2 would surface this, but only after a delay; subscribing to disputes gives same-day notification.

14. **Connect-platform events arriving at a non-Connect endpoint.** If LBK's Stripe account is connected to a third-party platform (Squarespace, TicketTailor, or a marketing/analytics tool), and that platform was set up as a Connect application, events generated by that platform may arrive with an `account: "acct_LBK"` field set even on LBK's own webhook endpoint — which lbkmk should treat as informational rather than as a signal of who owns the charge. See Connect section + open question §1.

## Open questions for lbkmk

These items are unresolved by the public docs and warrant either an empirical test against an LBK staging Stripe account or owner / Stripe-support confirmation:

1. **Does LBK's Stripe Dashboard show Squarespace and TicketTailor charges natively?** I.e. when a customer pays for a Squarespace order or a TicketTailor ticket, does the resulting `ch_...` appear in LBK's *own* Stripe Dashboard, or only in a Connect-platform-owned account? This determines whether lbkmk's Stripe webhook endpoint receives those events at all, or whether they have to be relayed by the platform. Most likely: LBK's own Stripe is the merchant of record and the charges appear in LBK's Dashboard. **Confirm with owner.**

2. **Does Squarespace populate Stripe `Charge.metadata.order_id`?** And/or `Charge.description`? Empirically verifiable: pull one real LBK Squarespace-originated charge and inspect. If yes, this offers a **second** deterministic join key for Squarespace ↔ Stripe correlation (alongside the `externalTransactionId` direction already established).

3. **Does TicketTailor populate Stripe `Charge.metadata.order_id` or `Charge.description`?** And what value does TicketTailor's webhook's `payment_method.external_id` actually contain when Stripe is the processor — is it the `ch_...`, the `pi_...`, the customer email, or something else? Empirically verifiable from one real LBK TicketTailor-originated charge. Resolution of this is on the critical path for TicketTailor ↔ Stripe correlation moving from heuristic to deterministic.

4. **What `statement_descriptor` does each channel set?** This is the text appearing on the customer's bank statement (e.g. "SQUARESPACE INC", "LBK MERCH", "TT*LBK SPRING2026"). It is not a useful join key (low cardinality, truncated to 22 chars) but knowing what shows up clarifies which customer-support questions LBK should expect.

5. **Is LBK's Stripe account on a paid plan tier that affects the publication rate-limits?** Stripe's 100/sec live-mode limit is the default; certain plan tiers / negotiated contracts can be higher. Unlikely to matter at LBK volume but worth confirming when sizing backfill windows.

6. **What API version is LBK's Stripe account currently defaulted to?** Determines the payload shape lbkmk's parsers must handle. Check Dashboard → Workbench → API version. lbkmk should explicitly pin to whichever version the codebase is written against, regardless of the account default.

7. **Refund flow from Stripe Dashboard vs Squarespace UI vs TicketTailor UI** — if the owner clicks "Refund" in Stripe directly (bypassing Squarespace / TicketTailor), what events fire and what state does Squarespace/TicketTailor end up in? Possibly nothing in Squarespace (only the Stripe charge knows about it). Affects whether lbkmk can trust the channel's `refundedTotal` / `order.status: canceled` as a complete view of refunds, or must reconcile against Stripe's `refund.created` independently. This is the "out-of-band refund" gap in `docs/integrations/squarespace.md` open question §8.

8. **Are there any Connect applications attached to LBK's Stripe account?** Dashboard → Connect → Applications shows third-party apps that have OAuth access. If Squarespace or TicketTailor appear here, the integration goes through Connect and event delivery / scoping changes. If only LBK's own integrations appear, the direct-account assumption holds.

9. **What is the `application` field value on a Squarespace-originated `Charge`?** And on a TicketTailor-originated `Charge`? Stripe sets this to the Connect-application id of whoever created the charge. Useful as a coarse-grained signal of "which platform processed this" even when more specific metadata is missing.

10. **Will LBK ever sell via Stripe Checkout directly?** I.e. is the Stripe-direct sales channel actually used, or is it always Squarespace/TicketTailor underneath? Determines whether lbkmk needs to subscribe to `checkout.session.completed` at all in v1.

11. **Maximum charge / order size?** Stripe-side limits are very high (no practical cap at LBK volume), but if LBK ever processes a single charge > £10k it may trigger Radar review and delayed settlement — affecting payout reconciliation timing.

12. **Does the Stripe Dashboard expose the merchant identifier (MID) on the Charge?** Some bank-reconciliation flows key on MID. Not surfaced in standard API responses but may appear on the connected payment-method-details. Owner confirmation needed if Xero bank feed correlation requires MID parity.

## Sources

All retrieved 2026-05-22.

Authoritative Stripe documentation:

- [Stripe Webhooks (overview)][webhooks] — `https://docs.stripe.com/webhooks`
- [Webhook signature verification][sig-verif] — `https://docs.stripe.com/webhooks/signatures`
- [API event types catalog][events-types] — `https://docs.stripe.com/api/events/types`
- [Charge object reference][charge-obj] — `https://docs.stripe.com/api/charges/object`
- [PaymentIntent object reference][pi-obj] — `https://docs.stripe.com/api/payment_intents/object`
- [Balance Transaction object reference][balance-tx-obj] — `https://docs.stripe.com/api/balance_transactions/object`
- [Idempotent requests][idempotency] — `https://docs.stripe.com/api/idempotent_requests`
- [Metadata][metadata] — `https://docs.stripe.com/api/metadata`
- [API versioning][versioning] — `https://docs.stripe.com/api/versioning`
- [Rate limits][rate-limits] — `https://docs.stripe.com/rate-limits`
- [Webhook source IP addresses][ips] — `https://docs.stripe.com/ips`
- [Connect webhooks][connect-webhooks] — `https://docs.stripe.com/connect/webhooks`
- [Connect charges (Direct / Destination / Separate)][connect-charges] — `https://docs.stripe.com/connect/charges`
- [Stripe API announce mailing list][ip-announce] — `https://groups.google.com/a/lists.stripe.com/g/api-announce`
- [API changelog][changelog] — `https://docs.stripe.com/changelog`

[webhooks]: https://docs.stripe.com/webhooks
[sig-verif]: https://docs.stripe.com/webhooks/signatures
[events-types]: https://docs.stripe.com/api/events/types
[charge-obj]: https://docs.stripe.com/api/charges/object
[pi-obj]: https://docs.stripe.com/api/payment_intents/object
[balance-tx-obj]: https://docs.stripe.com/api/balance_transactions/object
[idempotency]: https://docs.stripe.com/api/idempotent_requests
[metadata]: https://docs.stripe.com/api/metadata
[versioning]: https://docs.stripe.com/api/versioning
[rate-limits]: https://docs.stripe.com/rate-limits
[ips]: https://docs.stripe.com/ips
[connect-webhooks]: https://docs.stripe.com/connect/webhooks
[connect-charges]: https://docs.stripe.com/connect/charges
[ip-announce]: https://groups.google.com/a/lists.stripe.com/g/api-announce
[changelog]: https://docs.stripe.com/changelog
