# TicketTailor — Integration Reference

> Document Version: 1.0 | 2026-05-22

## Role in lbkmk

TicketTailor is one of four sales channels feeding lbkmk (alongside Squarespace, Stripe, and Square). It sells event admission only — ticket types like "Adult Pass — Spring Convention 2026" — and uses **Stripe** as its underlying payment processor.

Data flow:

```
TicketTailor  --(order.created webhook)-->  Make scenario  --(normalized POST)-->  lbkmk
                                                                                       |
                                                                                       v
                                                                       correlate with Stripe charge event
                                                                                       |
                                                                                       v
                                                                          decrement Inventory Item(s)
                                                                                       |
                                                                                       v
                                                                          post itemized Invoice to Xero
```

TicketTailor is the **sale-side** record; the matching Stripe `charge.succeeded` event is the **payment-side** record. The two are joined via a `Correlation` row (see `docs/domain-model.md` §4.2).

The lbkmk app never talks to TicketTailor directly — Make is the sole intermediary (`docs/domain-model.md` §6 rule 14). API-direct calls (for enrichment or backfill) would still be mediated by a Make scenario.

## Authentication & credentials

| Aspect | Value | Source |
|---|---|---|
| Base URL | `https://api.tickettailor.com` | [intro][intro] |
| Transport | HTTPS only, TLS 1.2+ | [intro][intro] |
| Auth scheme | HTTP Basic — API key as username, password empty (or `Basic Base64Encode(api_key)` manually) | [intro][intro] |
| Key location | Box Office Settings → API → "Generate a New Key" | [intro][intro] |
| Key scope | Per box office — a key only sees data from the box office that issued it | [intro][intro] |
| Webhook signing secret | Separate from API key; lives at Box Office Settings → API → Webhooks → "Signing secret" | [Cyclr docs][cyclr] |
| Key prefix | `sk_...` (e.g. `sk_1000_1000_VGlja2V0VGFpbG9y`) | [intro][intro] |
| Rotation cadence | **Not documented.** Keys are manually generated and named; no enforced expiry. Manual rotation policy needs to be set on lbkmk side. | [intro][intro] |

For lbkmk: both the API key and the webhook signing secret should be stored in the application's secret store (env vars / vault) and surfaced to Make. Make should not hold them long-term — the Make scenario receives the webhook and posts to lbkmk; lbkmk performs the signature verification when it can see the raw body, or trusts Make's verification if the Make scenario performs HMAC checks before forwarding.

## Key concepts / data model

TicketTailor's resource hierarchy (relevant to lbkmk):

| TicketTailor resource | lbkmk mapping | Notes |
|---|---|---|
| **Box office** | (configuration / tenant scope) | LBK is one box office. API keys are scoped here. |
| **Event series** (`es_...`) | Logical grouping | An event series can have multiple event occurrences. |
| **Event** (event occurrence, `ev_...`) | Anchors `Inventory Item`s for that event | Each occurrence has its own capacity and date. |
| **Ticket type** (`tt_...`) | Maps 1:1 to a `Channel SKU` → `Inventory Item` | E.g. `tt_230656` = "Adult Pass — Spring Convention 2026". Carries listed price + currency. |
| **Order** (`or_...`) | `Sale Event` (channel = TicketTailor) | One per checkout. Holds `line_items[]`, `issued_tickets[]`, buyer details, totals. |
| **Line item** (`li_...`, inside an order) | `Line Item` | Quantity-level: "2 × Adult Pass". `item_id` field references the `ticket_type_id` (`tt_...`). |
| **Issued ticket** (`it_...`, inside an order) | Attendee-level record | One per individual ticket (a quantity-2 line item produces 2 issued tickets). Carries `ticket_type_id`, `listed_price`, barcode, attendee details. |
| **Product** (`pr_...`) | (not used by LBK today) | TicketTailor's add-ons / merch concept; appears as `add_on_id` on issued tickets. Out of scope unless LBK starts selling add-ons through TicketTailor. |

**Currency convention:** all monetary values are integers in the **smallest currency unit (e.g. pence for GBP)**, with `currency.base_multiplier` indicating the conversion (typically `100`). lbkmk should normalize to the same convention. ([intro][intro])

**Identifier prefixes** to expect on the wire: `or_` orders, `ev_` events, `es_` event series, `tt_` ticket types, `it_` issued tickets, `li_` line items, `pr_` products, `pm_` payment methods, `wh_` webhook deliveries. ([order-by-id][order-by-id])

## Webhooks / events

**Headline finding:** **TicketTailor's `order.created` and `order.updated` webhook payloads natively include both a `line_items[]` array AND an `issued_tickets[]` array — no second API call is required to enrich the line-item detail.** Each line item carries `item_id` (which is the `ticket_type_id`), `quantity`, `total`, `type`, `description`, and `booking_fee`. Each issued ticket carries `ticket_type_id`, `listed_price`, `listed_currency`, barcode, and attendee details. This resolves `docs/domain-model.md` §8 Q1 in the **affirmative** for the order-level events. ([new-order-webhook][new-order-webhook])

### Event types subscribable from the dashboard

Configured at **Settings → API → Webhooks** in the TicketTailor box office:

| Event | Fires when |
|---|---|
| `order.created` | A new order is created | ([config][webhook-config]) |
| `order.updated` | An order's status or details change — **including cancellation** | ([config][webhook-config]) |
| `issued_ticket.created` | A new individual ticket is issued | ([config][webhook-config]) |
| `issued_ticket.updated` | An issued ticket is updated — **including voiding** | ([config][webhook-config]) |
| `event.created`, `event.updated`, `event.deleted` | Event occurrence lifecycle | ([config][webhook-config]) |
| `waitlist_signup.created` | New waitlist signup | ([config][webhook-config]) |

For lbkmk's sales-recording purpose, **`order.created` is sufficient** as the primary trigger. `order.updated` is needed to catch cancellations / refunds (status moves to `canceled`). `issued_ticket.updated` should also be subscribed if individual ticket voids matter (voids invalidate one ticket without canceling the order — see "Anti-patterns" below).

### Envelope structure

Every webhook delivery is an `application/json` POST with the following top-level shape ([structure][webhook-structure]):

```json
{
  "id": "wh_15",
  "created_at": "2025-01-01 10:00:00",
  "event": "ORDER.CREATED",
  "resource_url": "https://api.tickettailor.com/v1/orders/or_737352",
  "payload": { /* the changed resource — see below */ }
}
```

- **`id`** — the idempotency key for the delivery. **Use this** to dedupe.
- **`created_at`** — UTC datetime the webhook was generated.
- **`event`** — uppercase event name (e.g. `ORDER.CREATED`).
- **`resource_url`** — the API URL of the affected resource (handy for backfill / forensic re-fetch).
- **`payload`** — the full changed resource.

### `order.created` payload (abridged sample)

Full sample from the TicketTailor docs ([new-order-webhook][new-order-webhook]):

```json
{
  "id": "wh_15",
  "created_at": "2025-01-01 10:00:00",
  "event": "ORDER.CREATED",
  "resource_url": "https://api.tickettailor.com/v1/orders/or_737352",
  "payload": {
    "object": "order",
    "id": "or_737352",
    "status": "completed",
    "total": 0,
    "buyer_details": {
      "address": { "address_1": "...", "postal_code": "SE1 7PB" },
      "custom_questions": [],
      "email": "john@example.com",
      "first_name": "John", "last_name": "Doe", "name": "John Doe",
      "phone": "07123456789"
    },
    "created_at": 1587042691,
    "currency": { "base_multiplier": 100, "code": "gbp" },
    "event_summary": {
      "event_id": "ev_40980",
      "event_series_id": "es_50897",
      "name": "Hackney Downs 2020 Tulip Festival",
      "start_date": { "iso": "2020-05-01T18:00:00+01:00", "unix": 1588352400 },
      "end_date":   { "iso": "2020-05-01T22:30:00+01:00", "unix": 1588368600 },
      "venue": { "country": "GB", "name": "Royal Albert Hall", "postal_code": "SW7 2AP" }
    },
    "line_items": [
      {
        "object": "line_item",
        "id": "li_1505167",
        "booking_fee": 0,
        "description": "Free ticket",
        "item_id": "tt_230656",
        "quantity": 2,
        "total": 0,
        "type": "ticket",
        "value": 0
      }
    ],
    "issued_tickets": [
      {
        "object": "issued_ticket",
        "id": "it_50198",
        "barcode": "al4R5",
        "ticket_type_id": "tt_230656",
        "listed_price": 100,
        "listed_currency": { "base_multiplier": 100, "code": "gbp" },
        "status": "valid",
        "checked_in": "false",
        "event_id": "ev_40980",
        "event_series_id": "es_596",
        "order_id": "or_737352",
        "full_name": "John Doe",
        "email": "john@example.com",
        "source": "api",
        "created_at": 1587042697,
        "updated_at": 1587042697,
        "voided_at": null
      }
    ],
    "payment_method": {
      "external_id": "seller222@example.com",
      "id": "pm_6691",
      "type": "paypal"
    }
  }
}
```

**Fields most relevant to lbkmk:**

- `payload.id` — TicketTailor order id, candidate for `Sale Event.external_event_id`.
- `payload.status` — `completed | pending | canceled` ([list-orders][list-orders]). `Sale Event` should ingest with the matching `reconciliation_state` semantics.
- `payload.total` and `payload.currency` — order gross.
- `payload.line_items[].item_id` — the **`ticket_type_id`** (`tt_...`). This is the Channel SKU external_id for lbkmk's mapping table.
- `payload.line_items[].quantity` / `.total` / `.booking_fee` / `.value` — quantity-level money.
- `payload.issued_tickets[].ticket_type_id` and `.listed_price` — attendee-level fallback if a line item has a quantity of 1 but you need per-seat reservation detail.
- `payload.payment_method` — note that LBK uses Stripe for TicketTailor sales, so expect `type: "stripe"`; the `external_id` here can help correlate to the Stripe charge.
- `payload.event_summary.event_id` and `event_series_id` — to scope inventory caps (per `docs/domain-model.md` §8 Q3, lbkmk currently models event-specific inventory).

### `order.updated` payload

Same shape as `order.created`. Fires on status changes (including `canceled`), refunds, and any other order-level edit. Subscribe to it to keep `Sale Event` state in sync. ([updated-order-webhook][updated-order-webhook])

### `issued_ticket.created` / `issued_ticket.updated`

Per-ticket events. Useful if lbkmk needs to react at attendee granularity (e.g. an individual ticket is voided without canceling the order). The payload is the single `issued_ticket` object — same shape as the array entries inside an order payload. ([new-issued-ticket-webhook][new-issued-ticket-webhook])

### Signing / verification

- Header: `Tickettailor-Webhook-Signature: t=<unix-timestamp>,v1=<hmac>` ([security][webhook-security]).
- Algorithm: **HMAC-SHA256 over the concatenation `timestamp + raw_request_body`** using the shared signing secret from the webhooks dashboard.
- Verification: compute hash, constant-time-compare against `v1`, reject if the `t` timestamp is older than 5 minutes (replay protection).
- Reference implementations in PHP, Ruby, Python on the docs page ([security][webhook-security]).
- The Pipedream source verifies exactly this scheme: `crypto.createHmac("sha256", sharedSecret).update(timestamp + bodyRaw, "utf8").digest("hex")` ([pipedream-source][pipedream-source]).

For lbkmk: signature verification must happen on the **raw body** before JSON parsing. If Make is positioned in the path, either (a) Make must forward the raw body and the signature header so lbkmk verifies, or (b) Make verifies and lbkmk treats Make as trusted — option (a) is preferred because it keeps the trust boundary at lbkmk.

### Retry policy

- **Exponential backoff over 72 hours**, up to ~22 attempts ([retry][webhook-retry]).
- Treated as failed immediately on **HTTP redirect** or **network error** — so do not respond with a 3xx.
- **5 days continuous failure → warning email.**
- **10 days continuous failure → webhook auto-disabled**, must be re-enabled manually in the dashboard.
- The webhook history page in TicketTailor shows status and next-attempt time for each delivery.

### Idempotency

TicketTailor's own guidance: "It is good practice to make clients idempotent in case webhooks are sent more than once. You can track ids of already processed requests to not execute tasks more than once." ([structure][webhook-structure])

For lbkmk: the webhook envelope `id` (e.g. `wh_15`) is the per-delivery idempotency key. The `payload.id` (e.g. `or_737352`) is the per-resource idempotency key. lbkmk's `(channel, external_event_id)` uniqueness should key on `payload.id` (the order), since multiple webhook deliveries (`order.created`, `order.updated`, retries) all describe the same underlying order.

It is **not explicitly documented** whether retries reuse the same envelope `id` or generate a new one; consumers should not rely on the envelope `id` alone for dedupe ([retry][webhook-retry]). Belt-and-braces: dedupe on both `payload.id` (the source-of-truth) and the envelope `id` (the per-delivery key).

## API surface we'll use

Base URL: `https://api.tickettailor.com`. All endpoints accept `Accept: application/json` and HTTP Basic auth as described above.

| Purpose | Endpoint | Notes |
|---|---|---|
| Verify an order out-of-band (forensic / backfill) | `GET /v1/orders/:order_id` | Returns the full order including `line_items[]`, `issued_tickets[]`, buyer, totals. Same shape as webhook payload. ([get-order-by-id][order-by-id]) |
| Backfill missed orders | `GET /v1/orders` | Cursor pagination via `starting_after` / `ending_before`. Filterable by `created_at`, `status`, `event_id`, `event_series_id`, `email`, `txn_id`, `barcode`, `referral_tag`. Up to 100 per page. ([list-orders][list-orders]) |
| Reconcile a specific ticket | `GET /v1/issued_tickets/:id` | Per-attendee detail with `ticket_type_id`, `listed_price`, `status`. ([get-issued-ticket-by-id][get-issued-ticket-by-id]) |
| Backfill issued tickets | `GET /v1/issued_tickets` | List endpoint, cursor pagination. ([list-issued-tickets][list-issued-tickets]) |
| Void a single ticket | `POST /v1/issued_tickets/:id/void` | **Irreversible.** Does not refund or cancel the order. Optional `void_to_hold=true`. ([void-issued-ticket][void-issued-ticket]) |
| Inspect event capacity | `GET /v1/events/:event_id` (and `/v1/event_series/...`) | For stock-cap context per Q3 in `docs/domain-model.md` §8. |
| Health check | `GET /v1/ping` | ([dlt-source][dlt-source]) |

**Rate limit:** 5,000 requests per 30 minutes globally for the box office. Specific endpoints have lower limits (e.g. `POST /v1/issued_memberships` is 30/hour — not relevant for LBK today). Response headers: `X-Rate-Limit-Limit`, `X-Rate-Limit-Remaining`, `X-Rate-Limit-Reset`. When throttled, `Retry-After` is included. ([intro][intro])

For lbkmk: at any plausible LBK volume (a few hundred orders per event), this ceiling is irrelevant for normal ingestion. It only matters if a backfill scans the entire order history of the box office.

**Versioning:** the docs show `/v1/...` paths but do not publish a deprecation policy or version-skew guidance. The blog post announcing webhooks dates from April 2021 ([webhook-blog][webhook-blog]); the field shape has been stable since at least then. Treat the `/v1/` API as the stable contract and watch for new `/v2/` paths if/when they appear.

## Best practices

1. **Subscribe to `order.created` and `order.updated`, not `issued_ticket.created`.** The order events deliver the full picture (line items + issued tickets + totals) in one payload. Subscribing additionally to issued ticket events only matters for attendee-level edits (voids, custom-question updates).
2. **Verify the HMAC signature on the raw body before parsing JSON** — and enforce the 5-minute timestamp tolerance to block replays ([security][webhook-security]). Constant-time compare.
3. **Dedupe on `payload.id` (the order id)**, not the webhook envelope `id`. Re-deliveries and `order.updated` events for the same order should converge on the same lbkmk `Sale Event` row.
4. **Always respond `200 OK` quickly.** Heavy processing should be queued; a 3xx or a slow timeout marks the delivery as failed and starts the 72-hour retry curve ([retry][webhook-retry]).
5. **Treat `resource_url` as a re-fetch handle.** If a webhook arrives with stale or partial data (e.g. during a TicketTailor incident), `GET resource_url` returns the canonical current order.
6. **Use cursor pagination for backfills.** `starting_after` / `ending_before` with `limit=100`. Iterate to exhaustion; never assume a single page covers a date range ([intro][intro]).
7. **Currency in the smallest unit.** Store the raw integer plus `currency.code`; do not divide by `base_multiplier` until display time. Mismatches with Stripe (which also uses the smallest currency unit) are then trivial.
8. **Keep the webhook signing secret out of Make's UI history** — set it as a connection/credential, not as a hardcoded scenario value.

## Anti-patterns / footguns

1. **Voiding a single issued ticket does NOT cancel the order and does NOT refund the buyer.** `POST /v1/issued_tickets/:id/void` is irreversible and only invalidates one barcode — the parent order's `status` stays `completed` and no refund is issued by TicketTailor ([void-issued-ticket][void-issued-ticket]). For lbkmk: a `issued_ticket.updated` event with `status: voided` should NOT be treated as an order cancellation. Either model voids as a partial inventory return at the Inventory Item level, or surface them to the owner via `needs_resolution`. The domain model's current "void the Invoice" path on `Sale Event` does not apply cleanly here — voids are sub-order events.

2. **Webhook delivery counted as failed on HTTP redirect.** If lbkmk's webhook endpoint is fronted by something that 30x-redirects (HTTPS canonicalization, www-redirect, trailing-slash normalization), TicketTailor flags the delivery as failed *immediately* — no follow-through on the redirect — and enters the 72-hour retry curve ([retry][webhook-retry]). Ensure the webhook URL configured at TicketTailor matches the receiving endpoint exactly, with no redirect in front of it.

3. **Auto-disable after 10 days of continuous failure.** If a webhook fails for 10 days straight, TicketTailor disables it and it must be **manually re-enabled in the dashboard** ([retry][webhook-retry]). lbkmk needs a monitoring alarm well before day 10 (the warning email at day 5 should not be the only signal). Add a heartbeat: if no TicketTailor webhook has arrived in N hours (N = 95th percentile inter-arrival + buffer), page someone.

4. **API key scope is per-box-office, not per-environment.** TicketTailor does not appear to provide a sandbox environment ([apitracker][apitracker] lists "Sandbox environment" as not documented). Test traffic flows through the same box office as production unless LBK maintains a separate test box office. Any test orders will appear in real reports and reconciliation queues — `Sale Event` ingestion must be able to mark them `rejected` cleanly (the model already supports this via owner action — `docs/domain-model.md` §5).

5. **Webhook envelope `id` reuse on retry is undocumented.** The structure page calls out idempotency on `id` ([structure][webhook-structure]) but the retry page does not confirm whether retries reuse it ([retry][webhook-retry]). Do not assume a unique `id` per HTTP attempt — dedupe on `payload.id` as the authoritative key.

6. **No idempotency-key support on outbound API writes (orders, voids).** The API documentation does not describe an `Idempotency-Key` header equivalent to Stripe's. If lbkmk ever performs a writeback (e.g. voiding tickets in response to an owner action), retries must be guarded application-side (e.g. mark the local `Sale Event` as "void requested" before the call, reconcile on response, do not retry blindly on transient 5xx).

7. **`order.status: canceled` does not specify *why*.** Cancellations and refunds both surface as an `order.updated` with `status: canceled`. The payload does not include a refund object or refund timestamp. To distinguish a buyer-requested refund from a TicketTailor-initiated cancellation, lbkmk has to cross-reference the Stripe `charge.refunded` event (which arrives via the Stripe channel correlation). This is consistent with the domain model's correlation strategy but worth flagging in the ingestion pipeline design.

8. **Free / zero-priced orders still arrive as `order.created` events with `total: 0`.** Per the sample payload ([new-order-webhook][new-order-webhook]). lbkmk should not assume "total > 0" — `Sale Event.gross = 0` is legal and must not break the "lines sum to gross" rule (`docs/domain-model.md` §6 rule 3).

## Open questions for lbkmk

These items are unresolved by the public docs and warrant either an empirical test against a TicketTailor sandbox box office, an email to `api@tickettailor.com`, or an owner conversation:

1. **Does TicketTailor publish an OpenAPI / Swagger spec?** apitracker.io marks this as unknown ([apitracker][apitracker]). Having a machine-readable spec would let lbkmk generate types directly instead of hand-modelling.
2. **What exact `payment_method.type` values appear when Stripe is the processor?** The sample on the docs shows `"type": "paypal"`; LBK uses Stripe. Empirically test with one real LBK order: the value is probably `"stripe"` or `"card"`, and `payment_method.external_id` likely contains the Stripe charge id or PaymentIntent id (which would massively simplify correlation, bypassing the amount+time-window strategy).
3. **Does `order.updated` fire for partial refunds, or only for full cancellations?** Docs only say "updates including cancelling an order" ([config][webhook-config]). Refund handling is explicitly out of scope for lbkmk v1 (`docs/domain-model.md` §8), but the v2 design depends on this.
4. **Does TicketTailor support a sandbox / test mode at all?** Not documented. Worst case: LBK creates a parallel "test" box office and routes test webhooks there.
5. **Are the same envelope `id`s reused on retry?** Confirming this would let lbkmk dedupe more aggressively. If they are unique per attempt, the `payload.id` dedupe is essential.
6. **Tax fields.** The order payload sample does not show explicit tax breakdown lines. TicketTailor's tax model (where does tax sit — line item, order, fees?) is not visible in the public docs and needs confirmation against a real LBK order if VAT/sales tax recording matters for Xero posting.
7. **What is the maximum size / number of `issued_tickets[]` in a single order webhook?** Group bookings could produce dozens of tickets. The structure docs do not state a cap. Empirically test with a 50-ticket group purchase to ensure the webhook body does not hit any Make / lbkmk size limits.

## Sources

All retrieved 2026-05-22.

- TicketTailor developer docs (authoritative):
  - [intro][intro] — `https://developers.tickettailor.com/docs/intro/`
  - [ticket-tailor-api][api-overview] — `https://developers.tickettailor.com/docs/api/ticket-tailor-api/`
  - [list-orders][list-orders] — `https://developers.tickettailor.com/docs/api/get-all-orders/`
  - [get-order-by-id][order-by-id] — `https://developers.tickettailor.com/docs/api/get-order-by-id/`
  - [list-issued-tickets][list-issued-tickets] — `https://developers.tickettailor.com/docs/api/get-all-issued-tickets/`
  - [get-issued-ticket-by-id][get-issued-ticket-by-id] — `https://developers.tickettailor.com/docs/api/get-issued-ticket-by-id/`
  - [void-issued-ticket][void-issued-ticket] — `https://developers.tickettailor.com/docs/api/void-issued-ticket-by-id/`
  - [new-order-webhook][new-order-webhook] — `https://developers.tickettailor.com/docs/api/new-order-webhook/` (full ORDER.CREATED payload sample)
  - [updated-order-webhook][updated-order-webhook] — `https://developers.tickettailor.com/docs/api/updated-order-webhook/`
  - [new-issued-ticket-webhook][new-issued-ticket-webhook] — `https://developers.tickettailor.com/docs/api/new-issued-ticket-webhook/`
  - [webhook-intro][webhook-intro] — `https://developers.tickettailor.com/docs/webhook/introduction/`
  - [webhook-config][webhook-config] — `https://developers.tickettailor.com/docs/webhook/configuration/`
  - [webhook-structure][webhook-structure] — `https://developers.tickettailor.com/docs/webhook/structure/`
  - [webhook-security][webhook-security] — `https://developers.tickettailor.com/docs/webhook/security/`
  - [webhook-retry][webhook-retry] — `https://developers.tickettailor.com/docs/webhook/retry/`
- TicketTailor blog (announcement, dated 2021-04-15):
  - [webhook-blog][webhook-blog] — `https://www.tickettailor.com/blog/webhooks-live-on-our-api`
- Third-party (community — used only to confirm authoritative claims, not as primary sources):
  - [pipedream-source][pipedream-source] — `https://github.com/PipedreamHQ/pipedream/blob/master/components/ticket_tailor/sources/new-action/new-action.mjs` (HMAC verification implementation)
  - [cyclr][cyclr] — `https://community.cyclr.com/connector-guides/ticket-tailor/ticket-tailor-setup` (location of the signing secret in the dashboard)
  - [dlt-source][dlt-source] — `https://dlthub.com/context/source/ticket-tailor` (endpoint inventory)
  - [apitracker][apitracker] — `https://apitracker.io/a/ticket-tailor` (sandbox / OpenAPI availability — both marked unknown)

[intro]: https://developers.tickettailor.com/docs/intro/
[api-overview]: https://developers.tickettailor.com/docs/api/ticket-tailor-api/
[list-orders]: https://developers.tickettailor.com/docs/api/get-all-orders/
[order-by-id]: https://developers.tickettailor.com/docs/api/get-order-by-id/
[list-issued-tickets]: https://developers.tickettailor.com/docs/api/get-all-issued-tickets/
[get-issued-ticket-by-id]: https://developers.tickettailor.com/docs/api/get-issued-ticket-by-id/
[void-issued-ticket]: https://developers.tickettailor.com/docs/api/void-issued-ticket-by-id/
[new-order-webhook]: https://developers.tickettailor.com/docs/api/new-order-webhook/
[updated-order-webhook]: https://developers.tickettailor.com/docs/api/updated-order-webhook/
[new-issued-ticket-webhook]: https://developers.tickettailor.com/docs/api/new-issued-ticket-webhook/
[webhook-intro]: https://developers.tickettailor.com/docs/webhook/introduction/
[webhook-config]: https://developers.tickettailor.com/docs/webhook/configuration/
[webhook-structure]: https://developers.tickettailor.com/docs/webhook/structure/
[webhook-security]: https://developers.tickettailor.com/docs/webhook/security/
[webhook-retry]: https://developers.tickettailor.com/docs/webhook/retry/
[webhook-blog]: https://www.tickettailor.com/blog/webhooks-live-on-our-api
[pipedream-source]: https://github.com/PipedreamHQ/pipedream/blob/master/components/ticket_tailor/sources/new-action/new-action.mjs
[cyclr]: https://community.cyclr.com/connector-guides/ticket-tailor/ticket-tailor-setup
[dlt-source]: https://dlthub.com/context/source/ticket-tailor
[apitracker]: https://apitracker.io/a/ticket-tailor
