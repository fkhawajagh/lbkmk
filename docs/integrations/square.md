# Square — Integration Reference

> Document Version: 1.0 | 2026-05-22

## Role in lbkmk

Square is one of four sales channels feeding lbkmk (alongside Squarespace, Stripe, and TicketTailor). It handles LBK's **in-person card-present sales** at physical points of sale via Square Register / Terminal hardware, with the optional capacity to also process online sales through Square Online, hosted invoices, or Virtual Terminal. Square uses **its own payment rails** — not Stripe — which makes it the simplest of the four channels from a correlation standpoint: the Square `Order` (sale side) and the Square `Payment` (payment side) come from the same vendor and share deterministic foreign-key joins.

Data flow:

```
Square (POS sale, Square Online order, invoice, Virtual Terminal)
        │
        │  order.created / order.updated / payment.created / payment.updated /
        │  refund.created / refund.updated / inventory.count.updated webhooks
        ▼
Make scenario (Custom Webhook trigger)
        │  raw body + x-square-hmacsha256-signature header forwarded
        ▼
lbkmk /webhooks/square            ───►  Square Orders API
        │  HMAC-SHA256 verified            GET /v2/orders/{order_id}
        │  enqueue                         (enrich: line_items[], tenders[],
        │                                   refunds[], fulfillments[], state)
        ▼
join Square Order ↔ Square Payment ↔ Square Refund
(no cross-vendor correlation needed)
        │
        ▼
decrement Inventory Item(s)
        │
        ▼
post itemized Invoice to Xero
```

Square is **both** the sale-side and the payment-side record — there is no cross-vendor `Correlation` row required for Square sales (`docs/domain-model.md` §4.2). Within Square, an `Order` is joined to its `Payment(s)` by the payment's `order_id` field, and a `Refund` is joined to its `Payment` by the refund's `payment_id` field. These are deterministic foreign keys.

The lbkmk app never talks to Square directly — Make is the sole intermediary (`docs/domain-model.md` §6 rule 14). API-direct calls (for enrichment or backfill) would still be mediated by a Make scenario.

As with Squarespace, **Square's order webhooks are notification-only**: the body carries object identifiers but not the full order detail. The Orders API call that follows is what supplies the per-item line items, tenders, and totals. The ingestion pipeline must perform that enrichment step before a Sale Event is approvable.

## Authentication & credentials

| Aspect | Value | Source |
|---|---|---|
| Production base URL | `https://connect.squareup.com` | [access-tokens][access-tokens] |
| Sandbox base URL | `https://connect.squareupsandbox.com` | [access-tokens][access-tokens] |
| Transport | HTTPS only; notification URLs must use HTTPS for production webhook subscriptions | [build-webhooks][build-webhooks] |
| Auth schemes | Two: **Personal Access Token** (full-account scope) or **OAuth 2.0** (per-seller scoped) | [access-tokens][access-tokens] |
| Production access token prefix | `EAAA...` (production); Sandbox tokens are distinct and only valid against the sandbox base URL | [access-tokens][access-tokens] |
| Application ID prefix | `sq0idp-...` (production), `sandbox-sq0idb-...` (Sandbox) | [oauth-walkthrough][oauth-walkthrough] |
| Application secret prefix | `sq0csp-...` (production), `sandbox-sq0csb-...` (Sandbox) | [oauth-walkthrough][oauth-walkthrough] |
| OAuth access token lifetime | **30 days** — refresh via `ObtainToken` with `grant_type=refresh_token` before expiry | [oauth-walkthrough][oauth-walkthrough] |
| Webhook Subscriptions API auth | **Requires the application's personal access token** — OAuth access tokens cannot manage webhook subscriptions because webhooks are application-level, not seller-level | [access-tokens][access-tokens] |
| Webhook signing key (per subscription) | Revealed once on Endpoint Details page in Developer Console → Webhooks → Subscriptions → endpoint → "Show" in Signature Key box; usable via the Webhook Subscriptions API for rotation | [build-webhooks][build-webhooks], [validate][validate] |
| Authorization header on API calls | `Authorization: Bearer {ACCESS_TOKEN}` | [access-tokens][access-tokens] |
| API version pinning header | `Square-Version: YYYY-MM-DD` (e.g. `Square-Version: 2024-07-17`) | [versioning][versioning] |
| Webhook subscription version pinning | Each webhook subscription is independently versioned via its `api_version` field — set at create time, updated via `UpdateWebhookSubscription` | [subs-api][subs-api] |

For lbkmk: because LBK is a single-merchant integration (lbkmk acts on LBK's behalf, not on behalf of arbitrary Square sellers), the **Personal Access Token path** is the simpler choice for production. OAuth would only matter if lbkmk grew into a multi-tenant marketplace product. Store the production token and each subscription's signature key in lbkmk's secret store and surface them to Make via a Keychain (see `docs/integrations/make.md` §"Critical question 7 — secret storage").

**Secret rotation:** Square does not enforce token rotation, but the Personal Access Token can be revoked and reissued from the Developer Console. The webhook **signature key** can be rotated via the Webhook Subscriptions API — there is no documented overlap window (unlike Stripe), so rotation needs a coordinated swap or the verifier must accept both old and new for a brief window managed application-side. The exact rotation procedure is not surfaced explicitly in the developer docs and may require an empirical test or a developer-support ticket — see open question §1.

## Key concepts / data model

Square's resource graph relevant to lbkmk:

| Square resource | lbkmk mapping | Notes |
|---|---|---|
| **Merchant** (`merchant_id`) | (tenant scope) | LBK is one merchant. Every webhook payload includes `merchant_id` at the top level. |
| **Location** (`location_id`) | (configuration / inventory scoping) | A merchant can have up to 300 locations (physical stores, treatmobiles, online stores, pop-up booths). Most order/payment/inventory state is scoped to a location. ([locations][locations]) |
| **Catalog Object** (`CatalogObject`, hex-string id) | Parent of Channel SKUs of type `ITEM_VARIATION` | Wraps various sub-types: `ITEM`, `ITEM_VARIATION`, `CATEGORY`, `TAX`, `DISCOUNT`, `MODIFIER`, `MODIFIER_LIST`, `IMAGE`, `MEASUREMENT_UNIT`, `PRICING_RULE`, `PRODUCT_SET`, `QUICK_AMOUNTS_SETTINGS`, `TIME_PERIOD`. ([catalog][catalog]) |
| **Catalog Item** (`CatalogItem`, inside an `ITEM` `CatalogObject`) | Logical product | A product or service for sale; can have up to 250 `ITEM_VARIATION` children. ([catalog][catalog]) |
| **Catalog Item Variation** (`CatalogItemVariation`, inside an `ITEM_VARIATION` `CatalogObject`) | Maps 1:1 to a `Channel SKU` → `Inventory Item` | The unit of stock and the unit referenced from each `OrderLineItem.catalog_object_id`. Carries `sku` (merchant-set), `pricing_type`, `price_money`, `track_inventory`. |
| **Inventory Count** (Inventory API) | Read-only stock mirror | Tracks `IN_STOCK`, `SOLD`, `WASTE`, and other states per `(catalog_object_id, location_id)`. Subscribing to `inventory.count.updated` mirrors Square's stock state into lbkmk if desired, but per `docs/domain-model.md` §6 rule 5, Xero is the canonical writer of stock. ([inventory][inventory]) |
| **Order** (`Order`, hex-string id, e.g. `CAISENgvlJ6jLWAzERDzjyHVybY`) | `Sale Event` (channel = Square) | Top-level checkout record. Holds `line_items[]`, `tenders[]`, `refunds[]`, `fulfillments[]`, `taxes[]`, `discounts[]`, `service_charges[]`, totals, `state`, `source.name`, `location_id`, `customer_id`, `version`, `created_at`, `updated_at`. ([order-obj][order-obj]) |
| **Order Line Item** (`OrderLineItem`, inside `Order.line_items[]`) | `Line Item` | Carries `uid`, `catalog_object_id` (variant id), `catalog_version`, `name`, `quantity` (decimal string), `base_price_money`, `gross_sales_money`, `total_money`, `variation_name`, `item_type`, `modifiers[]`, `applied_taxes[]`, `applied_discounts[]`. The `item_type` enum is `ITEM | CUSTOM_AMOUNT | GIFT_CARD`. |
| **Order Source** (`OrderSource`, inside `Order.source`) | (channel sub-source disambiguation) | `OrderSource.name` is a string that identifies "the place (physical or digital) that an order originates" — e.g. `"Square Point of Sale"` for POS orders, the application name for third-party-created orders. **POS-originated orders may have `Order.source.name` set to `SQUARE_POS`.** Searchable via `SearchOrders` with `source_filter.source_names[]`. ([order-source][order-source], [search-orders][search-orders]) |
| **Tender** (`Tender`, inside `Order.tenders[]`) | (payment-side cross-reference within Square) | The means of payment applied to an order: `type` (`CARD | CASH | THIRD_PARTY_CARD | SQUARE_GIFT_CARD | NO_SALE | WALLET | BANK_ACCOUNT | BUY_NOW_PAY_LATER | OTHER`), `amount_money`, `tip_money`, `processing_fee_money`, `payment_id`. **The `payment_id` is the foreign key to the `Payment` resource.** |
| **Payment** (`Payment`, hex-string id) | Payment-side detail (same Sale Event) | The settled payment record. Carries `amount_money`, `total_money`, `tip_money`, `app_fee_money`, `processing_fee[]`, `refunded_money`, `status` (`APPROVED | PENDING | COMPLETED | CANCELED | FAILED`), `source_type`, `card_details`, `cash_details`, `external_details`, `location_id`, **`order_id`** (back-reference to the Order), `reference_id`, `customer_id`, `refund_ids[]`, `risk_evaluation`, `application_details.square_product` (`SQUARE_POS | INVOICES | VIRTUAL_TERMINAL | TERMINAL_API | ECOMMERCE_API` etc.). ([payment-obj][payment-obj]) |
| **Refund** (`PaymentRefund`, hex-string id) | Refund record on a Sale Event | Joined to the parent `Payment` by `payment_id` and to the `Order` by `order_id`. Carries `amount_money`, `app_fee_money`, `processing_fee[]`, `status` (`PENDING | COMPLETED | REJECTED | FAILED`), `reason`, `location_id`, `created_at`, `updated_at`. ([refund-obj][refund-obj]) |
| **Dispute** (Disputes API) | (out of scope for v1; flag for owner) | Chargebacks on a Square payment. Fires `dispute.created`, `dispute.state.updated`, `dispute.evidence.created`, `dispute.evidence.deleted`. ([events-ref][events-ref]) |
| **Event** (webhook envelope) | (delivery envelope) | The webhook envelope. Carries `merchant_id`, `type`, `event_id`, `created_at`, and `data.{type, id, object, deleted?}`. ([build-webhooks][build-webhooks]) |

**Currency convention:** all monetary amounts are integer values in the **smallest unit** of the currency (pence for GBP, cents for USD, yen for JPY which is zero-decimal). Same convention as Stripe and TicketTailor, opposite of Squarespace's decimal-string format. The wire shape is `{"amount": 100, "currency_code": "USD"}` — a `Money` object. ([monetary-amounts][monetary-amounts])

**Identifier shapes to expect on the wire:**

- Order, Payment, Refund, Dispute, Catalog, Location, Customer ids are opaque hex-string identifiers (typically 22-32 chars, e.g. `CAISENgvlJ6jLWAzERDzjyHVybY` for orders, `LXX23EZFG5M9S` for locations).
- Webhook subscription ids: `wbhk_...` prefix (e.g. `wbhk_b35f6b3145074cf9ad513610786c19d5`).
- Event ids (the `event_id` field on a webhook envelope): UUID-shaped (e.g. `edce24d3-bf56-46b4-b5ea-40266mnaa5a84`).

## Webhooks / events

### Headline finding — line items in webhook payloads

**Square's `order.created`, `order.updated`, and `order.fulfillment.updated` webhook payloads contain only the `Order` object identifier (and metadata) in `data.id` — they do NOT reliably embed the full `line_items[]`, `tenders[]`, or `refunds[]` array.** Square's webhook docs describe the body shape as containing `data.type`, `data.id`, and `data.object` (the affected object at the time the event was triggered), with explicit guidance to "check the webhook documentation for the specific event" for what `object` actually includes ([build-webhooks][build-webhooks]). For orders specifically, the docs do not promise that `data.object` carries the full line-item enrichment, and community reports consistently describe the order webhook as identifier-plus-state rather than full-detail. **lbkmk should treat the order webhook as a notification and follow up with `GET /v2/orders/{order_id}` to retrieve the canonical `line_items[]`, `tenders[]`, `refunds[]`, totals, and `state`.** This resolves the lbkmk equivalent of `docs/integrations/tickettailor.md` §Q1 and `docs/integrations/squarespace.md` headline question for the Square channel in the **negative**: line items require a second API call. Confirm empirically against a real LBK order — see open question §2.

For **payment** and **refund** events, the Square docs explicitly state that the `data.object` carries the affected resource (the `Payment` or `Refund` object respectively), and the example payload shown in the build-webhooks docs for `customer.created` includes the full nested `customer` object under `data.object.customer` ([build-webhooks][build-webhooks]). The same convention applies to `payment.created` / `payment.updated` / `refund.created` / `refund.updated` — they ship with the full Payment / Refund body.

### Event types lbkmk needs

The minimum set covering sale recording, payment confirmation, refund detection, and (optional) stock mirroring ([events-ref][events-ref], [orders-api][orders-api]):

| Event type | Permission | Why lbkmk needs it | Source |
|---|---|---|---|
| `order.created` | `ORDERS_READ` | **Primary** sale-side trigger. Fires for orders created by any Square product (POS, Square Online, Invoices, Virtual Terminal, Terminal API) or by API. | ([events-ref][events-ref]) |
| `order.updated` | `ORDERS_READ` | Fires on `UpdateOrder` API calls or seller updates. Use to keep `Sale Event` state in sync (e.g. partial-pay → fully-paid transitions, line-item adjustments). | ([events-ref][events-ref]) |
| `order.fulfillment.updated` | `ORDERS_READ` | Fires when an `OrderFulfillment` is created or updated. Useful only if LBK tracks fulfillment state for owner-facing UI; not required for revenue recording. | ([events-ref][events-ref]) |
| `payment.created` | `PAYMENTS_READ` | **Primary** payment-side trigger. Fires when a `Payment` is created. The `data.object` carries the full `Payment` including `order_id`, `total_money`, `processing_fee[]`, `status`. | ([events-ref][events-ref]) |
| `payment.updated` | `PAYMENTS_READ` | Fires when a `Payment` field updates — e.g. `status` moves from `APPROVED` to `COMPLETED`, or `card_details.status` changes. lbkmk needs this to know when an authorized payment actually captures. | ([events-ref][events-ref]) |
| `refund.created` | `PAYMENTS_READ` | A `PaymentRefund` was created. Carries the full `Refund` object including `payment_id`, `amount_money`, `processing_fee[]`, `status`. | ([events-ref][events-ref]) |
| `refund.updated` | `PAYMENTS_READ` | Refund status transitions (e.g. `PENDING` → `COMPLETED` / `REJECTED` / `FAILED`). | ([events-ref][events-ref]) |
| `inventory.count.updated` | `INVENTORY_READ` | (Optional, out of scope for v1) The quantity for a catalog item variation changed. Data is packaged as `InventoryCount[]`. Subscribe **only** if lbkmk wants to mirror Square's stock state — `docs/domain-model.md` §6 rule 5 says Xero is the canonical writer, so this would be advisory-only. | ([events-ref][events-ref]) |
| `dispute.created`, `dispute.state.updated`, `dispute.evidence.created`, `dispute.evidence.deleted` | `PAYMENTS_READ` | (Optional, out of scope for v1) Chargeback notifications. Owner-facing alarm only — disputes do not flow into the reconciliation pipeline in v1. | ([events-ref][events-ref]) |

For lbkmk's v1 sales-recording purpose, the **minimum subscription** is: `order.created`, `order.updated`, `payment.created`, `payment.updated`, `refund.created`, `refund.updated`. Add `inventory.count.updated` only if drift-checking against Xero is desired. Add dispute events when the dispute-handling workflow lands.

### Envelope structure

Every webhook delivery is an `application/json` POST with these headers ([build-webhooks][build-webhooks], [validate][validate]):

```
Content-Type: application/json
x-square-hmacsha256-signature: <base64-encoded hmac-sha256>
square-initial-delivery-timestamp: <ISO 8601 timestamp of the first delivery attempt>
square-retry-number: <integer, present on retries>
square-retry-reason: <http_timeout | http_error | ssl_error | other_error, present on retries>
```

And this top-level body shape ([build-webhooks][build-webhooks]):

```json
{
  "merchant_id": "{MERCHANT_ID}",
  "type": "payment.created",
  "event_id": "edce24d3-bf56-46b4-b5ea-40266mnaa5a84",
  "created_at": "2021-05-17T22:46:29Z",
  "data": {
    "type": "payment",
    "id": "{PAYMENT_ID}",
    "object": {
      "payment": { /* full Payment object */ }
    }
  }
}
```

- **`merchant_id`** — LBK's Square merchant id. Useful for multi-tenant gating.
- **`type`** — lowercase dot-separated event name (`order.created`, `payment.created`, `refund.updated`, etc.).
- **`event_id`** — unique event identifier. **Use this for dedupe.** Square explicitly calls this out: "A generated idempotency value is included as the `event_id` field in the body of each event notification. Design your application to use this value to bypass processing if it's a repeated value." ([manage][manage])
- **`created_at`** — ISO 8601 UTC timestamp the event was generated. **Do not assume strict ordering by this timestamp** — events for the same logical transaction (e.g. `order.created` and `payment.created`) may arrive in either order; see "Order of notifications" below.
- **`data.type`** — the affected object's type (`order`, `payment`, `refund`, `customer`, etc.).
- **`data.id`** — the affected object's id.
- **`data.deleted`** — Boolean, set to `true` if the object was deleted. **This field is included only when the object is deleted.**
- **`data.object`** — the affected object at the time the event triggered. For Payment and Refund events this is the full resource; for Order events it may be sparse (see headline finding) — re-fetch via `GET /v2/orders/{id}` to be safe.

### Signing / verification

- **Header:** `x-square-hmacsha256-signature` (case-insensitive; many Square examples use camel-case `X-Square-HmacSha256-Signature`).
- **Algorithm:** **HMAC-SHA256**, base64-encoded.
- **Signed payload:** **the notification URL concatenated with the raw request body** — i.e. `signed_string = notification_url + raw_body`. This is the unusual part of Square's scheme. The signature key is the per-subscription value revealed in the Developer Console. ([validate][validate])
- **Comparison:** constant-time compare against the header value. Square documents this explicitly: "A malicious agent can compromise your notification endpoint by using a timing analysis attack to determine the key you're using to decrypt and compare webhook signatures. You should use a constant-time crypto library to prevent such attacks." ([validate][validate])
- **The notification URL must match EXACTLY** what was registered for the subscription — including scheme, host, port, path, and trailing slash. Square's signature is computed against the registered notification URL string. Any rewrite at the network edge (HTTPS canonicalization, trailing-slash normalization, www-prefix change) before the request reaches lbkmk's verifier would change the URL string the receiver thinks is correct and break verification. ([validate][validate])

**Reference verification (Node.js SDK pattern, [validate][validate]):**

```js
const { WebhooksHelper } = require('square');

const isValid = await WebhooksHelper.verifySignature({
  requestBody: rawBody,
  signatureHeader: req.headers['x-square-hmacsha256-signature'],
  signatureKey: SIGNATURE_KEY,
  notificationUrl: NOTIFICATION_URL
});
```

Or equivalent shell test fixture from the docs:

```bash
curl -vX POST localhost:8000 \
  -d '{"hello":"world"}' \
  -H "X-Square-HmacSha256-Signature: 2kRE5qRU2tR+tBGlDwMEw2avJ7QM4ikPYD/PJ3bd9Og="
```

For lbkmk: signature verification must happen on the **raw body bytes** before JSON parsing. Make's Custom Webhook trigger parses JSON by default — enable **JSON pass-through** and **Get request headers** on the Custom Webhook so the original body and the `x-square-hmacsha256-signature` header are forwarded to lbkmk verbatim. The verifier must also know the **exact notification URL string that Square has registered**, not the URL as observed at lbkmk after any reverse-proxy rewriting (see `docs/integrations/make.md` §"Inbound payload — raw body forwarding to lbkmk", plus the Make-side URL preservation considerations).

**No timestamp tolerance is documented.** Square's signature is over `notification_url + raw_body` only — it does not include a timestamp like Stripe (`t=<unix>`) or TicketTailor. The `square-initial-delivery-timestamp` header exists (and on retries `square-retry-number` + `square-retry-reason`) but is not covered by the signature, so it cannot be relied on for replay protection. Replay protection therefore depends entirely on lbkmk's `(channel, external_event_id)` idempotency check (`docs/domain-model.md` §6 rule 16) keyed on `event_id` and/or the resource id in `data.id`. The signature only proves the body+URL pair has not been tampered with.

### Retry policy

**There is a documented inconsistency in Square's developer docs about webhook retry duration.** Treat the longest-window doc as authoritative (consistent with a Square Developer Forums staff post from 2021) and treat the shorter-window doc as out of date or stale guidance. Both are quoted below.

| Source | Retry duration | Notes |
|---|---|---|
| [Square Developer Forums staff post (2021)][forum-retry] | **Up to 72 hours**, with retries 1-6 on exponential backoff (1m, 2m, 4m, 8m, 16m, 32m) and retries 7-78 at 60-minute intervals | Detailed schedule; widely cited. Treat as the operational reality. |
| [Manage Webhook Operations][manage] | "If your notification URL endpoint doesn't respond with a single 2xx HTTP status code within **three weeks**, Square takes the following actions: 1. Sends a warning email after the first week. 2. Sends a warning email after the second week. 3. Sends a final warning email after the third week. Following this final email, Square automatically disables your webhook subscription." | The 3-week window is the **subscription-disable** window, not the per-event retry window. After 72 hours of failure for a given event the event is discarded; after 3 weeks of sustained subscription-wide failure the subscription is auto-disabled. |
| [Troubleshoot Webhooks][troubleshoot] | "Unsuccessful deliveries are retried for up to **24 hours**. After 24 hours, the notification is discarded and not sent again." | This page disagrees with the forums post. Likely stale. **Confirm via developer-support ticket or empirical test** — see open question §3. |

The consistent picture: **per-event retry curve is exponential-backoff-then-hourly for up to 72 hours**, and after **three weeks** of sustained subscription-wide failure (no 2xx response on any event), the entire subscription is auto-disabled and must be re-enabled or recreated.

**Other retry mechanics ([build-webhooks][build-webhooks], [manage][manage]):**

- **Successful delivery** = the endpoint returns a `2xx` status code **within 10 seconds** of receiving the POST. Slower than 10 seconds counts as a timeout (`square-retry-reason: http_timeout`).
- **Any non-2xx response, redirect, SSL error, or timeout** = unsuccessful. Square retries.
- **Retried notifications carry headers `square-retry-number` (integer) and `square-retry-reason`** (`http_timeout`, `http_error`, `ssl_error`, `other_error`).
- **Each retry generates a fresh signature** — but the `event_id` stays the same, which is the key to dedupe.
- **Webhook event logs are kept for 28 days** in the Developer Console for forensic inspection ([logs][logs]).
- **Missed events can be recovered via the Events API** — see "API surface" below.

For lbkmk: combined with Make's queue retry and lbkmk-side idempotency, the chance of a permanently-lost Square event is very low — but the 3-week subscription-disable window (in any reading) is the strictest of the four channels for **subscription-level** failure. lbkmk needs a monitoring alarm well before week 3 (the warning emails at weeks 1, 2, 3 should not be the only signal). Add a heartbeat: if no Square webhook has arrived in N hours, page someone.

### Idempotency

Square's own guidance ([manage][manage]): "Use idempotency - A generated idempotency value is included as the `event_id` field in the body of each event notification. Design your application to use this value to bypass processing if it's a repeated value."

For lbkmk: the `event_id` is the **per-delivery idempotency key**. The `data.id` (the `Order` id, `Payment` id, or `Refund` id) is the **per-resource idempotency key**. lbkmk's `(channel, external_event_id)` uniqueness should key on `data.id` — multiple events (`order.created` + several `order.updated` + retries) all describe the same underlying Square order. Belt-and-braces: dedupe on both `event_id` (per-delivery) and `data.id` (per-resource).

**Outbound idempotency (lbkmk → Square writes):** Square requires an `idempotency_key` field **in the request body** (not as a header) for most POST/PUT endpoints — `CreatePayment`, `RefundPayment`, `CreateOrder`, `BatchUpsertCatalogObjects`, etc. The key is any unique string (Square recommends a UUID v4) and is retained server-side for at least a short window to deduplicate retries. ([idempotency][idempotency]) Replaying the same key with **different parameters** errors out — the same safety net Stripe provides. lbkmk does not perform Square writes in v1, but if a future feature adds them, generate a fresh UUID per logical attempt and pass it in the request body.

### Order of notifications

Square does not publish an explicit ordering guarantee. Events for the same logical transaction (e.g. an `order.created` and the matching `payment.created`) may arrive in either order, because Square's webhook delivery system fans out across multiple internal pipelines. The right pattern (mirroring Stripe and Squarespace) is: on every event, re-derive state from `data.object` (or, if needed, re-fetch via `GET /v2/orders/{id}` or `GET /v2/payments/{id}`) and update lbkmk's Sale Event idempotently. Never trust the order of events as a causality signal.

The `Order` object carries a `version` integer that monotonically increments on each update — when applying an `order.updated` event, compare the incoming `version` against the locally-cached version and discard out-of-order updates.

## API surface we'll use

Base URLs: `https://connect.squareup.com` (production) and `https://connect.squareupsandbox.com` (Sandbox). All endpoints accept `Authorization: Bearer {ACCESS_TOKEN}`. Pin the API version via `Square-Version: YYYY-MM-DD` ([versioning][versioning], [access-tokens][access-tokens]).

| Purpose | Endpoint | Notes |
|---|---|---|
| Enrich a Sale Event after `order.created` / `order.updated` | `GET /v2/orders/{order_id}` (via `RetrieveOrder`) or `POST /v2/orders/batch-retrieve` (for multiple ids) | Returns the full `Order` including `line_items[]`, `tenders[]`, `refunds[]`, `fulfillments[]`, totals, `state`, `version`. ([order-obj][order-obj], [orders-api][orders-api]) |
| Re-fetch a payment | `GET /v2/payments/{payment_id}` (via `GetPayment`) | Returns the `Payment` with `order_id`, `total_money`, `processing_fee[]`, `refunded_money`, `status`. ([payment-obj][payment-obj]) |
| Backfill payments | `GET /v2/payments?begin_time=...&end_time=...&location_id=...&limit=100` (via `ListPayments`) | Cursor pagination via `cursor` query parameter. Useful for catching up after a Make outage. |
| Re-fetch a refund | `GET /v2/refunds/{refund_id}` (via `GetPaymentRefund`) | Returns the `PaymentRefund` with `payment_id`, `order_id`, `amount_money`, `processing_fee[]`, `status`. ([refund-obj][refund-obj]) |
| List refunds for backfill | `GET /v2/refunds?begin_time=...&end_time=...&location_id=...` (via `ListPaymentRefunds`) | Cursor pagination. |
| Search orders by source / state / location / date | `POST /v2/orders/search` (via `SearchOrders`) | Supports `source_filter.source_names[]` to filter by `Order.source.name`, `state_filter` (`OPEN | DRAFT | COMPLETED | CANCELED`), `date_time_filter`, `customer_filter`, `fulfillment_filter`. Up to 1,000 orders per page. ([search-orders][search-orders]) |
| Read catalog (Channel SKU mapping) | `GET /v2/catalog/list?types=ITEM,ITEM_VARIATION` (via `ListCatalog`) | Iterate to build the LBK catalog → Inventory Item mapping. Cursor pagination. ([catalog][catalog]) |
| Re-fetch a single catalog object | `GET /v2/catalog/object/{object_id}` (via `RetrieveCatalogObject`) | For unmapped-SKU resolution at ingestion time. |
| Read inventory state | `POST /v2/inventory/counts/batch-retrieve` (via `BatchRetrieveInventoryCounts`) | Current stock per `(catalog_object_id, location_id)`. Advisory only — Xero remains the canonical writer per `docs/domain-model.md` §6 rule 5. ([inventory][inventory]) |
| List locations | `GET /v2/locations` (via `ListLocations`) | Returns up to 300 locations for the merchant. Use `main` as the location id placeholder for the seller's primary location. ([locations][locations]) |
| Manage webhook subscriptions | `POST /v2/webhooks/subscriptions` (`CreateWebhookSubscription`), `PUT /v2/webhooks/subscriptions/{id}` (`UpdateWebhookSubscription`), `POST /v2/webhooks/subscriptions/{id}/test` (`TestWebhookSubscription`), `DELETE /v2/webhooks/subscriptions/{id}`. **Requires the application's personal access token.** | The subscription's `api_version` field is the version of events emitted — set or update via these endpoints to pin or upgrade. ([subs-api][subs-api]) |
| Recover missed events | `POST /v2/events` (via `SearchEvents`, Events API) | "Applications can use the Events API to recover and reconcile missed event notifications." Useful when an lbkmk outage causes Square to give up retrying. ([logs][logs]) |

### Rate limits

Square does not publish a single global rate-limit ceiling for the REST API. From the developer documentation and community guidance:

- **Default behavior:** API endpoints return `429 Too Many Requests` on throttling. Specific endpoints carry resource-specific limits (e.g. catalog batch operations have batch-size caps rather than RPS caps).
- **Bulk operations are preferred** — `BatchRetrieveOrders`, `BatchUpsertCatalogObjects`, `BatchRetrieveInventoryCounts` — over many single-resource calls.
- **For lbkmk at any plausible LBK volume**, rate-limit ceilings are non-binding for steady-state ingestion. Watch limits only during initial backfill across a multi-month catch-up via `SearchOrders` or `ListPayments`.

### Sandbox

Square has a **first-class Sandbox** at `https://connect.squareupsandbox.com`. Sandbox application credentials are fully isolated from production (`sandbox-sq0idb-...` vs `sq0idp-...` IDs; `sandbox-sq0csb-...` vs `sq0csp-...` secrets). Sandbox webhook subscriptions emit `livemode`-equivalent test events when actions are taken in the Sandbox seller dashboard or via API calls against the Sandbox base URL. Test card tokens (e.g. `cnon:card-nonce-ok`) simulate successful card payments without moving real money. ([oauth-walkthrough][oauth-walkthrough], [access-tokens][access-tokens])

For lbkmk: use the Sandbox extensively for empirical testing of the webhook signing scheme (especially the `url + body` concatenation behavior), order/payment correlation, refund flows, and the Events API recovery path. The Sandbox is the cleanest way to verify the "line items in payload?" headline question without contaminating LBK's production Square account.

### API versioning

Square uses a `YYYY-MM-DD` date-based version scheme, very similar to Stripe ([versioning][versioning]):

- **Application default version** is pinned in the Developer Console on the Credentials page (one default for production, one for Sandbox). All API requests use this default unless overridden via the `Square-Version: YYYY-MM-DD` header.
- **Webhook subscription version pinning:** each subscription has its own `api_version` field, set at creation via `CreateWebhookSubscription` and updatable via `UpdateWebhookSubscription`. The version pinned at the subscription determines the shape of the events Square sends. This decouples the webhook payload shape from changes to the application's default API version. ([subs-api][subs-api])
- **Breaking vs non-breaking changes:** documented in [versioning][versioning]. Breaking changes (new required fields, type changes, field renames, retirement of fields/endpoints/values) are introduced in versioned releases. Non-breaking changes (new endpoints, new optional fields, new enum values, validation loosening) are introduced into existing versions.
- **Lifecycle stages:** Beta → GA → Deprecated (≥12 months before retirement) → Retired (returns `410 GONE`). ([lifecycle][lifecycle])
- **Per-request override:** any API call can pin a different version via the `Square-Version` header.

For lbkmk: **pin a specific Square API version at both the application default level and the webhook subscription level**, and pass `Square-Version` explicitly on every outbound API call. Document the pinned version in the lbkmk configuration. Upgrade deliberately — when a new version ships, read the [release notes][release-notes], plan a minor lbkmk version bump (`docs/CLAUDE.md` semver policy), test against the new version using a Sandbox subscription pinned to the new version, then swap production.

## Best practices

1. **Pin the Square API version.** Both the application default and every webhook subscription. Pass `Square-Version` on outbound API calls. Upgrade deliberately on a minor-version-bump cycle, not opportunistically. ([versioning][versioning])
2. **Verify HMAC-SHA256 over `notification_url + raw_body`.** Base64-encoded. Use the official SDK's `WebhooksHelper.verifySignature` as a known-good reference. Constant-time compare. The notification URL string must match the registered subscription URL **byte-for-byte**, including trailing slashes. ([validate][validate])
3. **Dedupe on `data.id` (the resource id), keyed alongside `type`.** Belt-and-braces with the envelope `event_id`. Multiple events describing one Order or Payment converge on one lbkmk Sale Event row.
4. **Always respond `2xx` within 10 seconds.** Square considers slower responses or non-2xx codes a failure and starts the 72-hour retry curve. Enqueue heavy processing asynchronously and ack early. ([build-webhooks][build-webhooks])
5. **Re-fetch the Order on every order webhook.** Treat `order.created` / `order.updated` / `order.fulfillment.updated` as a tap on the shoulder, not the data itself. Use `GET /v2/orders/{id}` (or `BatchRetrieveOrders` if processing in bulk) to capture the canonical `line_items[]`, `tenders[]`, `refunds[]`. Compare `Order.version` to detect stale callbacks.
6. **Use the Order ↔ Payment ↔ Refund foreign keys.** `Order.tenders[i].payment_id` → `Payment.id`; `Payment.order_id` → `Order.id`; `Refund.payment_id` → `Payment.id`; `Refund.order_id` → `Order.id`. These are deterministic deep links — no heuristics needed. This is the simplest correlation story of the four channels.
7. **Distinguish in-person vs online via `Order.source.name` or `Payment.application_details.square_product`.** Use `source_filter.source_names[]` in `SearchOrders` to filter at query time. POS orders typically show `Order.source.name = "Square Point of Sale"` (or `SQUARE_POS`); Square Online, Square Invoices, Virtual Terminal, and third-party-API-created orders surface different `source.name` strings. ([order-source][order-source], [search-orders][search-orders])
8. **Subscribe per-application, not per-location.** A Square webhook subscription is application-scoped and receives events for **all** of the merchant's locations. Filter location-side at the lbkmk handler if location-specific routing matters (e.g. multi-event scoping per `docs/domain-model.md` §8 Q3). Subscriptions cannot be narrowed by location.
9. **Use the Events API for backfill / disaster recovery.** If lbkmk is down for longer than 72 hours (per-event retry window), `POST /v2/events` (`SearchEvents`) can recover the missed events within the developer-console log retention window (28 days). ([logs][logs])
10. **Skip Sandbox events in production.** Sandbox uses a separate base URL and separate webhook endpoints, but during initial setup a Sandbox webhook might inadvertently be pointed at production lbkmk. Gate on the production access token's environment in lbkmk configuration.
11. **Use `BatchRetrieveOrders` for bulk enrichment.** When several `order.created` webhooks arrive within a short window (a busy POS hour at an event), batch the re-fetches via `BatchRetrieveOrders` rather than firing N `GetOrder` calls.
12. **Track the subscription signing-key rotation procedure carefully.** No documented overlap window — see open question §1.

## Anti-patterns / footguns

1. **Forgetting that the HMAC signed payload is `notification_url + raw_body`, not just `raw_body`.** This is the single biggest implementation pitfall on Square integrations. Every other channel lbkmk integrates with (Stripe, TicketTailor, Squarespace) signs the body alone (or `timestamp + body`). Square is unique in concatenating the notification URL **as the merchant registered it** with the body before HMAC. Reusing a generic HMAC-over-body verifier from another integration will silently fail signature verification on every Square event. Always use Square's `WebhooksHelper` or replicate its behavior carefully. ([validate][validate])

2. **Notification URL string mismatch.** Because the URL is part of the signed payload, **any rewrite at the network edge breaks verification.** Examples: an HTTPS canonicalization that adds or strips a trailing slash; a CDN that normalizes `https://api.example.com/webhooks/square/` to `https://api.example.com/webhooks/square`; a reverse proxy that injects `X-Forwarded-Host`. The verifier must use the exact URL string Square has registered for the subscription (stored as application config), not the URL observed at the handler. ([validate][validate])

3. **Treating the order webhook as carrying full line items.** Like Squarespace's `order.create`, Square's order webhooks are notification-grade — the consumer must re-fetch to get `line_items[]`. Without the follow-up `GET /v2/orders/{id}`, lbkmk would have a Sale Event with no Line Items, failing `docs/domain-model.md` §6 rule 1. ([build-webhooks][build-webhooks])

4. **Ignoring the 10-second response window.** Square considers a delivery failed if the handler takes longer than 10 seconds to return a 2xx ([forum-retry][forum-retry]). Synchronous enrichment (calling `GET /v2/orders/{id}` then `GET /v2/payments/{id}` then writing to the DB) is unlikely to fit in 10s reliably under load. The right pattern is: verify signature → enqueue → return 200 immediately → enrich asynchronously. Failure to do this triggers the 72-hour retry curve and eventually the 3-week subscription-disable countdown.

5. **Subscribing to `order.updated` without checking `Order.version`.** Multiple `order.updated` events for the same order can arrive out of sequence, and re-fetching `GET /v2/orders/{id}` between them returns the latest state — meaning an older `order.updated` could overwrite newer state if the handler does not check the monotonic `Order.version` integer. Compare incoming `version` against locally-cached version on every update.

6. **Conflating `Order` and `Payment` lifecycles.** A Square Order can exist before any Payment (e.g. a Square Online cart created but not yet paid), and a single Order can have multiple Tenders / Payments (e.g. a split-tender POS sale where a customer pays half cash and half card). lbkmk's `Sale Event` model assumes one sale event = one order; if split tenders matter for revenue recognition, the model needs to flatten `Order.tenders[]` into multiple payment-side rows or use the aggregate via `Order.total_money` and `Order.net_amounts`. ([order-obj][order-obj])

7. **The Webhook Subscriptions API requires the personal access token, not OAuth tokens.** "Calls to the Webhook Subscriptions API and Events API require the application's personal access token because these APIs manage application-level events." ([access-tokens][access-tokens]) Using an OAuth access token returns an auth error. This is a non-obvious gotcha during CI/CD provisioning of subscriptions.

8. **The `data.deleted` field's presence is the only flag for delete events.** The `data.deleted: true` field is included only when an object is deleted — not as `false` for non-delete events. A handler that does `if (data.deleted) {…}` works; a handler that does `if (data.deleted === false) {…}` misclassifies all non-delete events. The `object` field "might not be included for `.deleted` events" — code must tolerate its absence. ([build-webhooks][build-webhooks])

9. **Documentation inconsistency on retry duration (24h vs 72h vs 3-week disable).** The Troubleshoot page says 24h, the staff-marked forum post and webhook log behavior say 72h, the Manage page describes a 3-week disable window. All three are about different things (per-event retry vs subscription auto-disable) but the documentation conflates them. **Do not rely on any single source** — assume the per-event retry is ≥72 hours and the subscription auto-disables after 3 weeks of sustained failure, and verify empirically. ([troubleshoot][troubleshoot], [manage][manage], [forum-retry][forum-retry])

10. **Subscription auto-disable is silent in production except for warning emails.** After 3 weeks of continuous failure, the subscription is auto-disabled and must be **manually re-enabled or recreated** via the Developer Console or `UpdateWebhookSubscription`. The only signal before this happens is three warning emails (weeks 1, 2, 3). Like Squarespace, this is more aggressive than Stripe (which never auto-disables). lbkmk needs a heartbeat alarm independent of Square's emails. ([manage][manage])

11. **No `Retry-After` header on 429 responses (not documented).** Square does not publish a `Retry-After` contract on rate-limited responses — back off via client-side exponential backoff and resume.

12. **Square's `idempotency_key` lives in the request body, not in a header.** Unlike Stripe (which uses `Idempotency-Key: <uuid>` as an HTTP header) and Squarespace (which uses `Idempotency-Key: <uuid>` as a header), Square requires the idempotency key as a **body field** on most POST/PUT requests (`CreatePayment`, `RefundPayment`, `CreateOrder`, `BatchUpsertCatalogObjects`, etc.). Putting it in a header silently has no effect — Square ignores it and treats the request as non-idempotent. ([idempotency][idempotency])

13. **Subscriptions are application-scoped, not seller-scoped.** A single application can have a small number of webhook subscriptions (typically capped at a documented limit; not surfaced in the developer docs reviewed here), each pinned to one `notification_url`, one set of `event_types[]`, and one `api_version`. Splitting events across multiple subscriptions for the same merchant requires multiple `notification_url`s — the docs in [troubleshoot][troubleshoot] explicitly warn against pointing two subscriptions at the same listener URL (signature-key collision). For lbkmk: one subscription, one URL, one signing key.

14. **`Order.source.name` on third-party-created orders defaults to the application name.** Per [order-source][order-source]: "The name used to identify the place (physical or digital) that an order originates. If unset, the name defaults to the name of the application that created the order." This means an Order created via the API by some third-party integration (a marketing tool, an analytics scraper) will surface its application name in `source.name`, not `SQUARE_POS` or `SQUARE_ONLINE`. A naïve filter `source.name == "Square Point of Sale"` will miss legitimately third-party-created orders that may still be real LBK sales.

## Open questions for lbkmk

These items are unresolved by the public docs and warrant either an empirical test against the LBK staging Square account, an LBK Sandbox account, or a developer-support ticket:

1. **What is the procedure for rotating a webhook subscription's signing key?** The Webhook Subscriptions API exposes `UpdateWebhookSubscriptionSignatureKey` (or similar — name needs confirmation against the current API ref), but no overlap window is documented in the developer docs reviewed here. If rotation invalidates the old key immediately, lbkmk needs to swap secrets without dropping events — possibly by deploying the new key as a secondary verification key first, then rotating, then removing the old one. Confirm via developer-support ticket or by inspecting the SDK source.

2. **Does the `data.object` on an `order.created` / `order.updated` webhook actually contain the full Order with `line_items[]`?** The build-webhooks page describes `data.object` as "the affected object at the time the event was triggered (for example, the updated `Customer` object for a `customer.updated` event)" ([build-webhooks][build-webhooks]) — implying yes, but the wording is generic and the example shown is a Customer, not an Order. Empirically verifiable by inspecting a real Square webhook delivery. If yes, the enrichment `GET /v2/orders/{id}` becomes optional rather than mandatory (though still recommended for fresh state). **This is the headline question for the Square channel and should be tested first.**

3. **Resolve the retry-duration documentation inconsistency.** [troubleshoot][troubleshoot] says 24 hours; [forum-retry][forum-retry] (staff post 2021) says 72 hours; [manage][manage] talks about a 3-week subscription-disable window. A developer-support ticket should clarify the current operational reality.

4. **What exact value does `Order.source.name` carry for each Square product?** Per [orders-api][orders-api]: "Such an order might have the `Order.source` field set to `SQUARE_POS`" — but is this `SQUARE_POS` an enum value or a string `"Square Point of Sale"`? Different docs use different forms. Empirically test orders from: Square Register (iPad POS), Square Terminal (handheld), Square Online checkout, Square Invoices, Virtual Terminal, and API-created orders. Record the exact `source.name` for each. This unlocks reliable in-person vs online disambiguation if LBK uses Square for both.

5. **How does `Payment.application_details.square_product` differ from `Order.source.name`?** The Orders API doc mentions both (`source` on Order, `application_details.square_product` on Payment) — confirm they are redundant or distinct. The payment-side field is likely more reliable for POS-vs-online disambiguation because it is set by Square itself, not by the order-creator.

6. **Does Square publish a per-account or per-application API rate-limit ceiling?** The versioning and access-tokens pages do not document a global RPS cap. A developer-support ticket or empirical test can establish the actual throttle behavior — most relevant for initial backfill.

7. **What happens to `inventory.count.updated` if the catalog item is not flagged `track_inventory: true`?** Some Square items have inventory disabled — confirming whether webhooks fire silently or are suppressed entirely affects whether lbkmk needs special handling for untracked items.

8. **Maximum size / number of `line_items[]` in a single Order?** Not documented. A bulk Square Online order with 50+ line items could test Make's 5 MB payload cap (see `docs/integrations/make.md` §"5 MB"). Empirically test with a stress-test order if LBK ever runs a flash sale.

9. **Does the LBK Square account use Square Online?** If yes, online-fulfilled merch competes with the Squarespace storefront and lbkmk's `Channel SKU` mapping needs to disambiguate the same physical SKU sold under both channels. If no, Square is purely in-person and the disambiguation is unnecessary.

10. **Does LBK use Square Invoices?** If yes, those create `Invoice` resources distinct from `Order` resources and would require subscribing to `invoice.created`, `invoice.payment_made`, etc. Out of scope for v1 unless confirmed.

11. **Does Square's `processing_fee[]` always populate on `payment.created`, or does it arrive later via `payment.updated`?** Processing-fee finalization may be deferred — affecting whether lbkmk's `Sale Event.fee` and `.net` fields are populated at sale-time or only after a subsequent update. Empirically test.

12. **What is the precise `data.id` shape on a refund webhook — the `Refund` id or the `Payment` id?** Per the events catalog, `refund.created`'s `data.type` is `refund` and `data.id` is the refund id. Confirm via empirical test that this is reliably the `Refund.id`, not the parent `Payment.id`.

## Sources

All retrieved 2026-05-22.

Authoritative Square developer documentation:

- [Build with Webhooks][build-webhooks] — `https://developer.squareup.com/docs/webhooks/build-with-webhooks`
- [Verify and Validate an Event Notification][validate] — `https://developer.squareup.com/docs/webhooks/step3validate`
- [Manage Webhook Operations][manage] — `https://developer.squareup.com/docs/webhooks/step4manage`
- [Troubleshoot Webhooks][troubleshoot] — `https://developer.squareup.com/docs/webhooks/troubleshooting`
- [Webhook Events Reference][events-ref] — `https://developer.squareup.com/docs/webhooks/v2webhook-events-tech-ref`
- [Webhook Subscriptions API][subs-api] — `https://developer.squareup.com/docs/webhooks/webhook-subscriptions-api`
- [Webhook Event Logs][logs] — `https://developer.squareup.com/docs/devtools/webhook-logs`
- [Orders API — What it does][orders-api] — `https://developer.squareup.com/docs/orders-api/what-it-does`
- [Order object reference][order-obj] — `https://developer.squareup.com/reference/square/objects/Order`
- [OrderSource object reference][order-source] — `https://developer.squareup.com/reference/square/objects/OrderSource`
- [SearchOrders / SearchOrdersSourceFilter][search-orders] — `https://developer.squareup.com/docs/orders-api/manage-orders/search-orders`
- [Payment object reference][payment-obj] — `https://developer.squareup.com/reference/square/objects/payment`
- [PaymentRefund object reference][refund-obj] — `https://developer.squareup.com/reference/square/objects/PaymentRefund`
- [Refunds API overview][refunds-api] — `https://developer.squareup.com/docs/refunds-api/overview`
- [Catalog API — What it does][catalog] — `https://developer.squareup.com/docs/catalog-api/what-it-does`
- [Inventory API — What it does][inventory] — `https://developer.squareup.com/docs/inventory-api/what-it-does`
- [Locations API — What it does][locations] — `https://developer.squareup.com/docs/locations-api/what-it-does`
- [OAuth Walkthrough][oauth-walkthrough] — `https://developer.squareup.com/docs/oauth-api/walkthrough`
- [Access Tokens and Other Credentials][access-tokens] — `https://developer.squareup.com/docs/build-basics/access-tokens`
- [Idempotency][idempotency] — `https://developer.squareup.com/docs/build-basics/common-api-patterns/idempotency`
- [Working with Monetary Amounts][monetary-amounts] — `https://developer.squareup.com/docs/build-basics/working-with-monetary-amounts`
- [Versioning in the Square API][versioning] — `https://developer.squareup.com/docs/build-basics/versioning-overview`
- [Square API Lifecycle][lifecycle] — `https://developer.squareup.com/docs/build-basics/api-lifecycle`
- [Square APIs and SDKs Release Notes][release-notes] — `https://developer.squareup.com/docs/changelog`

Community (used only to corroborate / extend authoritative claims):

- [Square Developer Forums — WebHook Notification (staff post on retry schedule, 2021)][forum-retry] — `https://developer.squareup.com/forums/t/webhook-notification/4287`

[build-webhooks]: https://developer.squareup.com/docs/webhooks/build-with-webhooks
[validate]: https://developer.squareup.com/docs/webhooks/step3validate
[manage]: https://developer.squareup.com/docs/webhooks/step4manage
[troubleshoot]: https://developer.squareup.com/docs/webhooks/troubleshooting
[events-ref]: https://developer.squareup.com/docs/webhooks/v2webhook-events-tech-ref
[subs-api]: https://developer.squareup.com/docs/webhooks/webhook-subscriptions-api
[logs]: https://developer.squareup.com/docs/devtools/webhook-logs
[orders-api]: https://developer.squareup.com/docs/orders-api/what-it-does
[order-obj]: https://developer.squareup.com/reference/square/objects/Order
[order-source]: https://developer.squareup.com/reference/square/objects/OrderSource
[search-orders]: https://developer.squareup.com/docs/orders-api/manage-orders/search-orders
[payment-obj]: https://developer.squareup.com/reference/square/objects/payment
[refund-obj]: https://developer.squareup.com/reference/square/objects/PaymentRefund
[refunds-api]: https://developer.squareup.com/docs/refunds-api/overview
[catalog]: https://developer.squareup.com/docs/catalog-api/what-it-does
[inventory]: https://developer.squareup.com/docs/inventory-api/what-it-does
[locations]: https://developer.squareup.com/docs/locations-api/what-it-does
[oauth-walkthrough]: https://developer.squareup.com/docs/oauth-api/walkthrough
[access-tokens]: https://developer.squareup.com/docs/build-basics/access-tokens
[idempotency]: https://developer.squareup.com/docs/build-basics/common-api-patterns/idempotency
[monetary-amounts]: https://developer.squareup.com/docs/build-basics/working-with-monetary-amounts
[versioning]: https://developer.squareup.com/docs/build-basics/versioning-overview
[lifecycle]: https://developer.squareup.com/docs/build-basics/api-lifecycle
[release-notes]: https://developer.squareup.com/docs/changelog
[forum-retry]: https://developer.squareup.com/forums/t/webhook-notification/4287
