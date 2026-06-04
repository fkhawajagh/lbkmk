# Xero — Integration Reference

> Document Version: 1.1 | 2026-05-22 (updated 2026-06-04)

## Role in lbkmk

Xero is **the destination** for lbkmk. Unlike the four ingestion channels (Squarespace, Stripe, Square, TicketTailor), Xero plays **no role** in the inbound sale-recording path — it is purely an outbound recipient of itemized transactions (v1: `RECEIVE` BankTransactions per ADR-0001), plus the source of truth for inventory levels and the chart of accounts.

The lbkmk Xero responsibilities, in one picture:

```
                                  ┌─────────────────────────────────────┐
                                  │   approved Sale Event in lbkmk      │
                                  │   (channel: squarespace, stripe,    │
                                  │    square, or tickettailor)         │
                                  └────────────────┬────────────────────┘
                                                   │
                                                   │  POST /api.xro/2.0/BankTransactions
                                                   │  Type=RECEIVE
                                                   │  BankAccount={Stripe|Sqr clearing}
                                                   │  Reference="lbkmk:<sale_event.id>"
                                                   │  Idempotency-Key=<uuid-v4>
                                                   ▼
   ┌───────────── Xero tenant (LBK organisation) ─────────────┐
   │                                                          │
   │   BankTransaction (RECEIVE)  ──────►  Inventory Item     │
   │      ├── LineItem (ItemCode A, Qty)        decrements    │
   │      ├── LineItem (ItemCode B, Qty)        quantity      │
   │      └── LineItem (ItemCode …)             on hand       │
   │                                                          │
   │   Stripe bank-feed deposit  ───►  reconcile against      │
   │   Square bank-feed deposit  ───►  the transfer to Novo   │
   │                                                          │
   │   (Owner transfers net from clearing ──► Novo, then      │
   │    reconciles the bank-feed deposit against the transfer) │
   └──────────────────────────────────────────────────────────┘

                                                   │  schedule: inventory snapshot pull
                                                   ▼
                                  ┌─────────────────────────────────────┐
                                  │   GET /api.xro/2.0/Items            │
                                  │   refresh local Inventory Item      │
                                  │   read-model (stock counts, etc.)   │
                                  └─────────────────────────────────────┘
```

**Why `RECEIVE` BankTransactions instead of `ACCREC` Invoices?** LBK already uses a clearing-account reconciliation flow: itemized sales land in a Stripe/Square clearing account, the owner transfers the net to Novo, and the bank-feed deposit is reconciled against that transfer. Posting `ACCREC` Invoices would create Accounts Receivable that do not fit this flow and risk double-counting against bank rules. `RECEIVE` BankTransactions are sales transactions in Xero's model (alongside `ACCREC` Invoices) and decrement inventory via `ItemCode` the same way, but they land directly in the clearing account. See ADR-0001 for the full decision record.

Per `docs/domain-model.md` §6 rule 5, **Xero is the only writer of inventory counts**: lbkmk never PUTs stock levels, only POSTs transactions that cause Xero to decrement stock as a side-effect. Per rule 12, every Xero call is logged in full (request payload, response payload, status) so the system can always answer "what exactly did we send and what did Xero say".

Communication is **direct** from lbkmk (Phoenix) to Xero. Make.com is **not** in this path. `docs/solution-proposal.md` §"Make scenarios" currently shows a "Xero-write" scenario in Make, but the current direction (per this doc and the `docs/integrations/make.md` boundary) is that the Phoenix app authenticates against Xero itself — this is the only channel where Phoenix holds OAuth credentials directly. The advantage: Xero's idempotency model and refresh-token handling are too stateful to fit Make's stateless-scenario model cleanly, and the security perimeter is simpler with one well-defined OAuth client living in lbkmk.

## Authentication & credentials

Xero uses **OAuth 2.0 Authorization Code flow with PKCE-optional**, against a multi-tenanted identity layer where each connected Xero organisation is a "tenant". The flow is described in [Xero's OAuth2 standard auth-code flow guide][oauth2-auth-flow] and is **not** a server-only / client-credentials flow — there is no "service account" model in Xero. Every connection is bootstrapped by a human user authorising the app against a specific tenant, after which the app holds long-lived refresh tokens.

| Aspect | Value | Source |
|---|---|---|
| Authorization endpoint | `https://login.xero.com/identity/connect/authorize` | [oauth2-auth-flow][oauth2-auth-flow] |
| Token endpoint | `https://identity.xero.com/connect/token` | [oauth2-auth-flow][oauth2-auth-flow] |
| Revocation endpoint | `https://identity.xero.com/connect/revocation` | [oauth2-auth-flow][oauth2-auth-flow] |
| Connections list | `GET https://api.xero.com/connections` | [oauth2-auth-flow][oauth2-auth-flow] |
| API base | `https://api.xero.com/api.xro/2.0/` (Accounting API) | [accounting-overview][accounting-overview] |
| Grant types | `authorization_code` (initial), `refresh_token` (refresh), `client_credentials` (for managing connections only, not for API calls) | [oauth2-auth-flow][oauth2-auth-flow] |
| App registration | Xero Developer Portal → "New App". Yields **Client ID** + **Client Secret**. Standard Auth Code grant type chosen for server-side apps (LBK case) | [oauth2-auth-flow][oauth2-auth-flow] |
| Redirect URI | Must be HTTPS in production. `http://localhost/...` allowed for development, but **not** `http://127.0.0.1/...` | [oauth2-auth-flow][oauth2-auth-flow] |
| `state` parameter | Required to defend against CSRF on the redirect leg; opaque per-user string, validated on return | [oauth2-auth-flow][oauth2-auth-flow] |
| `id_token` (OpenID Connect) | Returned when `openid profile email` scopes are requested. **5-minute** expiry. Not needed if lbkmk doesn't surface "logged-in user identity" anywhere | [oauth2-auth-flow][oauth2-auth-flow] |
| `access_token` lifetime | **30 minutes** (Xero says "1800 seconds"). Bearer JWT, decodable for the `authentication_event_id` (useful for filtering brand-new connections on the `/connections` list) | [oauth2-auth-flow][oauth2-auth-flow] |
| `refresh_token` lifetime | **60 days** from issue; **sliding window** — each refresh produces a new refresh token that resets the 60-day clock. Letting the refresh token expire forces the user to re-authorise interactively | [oauth2-auth-flow][oauth2-auth-flow] |
| Refresh-token rotation | **Single-use**. Each refresh call **invalidates the old refresh token** and returns a new one. Both access and refresh tokens must be saved atomically | [oauth2-auth-flow][oauth2-auth-flow] |
| Refresh grace window | **30 minutes**: if lbkmk's app fails to persist the new refresh token (e.g. crash between Xero returning it and the DB write committing), the **previous** refresh token remains valid for 30 minutes so the call can be retried. After 30 minutes the previous token is dead and the user must re-authorise | [oauth2-auth-flow][oauth2-auth-flow] |
| Webhook signing key | Separate from OAuth — generated per webhook subscription in the Developer Portal. HMAC-SHA256 key, base64-compared against the `x-xero-signature` header on every inbound POST | [webhook-server][webhook-server] |
| Uncertified app connection cap | **Starter tier 5 connections; Core tier 50 connections.** Each Xero organisation is one connection. LBK needs exactly 1 connection (its own organisation), so this is a non-issue at LBK volume | [api-limits][api-limits] |
| Per-org uncertified-app cap | Each Xero organisation can be connected to **a maximum of two uncertified apps**. Certified apps are uncapped. Worth knowing if LBK has other integrations connected to the same Xero tenant | [api-limits][api-limits] |

### Scopes required for lbkmk

Pick the minimum scopes that cover the operations lbkmk performs. From the Xero scopes catalog ([scopes][scopes]):

| Scope | Why lbkmk needs it |
|---|---|
| `offline_access` | **Mandatory** — without this, no `refresh_token` is issued and the integration breaks after 30 minutes |
| `accounting.transactions` | POST/GET on Invoices, Credit Notes, Bank Transactions |
| `accounting.contacts` | Find/create the Contact each transaction is associated with (the customer, or a generic per-channel umbrella Contact like "Squarespace customer") |
| `accounting.settings.read` | List Accounts (chart of accounts), Tracking Categories, Tax Rates — read-only is sufficient |
| `accounting.journals.read` | Optional. Useful for forensic drift-detection (reading the underlying double-entry journals behind a transaction) |
| `openid profile email` | Only if lbkmk's UI shows "connected to Xero as: <name>". Otherwise skip — keeps the consent screen tighter |

Crucially, lbkmk should **not** request `accounting.transactions` write-scope and `accounting.settings` write-scope unless they're actively used — the system never writes to the chart of accounts or to tracking-category definitions; those are owner-administered in the Xero UI.

### Credential storage in lbkmk

Per-tenant secrets (there will be exactly one tenant for LBK in v1):

- `client_id` — env var, public-equivalent
- `client_secret` — env var, server-only secret store
- `tenant_id` — the GUID returned by `GET /connections` for LBK's organisation; persisted in the DB
- `refresh_token` — **persisted in the database**, encrypted at rest, single row per (app, tenant). The cleartext is read at refresh time, the new token is written **transactionally with the access token**, never separately
- `access_token` — cached in process memory or the DB (encrypted), refreshed proactively at ~25 minutes of age (5-minute safety margin before the 30-minute expiry)
- `webhook_signing_key` — env var, server-only secret store (separate from OAuth client_secret)

The Phoenix process should pre-warm the access token on boot and refresh **eagerly** rather than on-demand: a token that expires mid-POST during transaction posting forces a retry and burns the idempotency window. A simple background task that refreshes at `expires_at - 5 minutes` is enough.

## Key concepts / data model

Xero's resource graph relevant to lbkmk:

| Xero resource | lbkmk mapping | Notes |
|---|---|---|
| **Organisation (Tenant)** | One per LBK Xero account | The container for everything. Identified by `tenantId` GUID. Sent as `Xero-tenant-id: <guid>` header on **every** API call. Different Xero plans (Starter, Standard, Premium, Cashbook, etc.) have different feature sets; LBK needs at minimum a plan that supports **tracked inventory** and **multi-currency** — typically Premium. ([accounting-overview][accounting-overview]) |
| **Contact** (`ContactID` GUID) | Customer for each transaction | A BankTransaction must reference a Contact. lbkmk has two reasonable patterns: (a) **per-channel umbrella Contact** — one Contact named e.g. "Squarespace customer", reused for every Squarespace-originated transaction; minimises PII and contact-list bloat; (b) **per-real-customer Contact** — create or find a Contact per email address, so Xero reports show customer-level revenue. Recommendation: start with (a), evaluate (b) later. Avoids GDPR friction and avoids spamming the Xero contacts list with one-off ticket buyers. ([invoices][invoices]) |
| **Invoice** (`InvoiceID` GUID + `InvoiceNumber` string) | The Xero output of one approved Sale Event (alternative to BankTransaction; not used in v1) | `Type=ACCREC` (Accounts Receivable, i.e. "sales invoice"). Carries a `Reference` field — lbkmk uses `lbkmk:<sale_event.id>` here as a **soft idempotency key** that survives even if the Xero `Idempotency-Key` header window has expired. Has its own line items, currency, tax rates, tracking categories. v1 uses `RECEIVE` BankTransactions instead; Invoices remain the fallback if the owner later switches workflows. ([invoices][invoices]) |
| **Invoice Status** | reconciliation-state side-effect (for `ACCREC` Invoices; not used in v1) | Lifecycle: `DRAFT` → `SUBMITTED` → `AUTHORISED` → `PAID` (or `VOIDED` / `DELETED`). For `RECEIVE` BankTransactions, status is not applicable — the transaction is effective immediately. ([invoices][invoices]) |
| **LineItem** (within a BankTransaction) | Mirrors lbkmk's `Line Item` rows | Carries `ItemCode` (the Xero Item's user-defined code — see Inventory Item below), `Description`, `Quantity`, `UnitAmount`, `AccountCode`, `TaxType`, `DiscountRate`, optional `Tracking[]` (up to 2 categories). **If `ItemCode` references a tracked Item, Xero decrements the Item's stock on `RECEIVE` BankTransaction creation.** ([banktransactions][banktransactions]) |
| **Item** (`ItemID` GUID + `Code` string) | `Inventory Item` (canonical sellable thing) | The Xero catalog row. Two flavours: **tracked** (Xero maintains `QuantityOnHand` and `TotalCostPool`; uses Inventory Asset Account; auto-decrements on invoice authorisation) and **untracked** (just a name + default price). LBK's merch and tickets should be **tracked** items where stock matters. `Code` is the user-defined SKU-like identifier (e.g. `TSHIRT-RED-L`, `TICKET-SPRING2026-ADULT`) and lines up directly with `docs/domain-model.md` §4.2 Inventory Item identity. **`QuantityOnHand` and `TotalCostPool` are read-only via the Items endpoint** — they can only change as a side-effect of a sales transaction (ACCREC Invoice / RECEIVE BankTransaction → decrement) or a purchase transaction (ACCPAY Invoice / SPEND BankTransaction → increment). ([items][items], [tracked-inventory][tracked-inventory]) |
| **Account** (`AccountID` GUID + `Code` string, e.g. `200`) | (referenced from each line item) | The chart-of-accounts row each line item posts to. For LBK: a **revenue account** per product category (e.g. `200` = Sales-Merch, `210` = Sales-Tickets), and a **Stripe-fee account** (`410` = Bank Fees-Stripe) for the fee leg of payouts. The `Item` resource carries a default `SalesDetails.AccountCode`, so line items that use `ItemCode` inherit the right account automatically. ([invoices][invoices]) |
| **Tracking Category** + **Tracking Option** | Optional dimension on each line item | Free-form custom dimensions (e.g. Category="Event", Options="Spring Convention 2026" / "Autumn Convention 2026") — lets LBK slice revenue by event without creating a separate Account per event. Up to **2 active tracking categories** per organisation, each with multiple options. Each line item carries up to 2 `Tracking[]` references. Strongly recommended for LBK so per-event revenue reporting works without polluting the Items catalog with date-stamped variants of every SKU. ([invoices][invoices]) |
| **Tax Rate** (`TaxType` enum) | Per-line-item tax handling | UK organisations get tax types like `OUTPUT2` (20% standard-rate VAT), `ZERORATEDOUTPUT`, `EXEMPTOUTPUT`, etc. ([accounting-overview][accounting-overview]). The default for a line item is inherited from the line's `AccountCode`; lbkmk should usually let Xero infer rather than override per-line. |
| **CreditNote** (`CreditNoteID` GUID) | Refund handling | Issued against a previously-posted transaction when LBK refunds a customer. `Type=ACCRECCREDIT`. Decrements inventory **in reverse** (returns stock to the shelf). lbkmk's v1 defers refunds (`docs/domain-model.md` §8), but the credit-note shape is the right abstraction when it lands. For the `RECEIVE` flow, a refund may also be handled by a `SPEND` BankTransaction that returns stock. ([credit-notes][credit-notes]) |
| **BankTransaction** | Stripe / Square bank-feed lines | Created by Xero's bank-feed integration, **not** by lbkmk. Each represents one settled deposit (a Stripe payout, a Square payout, a fee debit). lbkmk treats these as the **counter-party** of the invoices it creates — the `docs/domain-model.md` Drift detection works by summing AUTHORISED+PAID Invoices over a window and comparing to the BankTransaction sum. |
| **Webhook** (subscription) | Optional inbound channel | Xero can push `Contact` and `Invoice` create/update events to lbkmk. Limited coverage (no `Item`, no `BankTransaction`, no `CreditNote` events as of retrieval date) — see Webhooks section. Mostly out of scope for lbkmk v1: lbkmk is the source of truth for the invoices it created, and reconciliation against bank feeds happens via scheduled polling, not push. |

**Identifier conventions:** Xero uses **GUIDs** for primary keys on every resource (`BankTransactionID`, `InvoiceID`, `ContactID`, `ItemID`, `AccountID`, `TrackingCategoryID`, `TenantID`) and **user-defined strings** for the human-facing codes (`Code` on Items, `Code` on Accounts). When persisting Xero IDs on the lbkmk side, store the GUID — names and codes can be edited by the owner in the Xero UI without notice; GUIDs cannot.

**Monetary convention:** Xero uses **decimal strings** (`"1800.00"`, `"225.00"`) **in the transaction's currency** — opposite of Stripe/TicketTailor's minor-unit integers, same shape as Squarespace's decimal-string totals. Normalisation on the lbkmk side: convert internal minor-unit integers to a 2-decimal string at the Xero API boundary, never store decimals internally. Unit prices can opt in to 4-decimal precision by appending `?unitdp=4` to the request URL.

## Webhooks / events

Xero webhooks are **lower-priority** for lbkmk than the channel-side webhooks because Xero is downstream of lbkmk's writes — lbkmk already knows when it created a transaction. But there are two scenarios where they matter:

1. **Out-of-band edits** — if the owner edits a BankTransaction directly in the Xero UI (changes the customer, deletes it, etc.), lbkmk has no other way to learn about the change. A webhook subscription on Invoice updates closes that gap for the `ACCREC` fallback; for `RECEIVE` BankTransactions, polling is the only option.
2. **Detecting payments applied** — if Xero receives a bank-feed deposit and the owner reconciles it manually, the dashboard benefits from showing "reconciled in Xero" status. For the `RECEIVE` flow, this is less relevant because reconciliation happens at the transfer level, not per-transaction.

For v1, lbkmk **may skip Xero webhooks entirely** and rely on scheduled polling (every N minutes, `GET /BankTransactions?If-Modified-Since=<last_sweep>`). Re-evaluate when out-of-band edits become an operational problem.

### Webhook coverage

Xero webhooks are **limited to two resource types** as of retrieval date ([webhook-overview][webhook-overview], [webhook-contacts][webhook-contacts]):

| Resource | Events |
|---|---|
| **Contact** | `CREATE`, `UPDATE` |
| **Invoice** | `CREATE`, `UPDATE` |

There is no webhook coverage for Items, BankTransactions, CreditNotes, Payments, Accounts, or Tracking Categories. Anything in those areas requires polling.

### Envelope structure

A Xero webhook delivery is an `application/json` POST with this body shape ([webhook-overview][webhook-overview], [xero-devblog-webhooks][xero-devblog-webhooks]):

```json
{
  "events": [
    {
      "resourceUrl": "https://api.xero.com/api.xro/2.0/Invoices/<InvoiceID>",
      "resourceId": "<InvoiceID-GUID>",
      "eventDateUtc": "2026-05-22T10:34:12.123",
      "eventType": "CREATE",
      "eventCategory": "INVOICE",
      "tenantId": "<tenantId-GUID>",
      "tenantType": "ORGANISATION"
    }
  ],
  "lastEventSequence": 12,
  "firstEventSequence": 12,
  "entropy": "S0M3R4ND0M..."
}
```

Crucially, the payload does **not** carry the full resource — only an identifier and a URL. To learn what changed, lbkmk must follow up with `GET <resourceUrl>` using the access token for the tenant in question. This is by design (privacy minimisation: the webhook traverses public infrastructure, but the actual data is fetched via an authenticated channel).

### Signing / verification — "Intent to Receive"

Every Xero webhook delivery, including the initial validation check, is signed:

- **Header:** `x-xero-signature: <base64(hmac-sha256(raw_body, webhook_signing_key))>` ([webhook-server][webhook-server], [xero-devblog-webhooks][xero-devblog-webhooks])
- **Algorithm:** HMAC-SHA256, keyed by the per-subscription **webhook signing key** (NOT the OAuth client_secret), over the **raw request body** (bytes as Xero sent them, no JSON re-serialisation)
- **Output encoding:** **base64** (not hex — different from Stripe). Compared against `x-xero-signature` using a constant-time string compare
- **Response requirements** ([xero-devblog-webhooks][xero-devblog-webhooks]):
  1. HTTPS on standard port 443
  2. Respond within **5 seconds** with a **200 OK** status code (for valid signatures)
  3. **Empty body** in the response (no JSON, no text, no whitespace beyond what the HTTP framework strictly requires)
  4. **No cookies** in the response headers
  5. Return **401 Unauthorised** if the signature is invalid
- **Intent to Receive (ITR):** when lbkmk registers a webhook URL in the Developer Portal, Xero immediately POSTs a (possibly empty) test payload with `x-xero-signature` set. lbkmk's endpoint must pass the HMAC check and respond with `200` for valid / `401` for invalid within 5 seconds. **ITR can be re-triggered manually from the Developer Portal** if the first attempt fails

### Retry policy

If lbkmk's endpoint takes longer than 5 seconds, returns a non-2xx, or repeatedly fails signature validation, Xero **disables the webhook subscription**. The exact thresholds aren't published as numbers in the public docs, but third-party guides report Xero will retry briefly then disable ([xero-devblog-webhooks][xero-devblog-webhooks]). Recovery requires re-validating Intent to Receive from the Developer Portal.

**Operational consequence:** lbkmk's webhook handler **must** acknowledge with `200` first, then process asynchronously in a background queue. Doing the `GET /BankTransactions/<id>` follow-up call synchronously inside the 5-second window is dangerous — that GET counts against the per-minute API limit (60 calls/min) and Xero's own latency can blow the budget.

### Idempotency on Xero-side webhooks

Each webhook delivery carries `firstEventSequence` / `lastEventSequence` per `tenantId`. lbkmk should dedupe on `(tenantId, eventDateUtc, resourceId, eventType)`. Public docs are not fully explicit about whether Xero deduplicates retries on its side — assume not, and dedupe defensively.

## API surface we'll use

Base URL: `https://api.xero.com/api.xro/2.0/`. All endpoints require **two** headers:

```
Authorization: Bearer <access_token>
Xero-tenant-id: <tenantId-GUID>
```

Mutation endpoints (POST/PUT/PATCH) also accept an `Idempotency-Key: <client-string>` header (see Idempotency below). Set `Accept: application/json` to get JSON responses (the API defaults to XML on some endpoints — JSON must be explicitly requested).

| Purpose | Endpoint | Notes |
|---|---|---|
| Create an itemized `RECEIVE` BankTransaction | `POST /api.xro/2.0/BankTransactions` with body `{"Type":"RECEIVE", "Contact":{"ContactID":"..."}, "BankAccount":{"Code":"..."}, "Date":"...", "LineAmountTypes":"Exclusive"/"Inclusive"/"NoTax", "LineItems":[...], "Reference":"lbkmk:<sale_event.id>", "CurrencyCode":"GBP"}` and headers `Idempotency-Key: <uuid-v4>`. **lbkmk's primary write.** Per ADR-0001, `RECEIVE` BankTransactions are sales transactions that decrement inventory via `ItemCode` and land directly in the clearing account. ([banktransactions][banktransactions]) |
| Create multiple BankTransactions in one call | `POST /BankTransactions` with body `{"BankTransactions":[ {...}, {...}, ... ]}` (up to ~50 nodes per request per [api-limits][api-limits]) | Each transaction in the batch independently needs its own `Reference`. Useful for backfill, less useful for steady-state ingestion. |
| Get one BankTransaction | `GET /BankTransactions/{BankTransactionID}` | Line items returned. |
| Get many BankTransactions (incremental sync) | `GET /BankTransactions?page=1` with header `If-Modified-Since: <UTC>` | **Paging is recommended**. Up to 100 transactions per page (or `pageSize=250` if needed). ([banktransactions][banktransactions]) |
| Search BankTransactions by Reference | `GET /BankTransactions?where=Reference="lbkmk:<sale_event.id>"` | The lbkmk-side belt-and-braces idempotency check before POSTing: if a transaction already exists with this Reference, do not POST again. Note that `Reference` is in the **optimised filter set** ([banktransactions][banktransactions]) so this query is cheap. |
| Void / reverse a BankTransaction | `POST /BankTransactions/{BankTransactionID}` with body that negates the line items (or delete and recreate). Xero does not have a native "void" for BankTransactions. | Reversing a `RECEIVE` restores inventory. In practice, v1 handles errors by flagging `needs_resolution` and letting the owner adjust in Xero. A proper reversal workflow is v2. |
| List items (inventory catalog) | `GET /Items?page=1` | The scheduled inventory snapshot pull. Returns `Code`, `Name`, `Description`, `IsTrackedAsInventory`, `QuantityOnHand`, `TotalCostPool`, `InventoryAssetAccountCode`, `SalesDetails.{UnitPrice, AccountCode, TaxType}`, `PurchaseDetails`. ([items][items], [tracked-inventory][tracked-inventory]) |
| Find or create a Contact | `GET /Contacts?where=Name="Squarespace customer"` then `POST /Contacts` if not found, with body `{"Name":"...", "EmailAddress":"...", "IsCustomer":true}` | Cache the resulting `ContactID` in lbkmk per channel; one lookup at startup, then reuse. |
| List accounts (chart of accounts) | `GET /Accounts?where=Status="ACTIVE"` | Used at startup to map lbkmk's "revenue account for merch", "revenue account for tickets", "Stripe-fee account" → Xero `AccountCode` strings. Refresh on a long cadence (daily or manual). |
| List tracking categories | `GET /TrackingCategories` | Used at startup. Caches `TrackingCategoryID` and the active `Options[]` so lbkmk can attach `{TrackingCategoryID, Option}` references on each line. |
| Create a credit note (refund) | `POST /CreditNotes` with body `{"Type":"ACCRECCREDIT", "Contact":{...}, "LineItems":[...], "Status":"AUTHORISED", "Reference":"lbkmk-refund:<sale_event.id>"}` | **Deferred to v2** per `docs/domain-model.md` §8. Listed for completeness. For the `RECEIVE` flow, refunds may also be handled by posting a `SPEND` BankTransaction that returns stock. ([credit-notes][credit-notes]) |

### Rate limits

Xero's rate limits are **per-tenant and per-minute**, and they are the **tightest of any integration in the lbkmk system** ([api-limits][api-limits]):

| Scope | Limit | Behaviour |
|---|---|---|
| **Concurrent** | **5 calls in progress at one time** per tenant | Sixth concurrent call returns 429 |
| **Minute** | **60 calls / minute** per tenant | 429 with `Retry-After` header in seconds |
| **Daily** | **1,000 / day** (Starter tier app) or **5,000 / day** (Core tier and above) per tenant | 429 with `Retry-After` header |
| **App-wide minute** | **10,000 calls / minute** across all tenants | Hit only at fleet scale; non-binding for LBK |
| `Retry-After` header | **Provided** on minute and daily 429s. Counts down from the start of the fixed rate-limit window | Pause requests to the tenant for the indicated seconds |
| `X-DayLimit-Remaining`, `X-MinLimit-Remaining`, `X-AppMinLimit-Remaining` | Response headers on **every** API call | Tells lbkmk where the budget is. Pre-emptively back off when any of these drops below ~10 |
| `X-Rate-Limit-Problem` header on 429 | Identifies which limit triggered: `minute`, `day`, `concurrent`, or `appminute` | Use to discriminate transient (minute, concurrent — short backoff) from persistent (day — backoff until midnight UTC) |

**For lbkmk:** steady-state ingestion is well within the limits — even 100 sales/day × 1 POST + 1 polling sweep is < 200 calls/day. The binding constraints are:

- **Initial backfill** — if LBK has months of pre-existing channel sales to post into Xero, batch them in 50-transaction POSTs (which counts as **1 API call**, not 50) and pace at < 60/minute
- **Concurrent cap of 5** — lbkmk should serialise Xero writes per tenant (single GenServer or per-tenant work queue), not parallelise across transactions. The dashboard's inventory-snapshot pull also competes for this budget
- **Daily cap of 5,000** — fine for one tenant. If lbkmk ever serves multiple Xero organisations from the same app installation, each org has its own 5,000/day allowance

### API versioning

Xero's Accounting API is at **v2.0** ([accounting-overview][accounting-overview]), in the URL path: `/api.xro/2.0/...`. Versioning style is **stable-with-additive-changes**:

- Resources rarely receive breaking changes; new fields appear over time
- There is **no per-request version header** like Stripe's `Stripe-Version` — the URL path version is the only dimension
- Other Xero APIs (Bank Feeds, Files, Finance, Payroll) have their own versioning under sibling paths (e.g. `bankfeeds.xro/1.0`) and are out of scope for lbkmk
- The `Accept` header (`application/json` vs `application/xml`) controls response format, not behaviour

For lbkmk: pin `/api.xro/2.0/` and treat new fields as optional. Watch the [Xero changelog][changelog] for any breaking notices.

### Idempotency

Xero added **`Idempotency-Key` header support** in 2023 for **PUT/POST/PATCH on every mutation endpoint**, including `POST /BankTransactions` ([idempotency][idempotency], [xero-openapi-pr][xero-openapi-pr]). The header name is exactly `Idempotency-Key`, the value is a client-generated string. lbkmk should send a fresh **UUID v4** per logical write attempt.

What Xero promises:

- Same key + same payload + same endpoint → returns the cached prior response (no second transaction created)
- Same key + different payload → **400 error** (defence against accidental key reuse with stale data)
- New key → new request, new effect

What the public docs do **not** state precisely (as of retrieval date):

- The retention window for keys (Stripe says ≥24h; Xero's public guide page returned an empty body during this research session — see Gaps below)
- The exact error code returned on key-replay-with-different-payload (community reports say 400 with a structured error message)

**lbkmk's belt-and-braces strategy** combines:

1. **`Idempotency-Key: <uuid-v4>` header** — defends against retry-within-window
2. **`Reference: "lbkmk:<sale_event.id>"`** field on every transaction — survives indefinitely. Before POSTing, lbkmk can `GET /BankTransactions?where=Reference="lbkmk:<sale_event.id>"` to confirm absence. After a 5xx, the same Reference + same UUID can be safely re-tried; if Xero already created the transaction on the prior attempt, the cached response is returned.

This double-layer is the right pattern for lbkmk because the `Idempotency-Key` window is narrow (likely hours) and lbkmk's retry loop can stretch across days if a Xero outage or a long-running maintenance window happens.

## Best practices

1. **One `RECEIVE` BankTransaction per Sale Event.** Don't batch unless backfilling. `RECEIVE` is a sales transaction in Xero's model (alongside `ACCREC` Invoice) and decrements inventory via `ItemCode`. The human approval step has already happened in lbkmk's UI. ([banktransactions][banktransactions])
2. **Put `lbkmk:<sale_event.id>` in the `Reference` field.** This is the durable, human-readable, queryable idempotency layer. Combined with the `Idempotency-Key` header it gives both fast-retry safety (header) and long-term audit safety (field).
3. **Generate a fresh UUID v4 for every `Idempotency-Key` write attempt.** Persist the UUID on the lbkmk Sale Event row before the call goes out, so retries within the Xero key-retention window reuse the same UUID. ([idempotency][idempotency])
4. **Pre-fetch `tenantId`, account codes, tracking-category IDs, item codes, clearing-account codes once at boot** (and on a daily refresh). Caching these prevents per-transaction round-trips to `/Accounts`, `/TrackingCategories`, `/Items` and keeps within the 60/min budget.
5. **Use `ItemCode` on every line item.** This is what activates Xero's automatic inventory decrement. A line item with a free-text `Description` but no `ItemCode` posts revenue correctly but does **not** touch stock counts. ([items][items], [tracked-inventory][tracked-inventory])
6. **Pin the inventory model: `IsTrackedAsInventory: true`** on every Item lbkmk wants to track. Untracked items work for invoicing but won't tell lbkmk "how many Adult Passes are left" — defeating the original requirement. Tickets should be tracked Items, scoped to the event (Adult Pass — Spring 2026 is a different Item from Adult Pass — Autumn 2026). ([tracked-inventory][tracked-inventory], `docs/domain-model.md` §8 ticket-cap open question)
7. **Pin `CurrencyCode` on every transaction.** Default is the tenant's base currency (GBP for LBK). If Stripe accepts a USD or EUR payment, post the Xero transaction in that currency — Xero handles FX conversion to GBP at the posting date's exchange rate.
8. **Serialise writes per tenant.** A simple single-worker pattern (one GenServer or a per-tenant queue) keeps the 5-concurrent cap from becoming a footgun and makes audit-log ordering deterministic.
9. **Refresh the access token eagerly.** Background-task refresh at `expires_at - 5 minutes`. Never let an active request discover an expired token at submit time.
10. **Persist the new `refresh_token` transactionally with the new `access_token`.** A crash between the Xero refresh response and the local DB commit costs you 30 minutes of recovery time before user re-auth becomes necessary. ([oauth2-auth-flow][oauth2-auth-flow])
11. **Verify webhook signatures on the raw body, base64-compared, constant-time.** Skip JSON parsing in middleware on the webhook route. Acknowledge 200 (empty body, no cookies) within 5 seconds; do the `GET <resourceUrl>` follow-up in a background queue. ([webhook-server][webhook-server], [xero-devblog-webhooks][xero-devblog-webhooks])
12. **Log request + response in full.** Per `docs/domain-model.md` §6 rule 12, audit-log every Xero call's full request payload, response body, status code, and timing. Forensic value far exceeds the storage cost.
13. **Treat Items' `QuantityOnHand` as read-only.** Never PUT changes to stock. Stock changes happen only as side-effects of sales transactions (`ACCREC` Invoices or `RECEIVE` BankTransactions) and purchase transactions (`ACCPAY` Invoices or `SPEND` BankTransactions). Inventory adjustments (e.g. stock-take corrections) are out of scope for lbkmk and should be done in the Xero UI by the owner. ([tracked-inventory][tracked-inventory])
14. **Use Tracking Categories for per-event slicing**, not a per-event explosion of Item Codes. One Tracking Category called "Event" with options like "Spring Convention 2026", "Autumn Convention 2026" keeps the catalog manageable and gives the reporting dimension the owner cares about. (Subject to `docs/domain-model.md` §8 confirming the per-event-vs-shared inventory model.)
15. **Set tax handling correctly per market.** LBK is UK-based, so `LineAmountTypes: "Exclusive"` (line amounts ex-VAT) plus per-line `TaxType: "OUTPUT2"` (20% standard) is the common case. Zero-rated and exempt items use their own TaxTypes. Get this wrong and the VAT return is wrong. ([invoices][invoices])

## Anti-patterns / footguns

1. **Posting without `ItemCode` on line items.** Free-text line items with `Description` set but no `ItemCode` post revenue correctly but **do not** touch tracked-inventory stock counts — Xero has no way to know which Item to decrement. ([items][items])

2. **Treating the Xero `Idempotency-Key` window as long-term protection.** The header is the right tool for retry-after-5xx within a short window, but the retention period is not publicly documented. Long retries (e.g. after a Xero maintenance outage that runs hours) may produce duplicate transactions if `Reference`-based dedupe isn't also in place. **Always pre-check `GET /BankTransactions?where=Reference="lbkmk:<sale_event.id>"`** before POSTing on a retry path where the prior attempt's outcome is unknown. ([idempotency][idempotency])

3. **Letting the refresh token expire after 60 days of dormancy.** Refresh tokens are sliding-window — using them resets the 60-day clock. But a system that doesn't refresh between Friday and the following Wednesday for a long weekend × N is fine; one that goes silent for 60 days requires a human user to re-authorise interactively through the browser. Schedule a heartbeat refresh (e.g. weekly) even if no transactions have been posted, to keep the token alive. ([oauth2-auth-flow][oauth2-auth-flow])

4. **Forgetting the `Xero-tenant-id` header.** Every API call needs both `Authorization: Bearer ...` **and** `Xero-tenant-id: <guid>`. Without the tenant id, the access token is valid but ambiguous (the same OAuth session can be connected to multiple Xero organisations) and Xero returns an error. Easy to omit, especially on quickly-written test scripts. ([oauth2-auth-flow][oauth2-auth-flow])

5. **Reusing one webhook signing key across multiple subscriptions.** Each webhook subscription has its own signing key generated in the Developer Portal. Confusing keys across environments (dev vs prod) produces signature failures and Intent-to-Receive failures that look like "Xero is broken" — they aren't; the wrong key is in use. Store `subscription_url → signing_key` explicitly per environment.

6. **Returning a non-empty body or any cookies in the webhook ACK response.** Xero's webhook spec is precise: 200 OK, **empty body, no cookies**. A response of `200 {"ok":true}` from a framework that auto-serialises JSON fails Intent to Receive — Xero will disable the subscription and the failure mode is silent until lbkmk notices missing events. ([xero-devblog-webhooks][xero-devblog-webhooks])

7. **Doing the `GET /BankTransactions/<id>` follow-up call synchronously inside the 5-second webhook window.** That GET counts against the 60/min API budget per tenant, and Xero's own response latency on the GET can be hundreds of milliseconds. Under any load it's a coin-flip to fit; under sustained webhook bursts it fails. Acknowledge first (200, empty body), enqueue the GET in a background worker. ([xero-devblog-webhooks][xero-devblog-webhooks])

8. **Using an account-default `Stripe-Version`-style mental model.** Xero has **no per-request version header**; the version is in the URL path (`/api.xro/2.0/...`). New fields appear over time without a version bump. lbkmk's parsers must tolerate unknown fields (ignore them) rather than reject the response. ([accounting-overview][accounting-overview])

9. **Posting line items without `ItemCode` and expecting inventory to update.** Free-text line items with `Description` set but no `ItemCode` post revenue correctly but **do not** touch tracked-inventory stock counts — Xero has no way to know which Item to decrement. ([items][items])

10. **Writing to `QuantityOnHand` directly via `PUT /Items`.** The field is read-only; the API may return success with no effect, or return an explicit error depending on the wrap. The only way to change stock is via accounting transactions (Invoice for sales-side decrement, ACCPAY Invoice or SPEND BankTransaction for purchase-side increment). ([tracked-inventory][tracked-inventory])

11. **Creating a separate Xero Contact per real-world customer in v1.** This explodes the Contacts list (potentially thousands per year of ticket buyers), pulls PII into Xero unnecessarily, and triggers Xero's contact-list performance warnings at >10,000 contacts ([api-limits][api-limits]). Start with one umbrella Contact per channel ("Squarespace customer", "TicketTailor customer", etc.), revisit if owner needs per-customer reports.

12. **Assuming the existing Stripe / Square bank feeds will auto-match against lbkmk's transactions.** Xero's bank-feed matching algorithm uses contact name + amount + date heuristics ([finlert-stripe-reconcile][finlert-stripe-reconcile]). Bank-feed deposits from Stripe are **gross of fees minus net deposit timing windows** — they do not match 1:1 to a single transaction's gross. With the `RECEIVE` BankTransaction flow, the owner reconciles the bank-feed deposit against the **transfer from clearing to Novo**, not against individual sales. lbkmk makes this possible by ensuring the clearing account has the correct itemized population. The daily reconciliation sweep (kind 4) compares the sum of lbkmk-posted `RECEIVE` transactions against the payout total to flag drift. See ADR-0001 for the full posting strategy.

13. **Posting one Xero transaction per Stripe-charge that double-counts Squarespace sales.** Squarespace's `order.create` and Stripe's `charge.succeeded` for the same customer are **two halves of one transaction** (`docs/domain-model.md` §4.2 Correlation). lbkmk must post **one** Xero BankTransaction per Correlation pair, not two. The current model has the Squarespace Sale Event carry the line items (the goods sold) and Stripe carry the payment side; the Xero transaction mirrors the Squarespace line items, **not** the Stripe gross. Double-posting would double inventory decrements and double revenue — and would not be caught by the bank feed reconciliation because the bank feed is a once-per-day net deposit.

14. **Storing customer billing addresses and email addresses without GDPR review.** A Xero BankTransaction with `Contact.EmailAddress` set puts customer PII into Xero. The umbrella-Contact pattern avoids this. If LBK does want per-customer contacts, ensure Xero's contact retention aligns with LBK's GDPR posture (Xero retains organisation data per its plan terms, which may exceed UK GDPR's "no longer than necessary" expectation unless deletion is actively driven).

15. **Forgetting the 50-node-per-batch practical ceiling.** The 10MB request size limit ([api-limits][api-limits]) translates to ~50 transactions per batch request in practice. Bigger batches trigger timeouts even when they're well under 10MB. Backfill code must page at ~50.

16. **Trusting webhook events as the source of truth about transaction state.** Xero webhooks cover only `CREATE` and `UPDATE` on Contact and Invoice — not `Items`, not `BankTransactions`, not `Payments`, not `CreditNotes`. Any reconciliation logic that needs visibility into stock-on-hand changes **must poll** (`GET /Items`, `GET /BankTransactions`). ([webhook-overview][webhook-overview])

## Open questions for lbkmk

1. ~~**Bank-feed reconciliation: Stripe and Square feeds vs lbkmk-posted transactions.**~~ **Resolved.** Decision: lbkmk posts `RECEIVE` BankTransactions to the owner's existing Stripe/Square clearing accounts. `RECEIVE` is a sales transaction in Xero's model and decrements inventory via `ItemCode`. The owner's existing reconciliation flow (clearing account → transfer to Novo → reconcile transfer) continues unchanged. See ADR-0001 for the full rationale.

2. **Per-customer Contact vs umbrella Contact strategy.** Start with one umbrella Contact per channel (recommended above), but the owner may want per-customer reporting (e.g. "who are our top-spending customers?"). If yes, lbkmk needs a Contact resolution strategy (find by email, create if not found) plus a GDPR-compliant deletion path. **Resolution: ask owner whether per-customer reporting is needed in v1; default to umbrella Contacts if no clear yes.**

3. **Per-event ticket Inventory Items vs shared.** [`docs/domain-model.md` §8 question 3.] Each event's tickets as a distinct tracked Item (clear stock semantics, clear historical reporting) is the design assumption. The alternative — one shared "Adult Pass" item that's reused across events — loses the per-event stock cap unless lbkmk enforces it externally. **Recommendation: per-event Items, with the Item Code suffix carrying the event slug (e.g. `TICKET-SPRING2026-ADULT`).** Confirm with owner before locking in.

4. **Refund flow design.** [`docs/domain-model.md` §8 question 4.] Refunds are deferred to v2, but the Xero shape needs to be sketched so v1 doesn't paint into a corner. For the `RECEIVE` BankTransaction flow, a refund can be handled by posting a `SPEND` BankTransaction with the same `ItemCode` (which increments inventory, reversing the sale). Alternatively, an `ACCRECCREDIT` Credit Note can be issued. **Recommendation: when a refund webhook arrives from Stripe / Square / Squarespace / TicketTailor, raise a "needs_resolution" flag on the lbkmk side; the owner manually adjusts in Xero. Automation lands in v2.**

5. ~~**Xero plan tier — does LBK have tracked inventory and multi-currency enabled?**~~ **Resolved.** Decision: upgrade to the unlimited-invoice tier (Grow or equivalent, ~$42–50/month). Tracked inventory and multi-currency are moot for v1: Items are untracked (per owner confirmation, issue #53) and sales are GBP-only.

6. **Chart of accounts mapping.** Which Account Code does each lbkmk Inventory Item post revenue to? Merch → one account, Tickets → another? Stripe fees → one account, Square fees → another? **Resolution: owner provides the mapping; lbkmk persists it as a configuration table; the `Items` snapshot pull populates the per-Item default account code automatically.**

7. **Tracking Categories — what dimensions does the owner already use?** If LBK already has a tracking category like "Sales Channel" or "Event" set up in Xero, lbkmk should match it. If not, lbkmk should propose creating "Event" as a tracking category. **Resolution: read `GET /TrackingCategories` against LBK's tenant and discuss.**

8. **Idempotency-Key retention window.** Xero's public docs page returned an empty body during research, so the precise retention period is unknown. Stripe is "≥24 hours"; Xero is likely similar. The Reference-based belt-and-braces strategy makes this question non-blocking, but it would be useful to confirm via the Xero developer support channel for the post-incident-replay scenario. **Resolution: test empirically (POST same key twice 25h apart in a sandbox); or open a Xero developer support ticket.**

9. **Webhook subscriptions — Yes or No for v1?** As argued above, lbkmk can skip Xero webhooks in v1 by polling. The cost of polling is ~2 calls/minute (well within the 60/min budget); the cost of webhooks is a more complex deployment surface (HTTPS endpoint, ITR validation, background workers). **Recommendation: skip webhooks in v1; add them only if out-of-band edits in Xero become an operational problem.**

10. **Demo company access for testing.** Xero provides a free "Demo Company" per developer login that resets daily and can be used for integration testing. lbkmk's CI/staging environment should use a Demo Company tenant (separate Client ID + Client Secret from production). **Confirm Demo Company setup at the start of dev work, not later.**

11. **Where do Stripe processing fees live in the Xero books?** The Stripe direct feed brings in fee lines as separate transactions ([stripe-xero-integration][stripe-xero-integration]); lbkmk's `RECEIVE` BankTransaction posts gross revenue to the clearing account, leaving the fee to be expensed when the bank-feed line is reconciled. This matches how the owner already does it — fees are handled by the bank feed, not by lbkmk.

12. **Currency handling for non-GBP sales.** Customer pays in USD via Stripe → Xero needs the transaction in USD with the date-of-posting FX rate ([xero-multi-currency][xero-multi-currency]). Multi-currency requires the Premium plan. **Resolution: confirm LBK's plan and confirm cross-currency volume.**

13. **What happens when the owner manually edits an lbkmk-posted BankTransaction in Xero?** lbkmk has no way to detect this without webhooks. Without webhooks, the owner's edit silently diverges from lbkmk's view. The mitigation is to flag this as a documented "do not edit lbkmk transactions in Xero" convention plus an occasional reconciliation sweep that compares lbkmk's stored transaction payload to a fresh `GET /BankTransactions/<id>`. **Resolution: documented owner convention; v2 webhook-based detection.**

14. **Multi-tenant or single-tenant lbkmk?** Today, lbkmk serves exactly one Xero organisation (LBK). The codebase should still treat `tenantId` as a first-class column on every entity that touches Xero, so adding a second tenant later doesn't require a migration. **Recommendation: design for multi-tenant data shape, ship as single-tenant in v1.**

## Sources

All retrieved 2026-05-22 unless otherwise noted.

Authoritative Xero documentation:

- [OAuth2 standard authorization code flow][oauth2-auth-flow] — `https://developer.xero.com/documentation/guides/oauth2/auth-flow/`
- [OAuth2 scopes][scopes] — `https://developer.xero.com/documentation/guides/oauth2/scopes/`
- [OAuth2 API limits (rate limits)][api-limits] — `https://developer.xero.com/documentation/guides/oauth2/limits/`
- [Accounting API overview][accounting-overview] — `https://developer.xero.com/documentation/api/accounting/overview`
- [Accounting API — Invoices][invoices] — `https://developer.xero.com/documentation/api/accounting/invoices`
- [Accounting API — Bank Transactions][banktransactions] — `https://developer.xero.com/documentation/api/accounting/banktransactions`
- [Accounting API — Items][items] — `https://developer.xero.com/documentation/api/accounting/items`
- [Accounting API — Credit Notes][credit-notes] — `https://developer.xero.com/documentation/api/accounting/creditnotes`
- [Integrating with Xero tracked inventory][tracked-inventory] — `https://developer.xero.com/documentation/guides/how-to-guides/tracked-inventory-in-xero/`
- [Idempotent requests guide][idempotency] — `https://developer.xero.com/documentation/guides/idempotent-requests/idempotency/` (page returned an empty body during research session; confirmed via cross-references in [xero-openapi-pr][xero-openapi-pr] and the SDK reference [xero-python-sdk][xero-python-sdk])
- [Xero API webhooks overview][webhook-overview] — `https://developer.xero.com/documentation/guides/webhooks/overview/`
- [Webhook server configuration][webhook-server] — `https://developer.xero.com/documentation/guides/webhooks/configuring-your-server`
- [Webhooks — Contacts][webhook-contacts] — `https://developer.xero.com/documentation/guides/webhooks/contacts`
- [Xero API changelog][changelog] — `https://developer.xero.com/documentation/changelog`

Community / partner sources (used to confirm behaviour where authoritative pages were thin):

- [Implementing Xero webhooks (Xero devblog)][xero-devblog-webhooks] — `https://devblog.xero.com/keeping-your-integration-in-sync-implementing-xero-webhooks-using-node-express-and-ngrok-6d2976baac6d` — author is Xero staff; reliable for the 5-second / 200 OK / empty body / no cookies / base64 signature shape
- [xero-python SDK reference (Xero Developer Evangelists)][xero-python-sdk] — `https://xeroapi.github.io/xero-python/v1/accounting/index.html` — `Idempotency-Key` parameter on every mutation endpoint confirms header name
- [xero-node Issue #649 (Xero staff response)][xero-node-issue-649] — `https://github.com/XeroAPI/xero-node/issues/649` — confirms `Idempotency-Key` as the header name, generated-from-OpenAPI-spec, fixed in xero-node 4.36.1 and 5.0.0
- [Xero-OpenAPI PR #581][xero-openapi-pr] — `https://github.com/XeroAPI/Xero-OpenAPI/pull/581` — confirms idempotency_key as the canonical OpenAPI parameter across all Xero SDKs
- [Reconciling Stripe bank feed in Xero (Finlert)][finlert-stripe-reconcile] — `https://help.finlert.com/subsync/reconciling-your-stripe-bank-feed-in-xero` — third-party guide describing the Stripe-feed-vs-lbkmk-Invoice reconciliation footgun in detail; treated as a hint, not authoritative
- [Stripe-Xero integration overview (FinTask)][stripe-xero-integration] — `https://fintask.ie/blog/stripe-xero-integration` — describes the Stripe direct feed + "Pay Now" patterns; treated as a hint, not authoritative
- [Square Xero integration app listing (Xero App Store UK)][square-xero-app] — `https://apps.xero.com/uk/collection/xero-square-integration/app/square` — confirms Square-to-Xero data flow includes Invoices, Contacts, Bank Transactions, Bank Transfers
- [Xero multi-currency accounting (Xero UK)][xero-multi-currency] — `https://www.xero.com/uk/accounting-software/use-multiple-currencies/` — confirms multi-currency support and 160+ currencies

[oauth2-auth-flow]: https://developer.xero.com/documentation/guides/oauth2/auth-flow/
[scopes]: https://developer.xero.com/documentation/guides/oauth2/scopes/
[api-limits]: https://developer.xero.com/documentation/guides/oauth2/limits/
[accounting-overview]: https://developer.xero.com/documentation/api/accounting/overview
[invoices]: https://developer.xero.com/documentation/api/accounting/invoices
[banktransactions]: https://developer.xero.com/documentation/api/accounting/banktransactions
[items]: https://developer.xero.com/documentation/api/accounting/items
[credit-notes]: https://developer.xero.com/documentation/api/accounting/creditnotes
[tracked-inventory]: https://developer.xero.com/documentation/guides/how-to-guides/tracked-inventory-in-xero/
[idempotency]: https://developer.xero.com/documentation/guides/idempotent-requests/idempotency/
[webhook-overview]: https://developer.xero.com/documentation/guides/webhooks/overview/
[webhook-server]: https://developer.xero.com/documentation/guides/webhooks/configuring-your-server
[webhook-contacts]: https://developer.xero.com/documentation/guides/webhooks/contacts
[changelog]: https://developer.xero.com/documentation/changelog
[xero-devblog-webhooks]: https://devblog.xero.com/keeping-your-integration-in-sync-implementing-xero-webhooks-using-node-express-and-ngrok-6d2976baac6d
[xero-python-sdk]: https://xeroapi.github.io/xero-python/v1/accounting/index.html
[xero-node-issue-649]: https://github.com/XeroAPI/xero-node/issues/649
[xero-openapi-pr]: https://github.com/XeroAPI/Xero-OpenAPI/pull/581
[finlert-stripe-reconcile]: https://help.finlert.com/subsync/reconciling-your-stripe-bank-feed-in-xero
[stripe-xero-integration]: https://fintask.ie/blog/stripe-xero-integration
[square-xero-app]: https://apps.xero.com/uk/collection/xero-square-integration/app/square
[xero-multi-currency]: https://www.xero.com/uk/accounting-software/use-multiple-currencies/
