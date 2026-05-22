# Squarespace — Integration Reference

> Document Version: 1.0 | 2026-05-22

## Role in lbkmk

Squarespace is one of four sales channels feeding lbkmk (alongside Stripe, Square, and TicketTailor). It sells LBK's physical (and occasionally digital) merchandise via the public storefront and uses **Stripe** as its underlying card processor. The owner manages products, inventory, fulfillment, and refunds inside the Squarespace admin; lbkmk only consumes the data.

Data flow:

```
Squarespace (order placed)
        │  order.create webhook (POST, JSON)
        ▼
Make scenario (Custom Webhook trigger)
        │  raw body + Squarespace-Signature header forwarded
        ▼
lbkmk /webhooks/squarespace            ───►  Squarespace Orders API
        │  HMAC-SHA256 verified                GET /1.0/commerce/orders/{id}
        │  enqueue                             (enrich: lineItems, totals,
        ▼                                       refundedTotal, addresses)
correlate with Stripe charge event
        │
        ▼
decrement Inventory Item(s)
        │
        ▼
post itemized Invoice to Xero
```

Squarespace is the **sale-side** record; the matching Stripe `charge.succeeded` event is the **payment-side** record. The two are joined via a `Correlation` row (see `docs/domain-model.md` §4.2). The lbkmk app never talks to Squarespace directly — Make is the sole intermediary (`docs/domain-model.md` §6 rule 14).

A critical wrinkle separates Squarespace from the TicketTailor channel: **Squarespace's order webhooks are notification-only and do not carry line items**. The webhook tells lbkmk *that* an order happened and *which* order id; the Orders API call that follows is what supplies the per-item detail. The ingestion pipeline must perform that enrichment step before a Sale Event is approvable.

## Authentication & credentials

| Aspect | Value | Source |
|---|---|---|
| Base URL | `https://api.squarespace.com` | [making-requests][making-requests] |
| Transport | HTTPS only — HTTP requests are rejected | [making-requests][making-requests] |
| Versioning in URL | Per-resource — `/1.0/commerce/orders`, `/1.0/commerce/transactions`, `/1.0/webhook_subscriptions`, `/1.0/commerce/inventory`, `/v2/commerce/products`. Pre-2025 resources use `Major.Minor`; 2025-onwards uses non-SemVer integers (`v1`, `v2`, …) | [versioning][versioning] |
| Auth schemes | Two: **API Key** (Bearer token, custom-applications path) or **OAuth 2.0** (Extensions path) | [auth-perms][auth-perms] |
| API key location | Squarespace admin → Settings → Advanced → Developer API Keys → **GENERATE KEY**. Requires **Commerce Advanced** plan. Key is shown **once on creation** — record immediately | [auth-perms][auth-perms] |
| API key expiry | "API keys will never expire as long as the merchant site remains active" — no enforced rotation | [auth-perms][auth-perms] |
| OAuth path | "Squarespace Extensions" — requires applying via a Squarespace ticket form to become a registered OAuth client. Required for any integration that subscribes to webhooks or uses the Contacts API | [auth-perms][auth-perms] |
| Mandatory request headers | `Authorization: Bearer <token>`, `User-Agent: <app-description>` (default `User-Agent` headers like `curl/X` are subject to stricter rate limiting; missing `User-Agent` is rejected outright) | [making-requests][making-requests] |
| Webhook signing secret | Hex-encoded value returned **only** when a `Webhook Subscription` is created or its secret is rotated. Stored separately from the API/OAuth credentials | [verify-notif][verify-notif], [rotate-secret][rotate-secret] |
| Webhook secret rotation | `POST /1.0/webhook_subscriptions/{id}/actions/rotateSecret` — invalidates the prior secret immediately | [rotate-secret][rotate-secret] |
| OAuth scopes for webhook topics | `order.create` and `order.update` require **`WEBSITE_ORDERS`** or **`WEBSITE_ORDERS_READ`**; contact / address topics require `WEBSITE_CONTACTS`; `extension.uninstall` requires no event-specific scope | [webhook-subs][webhook-subs] |
| Webhook Subscriptions API auth | **OAuth only** — API keys are not supported on `/webhook_subscriptions` endpoints | [webhook-subs][webhook-subs] |

For lbkmk: the Webhook Subscriptions API requires OAuth, so LBK must either (a) become a registered Squarespace Extensions client, or (b) configure webhook delivery via a partner integration that has its own OAuth registration (Make does not offer a first-class Squarespace webhook subscription manager — confirm during setup). The Orders / Inventory / Transactions read APIs can use a plain API key from a Commerce Advanced site, which is the easier path for backfill and enrichment.

**Secret storage rule:** the webhook signing secret is shown once and cannot be retrieved later; if it is lost, the only path back is `rotateSecret`, which then invalidates the secret stored by every relying party. Treat it as a write-once value and store it in the application's secret manager immediately on creation ([rotate-secret][rotate-secret]).

## Key concepts / data model

Squarespace's commerce object graph relevant to lbkmk:

| Squarespace resource | lbkmk mapping | Notes |
|---|---|---|
| **Site** (`websiteId`) | (tenant scope) | LBK is one site. Every webhook payload includes the `websiteId`. |
| **Product** (`productId`, e.g. `565c8f3da7c8a3cf71d5fd0a`) | Parent of a Channel SKU | Physical, service, gift-card, or download. Managed via Products API (`/v2/commerce/products`). |
| **Product Variant** (`variantId`, UUID e.g. `88c16ee4-547b-445e-a392-bded9991ae30`) | Maps 1:1 to a `Channel SKU` → `Inventory Item` | The variant is the unit of stock and the unit identified on each line item. Variants carry their own `sku` (the merchant-set SKU code), `unitPrice`, and option values. |
| **Inventory Item** (Inventory API resource) | Read-only stock mirror | The Inventory API returns stock for **physical and service** variants only — gift cards and download products are not visible. |
| **Order** (`id`, e.g. `585d498fdee9f31a60284a37`; also has a sequential `orderNumber`) | `Sale Event` (channel = Squarespace) | One per checkout. Holds `lineItems[]`, totals, addresses, fulfillment state, payment state, refunded total. |
| **Line Item** (inside `Order.lineItems[]`) | `Line Item` | Carries `productId`, `variantId`, `productName`, `sku`, `quantity`, `unitPricePaid`, `variantOptions[]`, `customizations[]`, `lineItemType`, dimensions. |
| **Transaction Document** (Transactions API) | (payment-side cross-reference) | Per-order document carrying `payments[]` with `provider: "STRIPE"`, `externalTransactionId` (the Stripe charge id, e.g. `ch_1FFCJCLMG4qggZ0BzchTZjwR`), and `refunds[]`. **This is where the Stripe correlation lives — not on the Order resource itself.** |
| **Webhook Subscription** | (configuration) | OAuth-managed registration tying a `topics[]` set to an `endpointUrl`. |

**Currency convention:** Squarespace uses an object form: `{"currency": "USD", "value": "49.99"}`. The `value` is a **decimal string**, not an integer in the smallest unit (this differs from Stripe and TicketTailor, which both use integer minor units). lbkmk normalization must parse the decimal string with fixed precision (do not use `float`) and convert to minor units consistent with the rest of the system. Per the order sample at [retrieve-specific-order][retrieve-specific-order], every monetary field — `unitPricePaid`, `grandTotal`, `subtotal`, `shippingTotal`, `taxTotal`, `discountTotal`, `refundedTotal` — uses this same shape.

**Line item types** (enum `lineItemType`): `PHYSICAL_PRODUCT`, `DIGITAL_PRODUCT`, `SERVICE_PRODUCT`, `GIFT_CARD`, `SHIPPING`, `SUBSCRIPTION`. `variantId` is present only on `PHYSICAL_PRODUCT` and similar product-variant types; gift cards and digital downloads may not carry a `variantId`. The Channel SKU mapping in lbkmk should expect a `variantId` for tracked merch and degrade gracefully for non-variant line items.

**Identifier shapes to expect on the wire:**

- Order / Product / Customer IDs: 24-character hex Mongo-style ObjectIds (e.g. `585d498fdee9f31a60284a37`).
- Variant IDs: UUIDs (e.g. `88c16ee4-547b-445e-a392-bded9991ae30`).
- Webhook subscription IDs: UUIDs (e.g. `7aff04bb-90e0-4002-96c2-69d8162c8dae`).
- Notification IDs (the `id` field in a webhook envelope): 24-character ObjectIds (e.g. `5c2ba184b63ed3cb411ce2b1`).

## Webhooks / events

**Headline finding:** **Squarespace's `order.create` and `order.update` webhook payloads contain only `{ orderId, [update] }` inside `data` — they do NOT include line items, totals, or any product detail.** Every Sale Event ingestion must follow up with a `GET /1.0/commerce/orders/{orderId}` call to enrich. This is the opposite of TicketTailor's behavior and resolves the lbkmk equivalent of `docs/domain-model.md` §8 Q1 for the Squarespace channel in the **negative**: line items require a second API call. ([order-create][order-create], [order-update][order-update])

### Event types

Available `topics` (enum, from the Create-Subscription endpoint and the Webhooks overview):

| Topic | Fires when | Source |
|---|---|---|
| `order.create` | A new order is created on the merchant site | [order-create][order-create] |
| `order.update` | An order's `fulfillmentStatus`, refund state, cancellation state, payment, or customer email changes — see the `update` enum below | [order-update][order-update] |
| `contact.create` / `.update` / `.delete` | Contact lifecycle events | [webhooks-overview][webhooks-overview] |
| `address.create` / `.update` / `.delete` | Customer address book lifecycle | [webhooks-overview][webhooks-overview] |
| `extension.uninstall` | The merchant uninstalls a Squarespace Extension | [webhooks-overview][webhooks-overview] |

For lbkmk's sales-recording purpose: subscribe to `order.create` (primary trigger) **and** `order.update` (refunds, cancellations, fulfillment moves). Contact / address events are out of scope unless LBK begins doing CRM-style work.

There is **no event for refund-only changes** — refunds surface as an `order.update` with `update: "REFUNDED"`. See "How refunds are surfaced" below.

There is **no `inventory.update` topic** at the time of writing. Some third-party guides (e.g. [rollout][rollout-guide]) reference `inventory.update`, but it does not appear in Squarespace's authoritative Webhooks overview ([webhooks-overview][webhooks-overview]) — treat the rollout claim as outdated. Inventory state is read-only via the Inventory API; lbkmk should poll if it needs to track stock drift independently of Xero.

### Envelope structure

Every webhook delivery is an `application/json` POST with these headers ([webhooks-overview][webhooks-overview]):

```
User-Agent: Squarespace/1.0
Content-Type: application/json
Squarespace-Signature: <hex hmac-sha256>
```

And this top-level body shape ([webhooks-overview][webhooks-overview]):

```json
{
  "id": "5c2ba184b63ed3cb411ce2b1",
  "websiteId": "5f3c3d55ac435e1a051f77b3",
  "subscriptionId": "5f3c2155d947844beedda991",
  "topic": "order.create",
  "createdOn": "2020-04-22T22:18+00:00",
  "data": { /* topic-specific */ }
}
```

- **`id`** — unique notification id. **Use this** for dedupe per delivery.
- **`websiteId`** — the Squarespace site that triggered the event. Useful if lbkmk ever multi-tenants.
- **`subscriptionId`** — which webhook subscription delivered this. Useful for debugging fan-out.
- **`topic`** — uppercase or lowercase event name depending on schema source. The authoritative samples use lowercase (`order.create`); the OpenAPI schema enum at [commerce-apis-schemas][commerce-apis-schemas] also defines lowercase. Match lowercase exactly.
- **`createdOn`** — ISO 8601 UTC. **Do NOT use this for ordering** — see "Order of notifications" below.
- **`data`** — event-specific payload.

### `order.create` payload

```json
{
  "id": "5c2ba184b63ed3cb411ce2b1",
  "websiteId": "5f3c3d55ac435e1a051f77b3",
  "subscriptionId": "5f3c2155d947844beedda991",
  "topic": "order.create",
  "createdOn": "2020-04-22T22:18+00:00",
  "data": {
    "orderId": "5f3c39ce69e11e796f19990e"
  }
}
```

That is the full payload ([order-create][order-create]). The `data` object contains a single field: `orderId`. To get the actual order detail, lbkmk must call `GET /1.0/commerce/orders/{orderId}`.

### `order.update` payload

```json
{
  "id": "5c2ba184b63ed3cb411ce2b1",
  "websiteId": "5f3c3d55ac435e1a051f77b3",
  "subscriptionId": "5f3c2155d947844beedda991",
  "topic": "order.update",
  "createdOn": "2020-04-22T22:18+00:00",
  "data": {
    "orderId": "5f3c39ce69e11e796f19990e",
    "update": "FULFILLED"
  }
}
```

The `update` field's enum values are `FULFILLED`, `REFUNDED`, `CANCELED`, `MARKED_PENDING`, `EMAIL_UPDATED` ([order-update][order-update], [commerce-apis-schemas][commerce-apis-schemas]). Each value tells lbkmk *what* changed but not the new value — a fresh `GET /1.0/commerce/orders/{orderId}` is still required to read totals and `refundedTotal`.

### Order resource (returned by `GET /1.0/commerce/orders/{id}`)

This is the enrichment payload. Fields most relevant to lbkmk ([retrieve-specific-order][retrieve-specific-order]):

| Field | Type | Notes for lbkmk |
|---|---|---|
| `id` | string (ObjectId) | `Sale Event.external_event_id` |
| `orderNumber` | string | Human-readable sequential number, useful in UI |
| `channel` | enum `web | pos` | `web` = storefront; `pos` = Squarespace Point of Sale (LBK does not use POS today) |
| `channelName` | string | Set only for orders imported from third-party channels (e.g. `"Faire Wholesale"`); native storefront orders typically omit this. **Useful: lbkmk can ignore third-party-channel orders if needed.** |
| `customerEmail`, `customerId` | string | Buyer identity |
| `createdOn`, `modifiedOn` | ISO 8601 | `createdOn` → `Sale Event.occurred_at` |
| `lineItems[]` | array | Per-line: `productId`, `variantId`, `productName`, `sku`, `quantity`, `unitPricePaid {currency, value}`, `variantOptions[]`, `customizations[]`, `lineItemType`. **This is where the Channel SKU mapping happens.** Use `variantId` as the external_id when present; fall back to `productId` for non-variant items. |
| `subtotal`, `shippingTotal`, `taxTotal`, `discountTotal`, `grandTotal` | money objects | Sum-of-lines check (`docs/domain-model.md` §6 rule 3): `subtotal + shippingTotal + taxTotal − discountTotal = grandTotal`. **Note `priceTaxInterpretation`:** `EXCLUSIVE` means `unitPricePaid` is pre-tax; `INCLUSIVE` means tax is baked in. |
| `refundedTotal` | money object | Non-zero means at least one refund has been issued. **Read this on every `order.update` with `update: "REFUNDED"`** to find out the cumulative refunded amount. |
| `fulfillmentStatus` | enum `PENDING | FULFILLED | CANCELED` | `CANCELED` corresponds to an `order.update` with `update: "CANCELED"`. |
| `fulfillments[]` | array | Shipment records (carrier, service, trackingNumber). Not needed for invoicing but useful for owner-facing UI. |
| `billingAddress`, `shippingAddress` | objects | Buyer addresses. |
| `formSubmission[]` | array | Squarespace checkout-form fields (e.g. "How did you hear about us?"). Out of scope. |
| `testmode` | boolean | **`true` for test-mode payments.** lbkmk should auto-reject these (route directly to `rejected` state — see `docs/domain-model.md` §5). |

**Crucially, the Order resource does NOT include a Stripe charge id or any `paymentReference` field.** The payment-side correlation lives in the **Transactions API** — see "API surface we'll use" below.

### Signing / verification

- **Header:** `Squarespace-Signature: <hex>`
- **Algorithm:** HMAC-SHA256 over the **raw HTTP request body bytes** (UTF-8, no whitespace normalization), keyed by the **hex-decoded** subscription secret. **The hex secret must be converted to raw bytes before being used as the HMAC key — using the hex string directly produces a different signature and will fail to verify.** ([verify-notif][verify-notif])
- **Comparison:** constant-time string compare against the header value.
- **Reference code (from the docs):**

  ```js
  const expectedSignature = crypto
    .createHmac('sha256', Buffer.from(secret, 'hex'))
    .update(payload)
    .digest('hex');

  const isValid = crypto.timingSafeEqual(
    Buffer.from(expectedSignature),
    Buffer.from(headerSignature)
  );
  ```

  Or in shell: `echo -n "$PAYLOAD" | openssl sha256 -mac hmac -macopt hexkey:$SECRET`.

- **No timestamp-tolerance protection.** Unlike Stripe and TicketTailor (which include a `t=<unix>` in the signature header and require replay-window checks), Squarespace's signature is over the body alone. Replay protection must come from lbkmk's `(channel, external_event_id)` idempotency check (`docs/domain-model.md` §6 rule 16) keyed on the notification `id` and/or the `orderId`. The signature only proves the body has not been tampered with.

For lbkmk: signature verification must happen on the **raw body bytes** before JSON parsing. Make's Custom Webhook trigger parses JSON by default — enable **JSON pass-through** and **Get request headers** on the Custom Webhook so the original body and the `Squarespace-Signature` header are forwarded to lbkmk verbatim (see `docs/integrations/make.md` §"Inbound payload — raw body forwarding to lbkmk").

### Retry policy

- **Successful delivery** = the endpoint returns a `2xx` status code ([notif-delivery][notif-delivery]).
- **Any non-2xx response or timeout** = unsuccessful. Squarespace retries.
- **Retry window: up to 48 hours.** Retry count and backoff are not documented beyond "several times for up to 48 hours" — treat the curve as opaque.
- **Auto-disable:** "Squarespace may delete a webhook subscription if multiple requests are unsuccessful." The exact threshold is not documented, but the *subscription is deleted outright* rather than disabled — lbkmk would have to re-create the subscription via the API and re-issue a secret. This is more aggressive than TicketTailor (which only disables) and Stripe (which only emails after N days). ([notif-delivery][notif-delivery])

For lbkmk: the 48-hour retry window is shorter than Stripe (~3 days) and TicketTailor (72 hours). Combined with the silent-deletion-on-repeat-failure policy, the operational tolerance for sustained downtime is the lowest of the four channels. Treat sustained 5xx from lbkmk as a P1 incident.

### Idempotency

Squarespace's own guidance: "In rare circumstances, webhook endpoints may receive a notification more than once. To gracefully handle duplicates, it is important for webhook endpoints to take this into account by tracking which notification `id`s have already been processed." ([notif-delivery][notif-delivery])

For lbkmk: the webhook envelope `id` is the per-delivery idempotency key. The `data.orderId` is the per-resource idempotency key. lbkmk's `(channel, external_event_id)` uniqueness should key on `data.orderId` — multiple deliveries (`order.create` + several `order.update`s + retries) all describe the same underlying Squarespace order. Belt-and-braces: dedupe on both `id` (per-delivery) and `data.orderId` (per-resource).

### Order of notifications

**Squarespace explicitly does not guarantee delivery order.** "Squarespace does not guarantee delivery in the order the events occurred, nor when the notifications were generated, as indicated by their `createdOn` field. Webhook endpoints should expect to receive notifications out of order, and handle them accordingly." ([notif-delivery][notif-delivery])

This is a footgun — see "Anti-patterns" §3 below. For lbkmk: always re-`GET` the order resource on every received update; never trust the sequence of `order.update.update` values across deliveries.

## API surface we'll use

Base URL: `https://api.squarespace.com`. All endpoints require `Authorization: Bearer <token>` and a non-default `User-Agent` header. All requests over HTTPS only.

| Purpose | Endpoint | Notes |
|---|---|---|
| Enrich a Sale Event after webhook | `GET /1.0/commerce/orders/{id}` | The bread-and-butter call. Returns the full Order including `lineItems[]`, totals, addresses, `refundedTotal`, `fulfillmentStatus`, `testmode`. ([retrieve-specific-order][retrieve-specific-order]) |
| Backfill / catch up after Make outage | `GET /1.0/commerce/orders?modifiedAfter={ts}&modifiedBefore={ts}` | Up to 50 orders per page, ordered by `modifiedOn` descending, cursor pagination via `pagination.nextPageCursor`. Filterable by `customerId`, date range, `fulfillmentStatus`. ([retrieve-specific-order][retrieve-specific-order]) |
| Cross-reference Stripe charge id | `GET /1.0/commerce/transactions/{documentIds}` or `GET /1.0/commerce/transactions?modifiedAfter=...` | Returns a Transaction Document per order, with `payments[].provider = "STRIPE"` and `payments[].externalTransactionId = "ch_..."` (the Stripe charge id). **This is the field that simplifies Stripe correlation — see "headline finding" on Stripe id below.** ([retrieve-spec-trans][retrieve-spec-trans]) |
| Read stock | `GET /1.0/commerce/inventory` and `GET /1.0/commerce/inventory/{variantIds}` | Stock state per variant. Read-only mirror; per `docs/domain-model.md` §6 rule 5, Xero is the writer. Squarespace inventory is the channel-side cap, not the canonical count. ([inventory-overview][inventory-overview]) |
| Adjust stock | `POST /1.0/commerce/inventory/adjustments` | **Requires `Idempotency-Key` header.** lbkmk should not call this in v1 — Xero is the writer. ([idempotency-key][idempotency-key]) |
| Import third-party orders (NOT used by lbkmk) | `POST /1.0/commerce/orders` | Creates an order on Squarespace from an external channel. Requires `Idempotency-Key`. **Stricter rate limit: 100/hour/website when using an API key** (does not apply to OAuth). Out of scope for lbkmk. ([rate-limits][rate-limits], [retrieve-specific-order][retrieve-specific-order]) |
| Manage webhook subscriptions | `POST /1.0/webhook_subscriptions`, `POST .../actions/rotateSecret`, `GET /1.0/webhook_subscriptions`, `DELETE .../{id}` | **OAuth only — no API key access.** ([webhook-subs][webhook-subs]) |
| Send a test notification | `POST /1.0/webhook_subscriptions/{id}/actions/sendTestNotification` | Useful for smoke-testing the lbkmk endpoint. **One-time only — Squarespace does not retry test notifications.** ([webhook-subs][webhook-subs]) |
| Products (read for SKU mapping) | `GET /v2/commerce/products`, `GET /v2/commerce/products/{ids}` | Note `/v2/`, not `/1.0/`. Used during the unmapped-SKU resolution flow to look up the human-readable name for a `productId` / `variantId`. ([versioning][versioning]) |

### Rate limits

| Scope | Limit | Behavior |
|---|---|---|
| Global per token | **300 requests per minute** (~5 rps) | `429 Too Many Requests` over the line, **1-minute cool-down** ([rate-limits][rate-limits]) |
| Create-order endpoint (`POST /1.0/commerce/orders`) | **100/hour/website when using API key** — does NOT apply when using OAuth | Stricter to discourage spam from custom apps; lbkmk does not call this endpoint ([rate-limits][rate-limits]) |
| 5xx errors | Documented as "sometimes transient" | "Implement a retry strategy using exponential backoff and halting execution after an appropriate number of attempts" ([responses-error][responses-error]) |

For lbkmk: at any plausible LBK volume (a few hundred orders per month), the 300/min global limit is non-binding for steady-state ingestion. A backfill loop (`GET /1.0/commerce/orders?modifiedAfter=...`) at 5 rps clears thousands of orders in minutes. Watch the limit during initial onboarding or a multi-month catch-up.

### Versioning policy

- Each resource path has its own version string. As of 2026-05-22: orders, inventory, transactions, profiles, webhook_subscriptions are all `1.0`; products is `v2` (legacy `1.0`, `1.1` still served); contacts is `v1`. ([versioning][versioning])
- **Pre-2025 versions used SemVer-style `Major.Minor` where minor updates sometimes introduced breaking changes.** From 2025 onwards, Squarespace uses non-SemVer integer versions (`v1`, `v2`, …) and only bumps on breaking changes. ([versioning][versioning])
- Non-breaking changes that consumers must tolerate without a version bump: new response fields, relaxed validation, new optional query parameters, new HTTP methods on existing endpoints, bug fixes. Webhook payloads carry the same caveat: "Squarespace reserves the right to add properties and fields without a version change." ([webhooks-overview][webhooks-overview])
- **Webhook Subscriptions API is at version 1.0 (current) — not beta.** No deprecation notice is published; the API has been stable since at least 2020 (the createdOn date on the docs page). ([webhook-subs-overview][webhook-subs-overview])
- Legacy versions are supported with "significant advance notice before deprecating." A formal sunset timeline is not published.

For lbkmk: pin to `/1.0/commerce/orders`, `/1.0/commerce/transactions`, `/1.0/webhook_subscriptions`, `/v2/commerce/products`. Parse JSON permissively (ignore unknown fields). Watch the [changelog][changelog] page.

## Best practices

1. **Treat `order.create` as a tap on the shoulder, not the data itself.** Every Sale Event ingestion fetches `GET /1.0/commerce/orders/{orderId}` after webhook receipt. Without this, lbkmk has no `lineItems[]`. Cache the response keyed by `(orderId, modifiedOn)` so repeated `order.update`s don't redundantly call the API.
2. **Verify HMAC-SHA256 on the raw body, with `Buffer.from(secret, 'hex')`.** Constant-time compare. Reject on mismatch. Forgetting to hex-decode the secret is the most common implementation mistake ([verify-notif][verify-notif]).
3. **Dedupe on `data.orderId` (the order), not the envelope `id`.** `order.create` and many `order.update`s all map to one Squarespace order and should converge on one lbkmk Sale Event row.
4. **Always respond `2xx` quickly.** Queue heavy processing asynchronously. Any non-2xx (or timeout) starts the 48-hour retry curve and counts toward the silent-deletion threshold ([notif-delivery][notif-delivery]).
5. **Cross-reference the Stripe charge id via the Transactions API.** `GET /1.0/commerce/transactions/{orderId}` returns `payments[].provider = "STRIPE"` and `payments[].externalTransactionId = "ch_..."`. Use this as the deterministic key for Stripe correlation in place of the amount+time-window heuristic that `docs/domain-model.md` §4.2 falls back to.
6. **Skip orders with `testmode: true`.** Auto-reject in lbkmk (`Sale Event.state = rejected`, reason `"squarespace_testmode"`).
7. **Re-fetch on every update, ignore the delivery order.** Notifications arrive out of order ([notif-delivery][notif-delivery]); the only reliable state is whatever `GET /1.0/commerce/orders/{id}` returns at refetch time. Compare `modifiedOn` to detect stale callbacks.
8. **Use cursor pagination for backfills.** `GET /1.0/commerce/orders?modifiedAfter=...&modifiedBefore=...`, follow `pagination.nextPageCursor`. Up to 50 per page. Cursor cannot be combined with `modifiedAfter`/`modifiedBefore` after the first page — feed the next page via the cursor alone ([retrieve-specific-order][retrieve-specific-order]).
9. **Monetary values are decimal strings.** Parse `{"currency":"USD","value":"49.99"}` with a fixed-precision type (Decimal in Elixir, BigDecimal elsewhere). Never `parseFloat`. Convert to minor units once for the internal canonical representation.
10. **Set a non-default `User-Agent` header.** Default values like `curl/X` or empty user-agents are subject to stricter rate limiting (and missing UA is rejected) ([making-requests][making-requests]). Use something descriptive like `lbkmk/0.1 (+https://lbkmk.example.com)`.
11. **Rotate the webhook secret on a schedule.** API keys have no expiry, but the webhook signing secret can be rotated via `POST /webhook_subscriptions/{id}/actions/rotateSecret`. Coordinate the rotation with lbkmk's secret-store update — the old secret is invalidated immediately on rotation, so any verifier still using it will start rejecting messages.
12. **Subscribe to the minimum set of topics.** lbkmk needs `order.create` and `order.update` only. Avoid `contact.*` and `address.*` — those carry PII and only matter if lbkmk grows into CRM territory.

## Anti-patterns / footguns

1. **Treating the webhook as the data.** The most common Squarespace integration mistake — assuming the webhook body contains order detail. It does not. Without the follow-up `GET /1.0/commerce/orders/{id}`, lbkmk would have a Sale Event with no Line Items, which fails `docs/domain-model.md` §6 rule 1 (cannot approve). Either the ingestion pipeline does the enrichment synchronously before persisting, or the Sale Event lands in `needs_resolution` until enrichment completes. ([order-create][order-create])

2. **Using the hex secret string directly as the HMAC key.** The docs explicitly note: "The hex-encoded secret should be decoded to raw bytes when constructing the HMAC otherwise the expected signature won't match." ([verify-notif][verify-notif]) Every language's HMAC API will happily accept the hex string as a key and produce a *wrong* signature that silently mis-matches. Test with the docs' Node example output as a known-good fixture.

3. **Trusting `createdOn` for event ordering.** Squarespace explicitly states notifications can arrive out of order, and `createdOn` is not authoritative for sequencing ([notif-delivery][notif-delivery]). A naive ordering by `createdOn` will misclassify late-arriving `order.create` events as duplicates of `order.update` events that arrived first. Always re-fetch the canonical order resource; use `modifiedOn` from the Order resource (not the envelope) as the freshness anchor.

4. **Silent subscription deletion on repeated failure.** The notification-delivery docs warn "Squarespace may delete a webhook subscription if multiple requests are unsuccessful" ([notif-delivery][notif-delivery]). Unlike TicketTailor (disables, must re-enable in dashboard) or Stripe (emails the merchant), Squarespace can **delete** the subscription entirely — leaving no Squarespace-side artifact to reactivate. lbkmk must monitor delivery health independently (e.g. heartbeat alarm on Make's `queueCount` and on lbkmk's `time-since-last-Squarespace-event`) so the silent deletion does not go unnoticed.

5. **Webhook Subscriptions API is OAuth-only.** API keys do not work on `/webhook_subscriptions` endpoints ([webhook-subs][webhook-subs]). To create or manage subscriptions, LBK must become a Squarespace Extensions OAuth client (via a ticket form). Setting up webhooks therefore has a longer lead time than configuring a TicketTailor or Stripe equivalent.

6. **`channelName` collision.** Squarespace uses `channelName` to mark *imported* third-party orders (e.g. orders pushed from Faire Wholesale via `POST /1.0/commerce/orders` — see [retrieve-specific-order][retrieve-specific-order] example). LBK's "channel" vocabulary in `docs/domain-model.md` §3 is different — it refers to LBK's own four sales channels. Do not propagate Squarespace's `channelName` field into lbkmk's `Sale Event.channel` enum; map only orders where `channel == "web"` (or `pos`) to `Sale Event.channel = squarespace`. Imported third-party orders may be intentionally ignored.

7. **No order id in the URL of `order.update`'s implicit "what changed?" question.** The `update` enum tells you *which kind* of change (`FULFILLED`, `REFUNDED`, `CANCELED`, `MARKED_PENDING`, `EMAIL_UPDATED`) but not the new value. For refunds in particular, the only way to know the *amount* refunded is to re-fetch the Order and read `refundedTotal`. Do not infer the refund amount from `grandTotal − previous_refundedTotal` cached locally — there is no guarantee deliveries arrive in order ([notif-delivery][notif-delivery]).

8. **Refund correlation across two APIs.** The Order resource carries `refundedTotal` (a sum) but **not** the individual refund transactions. To get per-refund detail (refund id, `refundedOn` timestamp, Stripe refund id `re_...`), lbkmk must call the Transactions API: `GET /1.0/commerce/transactions/{orderId}` → `payments[].refunds[].externalTransactionId`. This is two API calls (Orders + Transactions) per refund update. ([retrieve-spec-trans][retrieve-spec-trans])

9. **`testmode: true` orders look identical to real orders otherwise.** A Squarespace test-payment order produces a real `order.create` webhook, a real Order resource, and real-looking line items — the only flag is the boolean `testmode` field at the top of the Order. lbkmk's ingestion must check this on every order and route to `rejected` rather than treating it as a normal sale (`docs/domain-model.md` §5).

10. **The Webhook Subscriptions API ignores `Idempotency-Key`.** Only `POST /commerce/orders` (create third-party order) and `POST /commerce/inventory/adjustments` require/honor the header ([idempotency-key][idempotency-key]). Re-issuing the same `POST /webhook_subscriptions` request will create a duplicate subscription. lbkmk's webhook-management code must check-then-create (or rotateSecret-then-update) rather than blindly POSTing.

11. **API key shown once.** Misplacing the API key after creation means generating a new one from the admin — there is no recovery flow ([auth-perms][auth-perms]). Apply the same write-once handling to the API key as to the webhook signing secret.

12. **Squarespace's "Commerce Advanced" plan gate on API keys.** API keys can only be generated on Commerce Advanced sites ([auth-perms][auth-perms]). If LBK is on a lower-tier Commerce plan, the API-key path is unavailable and OAuth (Extensions) is the only option. Confirm the LBK Squarespace plan tier before designing the ingest pipeline around API keys.

## Open questions for lbkmk

These items are unresolved by the public docs and warrant either an empirical test against an LBK staging site or a support ticket to Squarespace:

1. **What is the exact retry curve inside the 48-hour window?** Docs say "several times for up to 48 hours" ([notif-delivery][notif-delivery]) but do not publish the schedule (linear? exponential? max-attempts?). Matters for sizing lbkmk's downtime tolerance.

2. **What is the silent-deletion threshold?** "Multiple requests are unsuccessful" is vague — 5 in a row? 10 over a day? Lack of clarity means lbkmk must monitor heartbeats rather than rely on Squarespace's tolerance.

3. **What is the LBK Squarespace plan tier?** Determines whether API keys are available or only OAuth. Affects the secret-management story and what credentials lbkmk needs from the owner.

4. **Does the test-notification endpoint (`POST .../actions/sendTestNotification`) verify the lbkmk-side HMAC?** That is, does Squarespace sign the test payload with the subscription's real secret? If yes, it is a usable smoke-test for the verification path. If no, lbkmk needs an alternative test fixture.

5. **What is the `Order.testmode` semantics exactly?** Specifically: does `testmode: true` also appear for orders made with the real card but flagged later by the merchant, or only when Squarespace is in payment test mode? Owner-confirmation needed.

6. **Are there gift-card or store-credit redemptions in the Order line items?** Gift cards appear in `Transaction.payments[].giftCardId` ([retrieve-spec-trans][retrieve-spec-trans]) but it is unclear whether gift-card *redemption* surfaces as a discount line or as a `lineItemType: GIFT_CARD` line. Affects whether LBK's gift-card sales need to be modeled as a separate channel concept.

7. **Maximum order size?** The docs do not state a cap on `lineItems[]` length or `orderNumber` range. A bulk order with 100+ items could test Make's 5 MB payload cap (see `docs/integrations/make.md` §"5 MB"). Empirically test with a stress-test order if LBK ever runs a flash sale.

8. **How does Squarespace report refunds done outside Squarespace?** If a refund is issued directly from the Stripe dashboard (bypassing Squarespace's UI), does that surface as an `order.update` with `update: "REFUNDED"`, or does it only appear in Stripe? Owner workflow question that affects whether lbkmk can trust Squarespace as the refund source-of-truth.

9. **OAuth scope minimization for webhooks.** Subscribing to `order.create`/`order.update` requires `WEBSITE_ORDERS` or `WEBSITE_ORDERS_READ` ([webhook-subs][webhook-subs]). Does the read-only scope satisfy webhook subscription, or does any write-side scope sneak in? Smaller blast radius if read-only suffices.

10. **Does the Webhook Subscriptions API rate-limit at 300/min like the rest, or under a different ceiling?** Not stated explicitly in [rate-limits][rate-limits]. Matters only for high-frequency rotation/test flows, which lbkmk does not do in steady state.

## Sources

All retrieved 2026-05-22.

Authoritative Squarespace developer docs:

- [Commerce APIs Overview][commerce-overview] — `https://developers.squarespace.com/commerce-apis/overview`
- [Making requests to Commerce APIs][making-requests] — `https://developers.squarespace.com/commerce-apis/making-requests`
- [Authentication and permissions][auth-perms] — `https://developers.squarespace.com/commerce-apis/authentication-and-permissions`
- [Rate limits][rate-limits] — `https://developers.squarespace.com/commerce-apis/rate-limits`
- [Idempotency-Key header][idempotency-key] — `https://developers.squarespace.com/commerce-apis/idempotency-key`
- [Versioning][versioning] — `https://developers.squarespace.com/commerce-apis/versioning`
- [Responses & error handling][responses-error] — `https://developers.squarespace.com/commerce-apis/responses-error-handling`
- [Changelog][changelog] — `https://developers.squarespace.com/commerce-apis/changelog`
- [Orders API overview][orders-overview] — `https://developers.squarespace.com/commerce-apis/orders-overview`
- [Orders API reference (incl. List / Get / Create / Fulfill)][retrieve-specific-order] — `https://developers.squarespace.com/commerce-apis/retrieve-specific-order`
- [Transactions API reference][retrieve-spec-trans] — `https://developers.squarespace.com/commerce-apis/retrieve-specific-transactions`
- [Inventory API overview][inventory-overview] — `https://developers.squarespace.com/commerce-apis/inventory-overview`
- [Webhook Subscriptions API overview][webhook-subs-overview] — `https://developers.squarespace.com/commerce-apis/webhook-subscriptions-overview`
- [Webhook Subscriptions API reference][webhook-subs] — `https://developers.squarespace.com/commerce-apis/webhooksubscriptions`
- [Rotate a subscription secret][rotate-secret] — `https://developers.squarespace.com/commerce-apis/rotate-subscription-secret`
- [Webhooks overview][webhooks-overview] — `https://developers.squarespace.com/webhooks/overview`
- [Verifying notifications][verify-notif] — `https://developers.squarespace.com/webhooks/verifying-notifications`
- [Notification delivery][notif-delivery] — `https://developers.squarespace.com/webhooks/notification-delivery`
- [Order create event][order-create] — `https://developers.squarespace.com/webhooks/events/order-create`
- [Order update event][order-update] — `https://developers.squarespace.com/webhooks/events/order-update`
- [Commerce APIs schemas (OpenAPI)][commerce-apis-schemas] — `https://commerce-apis.squarespace.com/commerce-apis/~schemas`

Third-party (community — used only to corroborate authoritative claims):

- [Rollout — Squarespace API essentials][rate-limit-rollout] — `https://rollout.com/integration-guides/squarespace/api-essentials` (rate-limit cooldown, create-order API-key vs OAuth distinction)
- [Rollout — Building a Squarespace webhook integration][rollout-guide] — `https://rollout.com/integration-guides/squarespace/quick-guide-to-implementing-webhooks-in-squarespace` (signature verification implementation reference; note: claims an `inventory.update` topic that is **not** in the authoritative Webhooks overview — disregard that claim)

[commerce-overview]: https://developers.squarespace.com/commerce-apis/overview
[making-requests]: https://developers.squarespace.com/commerce-apis/making-requests
[auth-perms]: https://developers.squarespace.com/commerce-apis/authentication-and-permissions
[rate-limits]: https://developers.squarespace.com/commerce-apis/rate-limits
[idempotency-key]: https://developers.squarespace.com/commerce-apis/idempotency-key
[versioning]: https://developers.squarespace.com/commerce-apis/versioning
[responses-error]: https://developers.squarespace.com/commerce-apis/responses-error-handling
[changelog]: https://developers.squarespace.com/commerce-apis/changelog
[orders-overview]: https://developers.squarespace.com/commerce-apis/orders-overview
[retrieve-specific-order]: https://developers.squarespace.com/commerce-apis/retrieve-specific-order
[retrieve-spec-trans]: https://developers.squarespace.com/commerce-apis/retrieve-specific-transactions
[inventory-overview]: https://developers.squarespace.com/commerce-apis/inventory-overview
[webhook-subs-overview]: https://developers.squarespace.com/commerce-apis/webhook-subscriptions-overview
[webhook-subs]: https://developers.squarespace.com/commerce-apis/webhooksubscriptions
[rotate-secret]: https://developers.squarespace.com/commerce-apis/rotate-subscription-secret
[webhooks-overview]: https://developers.squarespace.com/webhooks/overview
[verify-notif]: https://developers.squarespace.com/webhooks/verifying-notifications
[notif-delivery]: https://developers.squarespace.com/webhooks/notification-delivery
[order-create]: https://developers.squarespace.com/webhooks/events/order-create
[order-update]: https://developers.squarespace.com/webhooks/events/order-update
[commerce-apis-schemas]: https://commerce-apis.squarespace.com/commerce-apis/~schemas
[rate-limit-rollout]: https://rollout.com/integration-guides/squarespace/api-essentials
[rollout-guide]: https://rollout.com/integration-guides/squarespace/quick-guide-to-implementing-webhooks-in-squarespace
