# Make.com — Integration Reference

> Document Version: 1.0 | 2026-05-22

## Role in lbkmk

Make.com (formerly Integromat) is the **integration spine** for lbkmk. Every external webhook — Squarespace, Stripe, Square, TicketTailor — is delivered to a Make scenario first, transformed into a normalized shape, and forwarded to the lbkmk Phoenix application via Make's HTTP module. Per `docs/domain-model.md` §6 rule 14, the lbkmk app never talks to the upstream sales channels directly; per rule 15, Make holds no business state — it is a stateless transformer between the channels and lbkmk.

Data flow:

```
   Squarespace ─┐
   Stripe ─────┼──> Make scenario (Custom Webhook trigger) ──> Make HTTP module ──> lbkmk
   Square ─────┤            │                                                          │
   TicketTailor ┘            ▼                                                          ▼
                  (queue, retry, error                                       (idempotency
                   handlers, IP allowlist)                                    on channel + external_event_id;
                                                                              signature verification)
```

One Make scenario per channel × event is the simplest topology. Each scenario has:

- **Custom Webhook** trigger (the channel's POST endpoint, fronted by Make's hook URL).
- An optional verification / transform stage to canonicalize the payload shape.
- **HTTP module** POSTing to `https://lbkmk.example.com/webhooks/<channel>`.
- **Error handlers** (Break for transient HTTP failures; Resume for explicit ignore).

## Authentication & credentials

| Aspect | Value | Source |
|---|---|---|
| Hook URL format | `https://hook.<zone>.make.com/<32-char-id>` (zones: `eu1`, `eu2`, `us1`, `us2`, plus the Celonis zones `eu1.make.celonis.com`, `us1.make.celonis.com`) | [gateway-app][gateway-app], [hooks-api][hooks-api] |
| Transport | HTTPS only | [webhooks-help][webhooks-help] |
| Inbound auth options on Make's Custom Webhook | (1) **API key authentication** via reserved header `x-make-apikey` — multiple keys per webhook, ASCII only, ≤512 chars, write-once (Make does not redisplay the value after creation); (2) **IP restrictions** — comma-delimited allowlist, CIDR supported; (3) **Data structure validation** — incoming requests that fail schema validation are rejected with HTTP 400 | [gateway-app][gateway-app] |
| Built-in HMAC signature verification | **None.** Make has no first-class "verify HMAC SHA-256 with secret X" option on the Custom Webhook trigger. Signature verification must be done either (a) inside the Make scenario by recomputing the HMAC in a Tools module and comparing in a filter, or (b) downstream in lbkmk after Make forwards the raw body + signing headers | [codehooks-webhook-sec][codehooks-webhook-sec], [community-sig][community-sig] |
| Outbound auth (Make → lbkmk) | Configured per HTTP module: No Auth, **API Key authentication** (keychain), **Basic Auth** (keychain), or **OAuth 2.0** (connection). Keychains and connections are stored encrypted at rest by Make and not visible after creation | [http-app][http-app], [basic-conn][basic-conn] |
| Where to store the lbkmk-side shared secret | Two options: (a) a Make **Keychain** of type API Key or Basic Auth, referenced from the HTTP module's Advanced Settings → Proxy / Auth; (b) a **Custom Variable** (Pro plan and up) injected into the module at runtime. Both are encrypted at rest. **Do not** paste the secret directly into the HTTP module's headers field — that value lives in the scenario blueprint and is exposed by scenario sharing and JSON export | [credentials-cli][credentials-cli], [thinkpeak-keys][thinkpeak-keys] |
| Egress IPs (Make → lbkmk) | Three IPs per zone, rotated across all Make customers in the zone. Examples (verify against your zone on the help center): `us1` = `54.209.79.175`, `54.80.47.193`, `54.161.178.114`; `eu1` = `54.75.157.176`, `54.78.149.203`, `52.18.144.195` | [ip-mirror][ip-mirror] |
| Ingress IPs (channel → Make) | **Dynamic** — Make does not publish a static list. Allowlisting Make's ingress side from the channel is not feasible | [ip-mirror][ip-mirror] |

For lbkmk: store the lbkmk-side shared secret as a Make **Connection / Keychain**, reference it from the HTTP module. Do not paste secrets into URL query strings (URLs surface in execution logs and history). On the inbound side, set both an `x-make-apikey` header (cheap per-request filter at Make's edge) **and** a server-side HMAC signature check inside lbkmk over the channel's original raw body — Make does not natively verify channel signatures, so lbkmk is the trust boundary.

## Key concepts / data model

The objects an lbkmk operator needs to reason about:

| Concept | Definition | Notes |
|---|---|---|
| **Scenario** | A configured workflow: trigger → modules → output. Owns a schedule (instant for webhook triggers; interval-based for polling) and a status (active / inactive) | [webhooks-help][webhooks-help] |
| **Module** | A single step inside a scenario. Each module execution = **1 operation / credit**, with a few exceptions (routers / filters are free; AI modules and the Make Code module cost more) | [pricing-stacksheriff][pricing-stacksheriff], [pricing-make][pricing-make] |
| **Bundle** | A single record flowing between modules. One webhook delivery = at least one bundle; iterator modules fan out one bundle into many | [scenario-settings][scenario-settings] |
| **Operation / Credit** | The billing unit. Make renamed "operations" → "credits" in August 2025; for standard modules 1 credit = 1 module execution. AI modules and Make Code consume credits at higher dynamic rates | [pricing-stacksheriff][pricing-stacksheriff] |
| **Connection** | A stored credential (OAuth tokens, API keys, basic auth) for a specific external service. Connections are encrypted at rest, referenced by ID from modules. Created once, reusable across scenarios | [conn-api][conn-api], [credentials-cli][credentials-cli] |
| **Keychain** | A credential record used by the HTTP module's auth modes (API Key, Basic Auth) and proxy configuration. Same encryption / lifecycle as Connections; surfaced separately in the UI | [http-app][http-app] |
| **Data store** | A persistent key-value table inside Make, scoped to a team. Used to hold processing state across executions (e.g. idempotency ledgers, dedupe keys) — Make's pragmatic equivalent of a small operational DB | [reliabilitylayer-retry][reliabilitylayer-retry] |
| **Custom Variable** | A reusable named value scoped to a scenario, team, or organization. Encrypted at rest, injected at runtime, not visible in scenario JSON export. **Pro tier and up.** | [thinkpeak-keys][thinkpeak-keys], [pricing-make][pricing-make] |
| **Webhook queue** | A per-webhook FIFO buffer that holds inbound requests until the scenario processes them. Bounded by subscription size (see below) | [webhooks-help][webhooks-help] |
| **Execution** | One run of a scenario. Has a unique ID, a status (`success`, `error`, `incomplete`), and a duration. Capped at 40 seconds per module and 40 minutes per execution | [automatelab-timeout][automatelab-timeout], [community-timeout][community-timeout] |
| **Incomplete execution / DLQ** | A failed run whose state has been preserved (rather than rolled back). Lives in the scenario's Incomplete Executions folder; counts against the subscription's storage allowance | [scenario-settings][scenario-settings], [incomplete-api][incomplete-api] |
| **Error handler** | A branch attached to a module that runs when that module errors. Five types: **Resume** (skip error, supply replacement value, continue), **Break** (stop run, store incomplete, optionally auto-retry), **Commit** (finish run as success up to this point), **Rollback** (revert transactional modules), **Ignore** (suppress error, do not continue downstream) | [error-handlers][error-handlers], [quick-eh-ref][quick-eh-ref] |
| **Zone** | Geographic Make region (`us1`, `us2`, `eu1`, `eu2`). Determines hook URL, egress IPs, and data residency. Cannot be changed after team creation | [hooks-api][hooks-api] |

## Webhooks / events

This section answers critical questions 1, 5, 6, 7, 8 from the brief.

### Custom Webhook trigger — what Make's "Webhook (Instant)" actually does

The **Custom Webhook** module (`Webhooks > Custom webhook`) is Make's primary inbound receiver. Generated URL format: `https://hook.<zone>.make.com/<32-char-id>` ([gateway-app][gateway-app]).

Behavior when a request arrives ([webhooks-help][webhooks-help]):

1. The request body is parsed according to `Content-Type`: `application/json`, `application/x-www-form-urlencoded`, or `multipart/form-data`. Query string parameters are merged into the bundle alongside the body.
2. Make stores the request (timestamp, URL, method, headers, query, body) in the **webhook's queue**.
3. The scenario picks it up — **immediately if the scenario is set to "Immediately as data arrives"** (the default for webhook-triggered scenarios), **or batched** if the scenario is on an interval schedule.
4. The default HTTP response is **`200 Accepted`** with body `Accepted` — returned as soon as the request lands in the queue, before any module runs. **The default response timeout is 180 seconds**; if no `Webhook response` module replies inside that window, Make falls back to `200 Accepted` ([gateway-app][gateway-app]).
5. If the queue is full, Make returns **`400 Bad Request`** with body `Queue is full` ([gateway-app][gateway-app]).

### Critical question 1 — sync, queued, retries

**Make does NOT retry inbound webhook deliveries.** Make is the *receiver*; the retry contract is owned by the *sender* (e.g. TicketTailor retries for 72 hours, Stripe retries for ~3 days, etc.). If Make's webhook endpoint returns 4xx/5xx or times out, the channel's retry policy applies — and Make returning anything other than `200 Accepted` will trigger a retry from a well-behaved sender.

Default behavior is **sync-acknowledge, async-process**: Make answers `200 Accepted` immediately, queues the bundle, and the scenario runs against the queue. There is no end-to-end synchronous guarantee — the channel sees a 200 the moment the request hits Make's queue, not when lbkmk has processed it.

### Critical question 5 — payload size limit

**Hard limit: 5 MB (5,242,880 bytes) on the Content-Length of an incoming webhook**, regardless of plan tier ([gateway-app][gateway-app], [community-payload][community-payload]). Cannot be raised on any plan, including Enterprise. For mailhooks (the email-trigger variant) the cap is 25 MB ([gateway-app][gateway-app]). Outbound HTTP module payloads are bounded by the per-plan **data transfer** allowance (5 GB per 10k credits on paid plans — see Pricing below) rather than a per-request byte cap, but individual file modules expose a separate max-file-size that ranges from 5 MB on Free to 1,000 MB on Enterprise ([stackscored][stackscored]).

For lbkmk: TicketTailor and Stripe payloads for typical LBK volumes are well under 5 MB. The risk surface is **group ticket orders** (TicketTailor's `issued_tickets[]` array can grow with quantity — see `docs/integrations/tickettailor.md` open questions §Q7) and Stripe events with deeply nested expanded objects. If 5 MB is in play, Make is not the right path — the channel must POST a reference and lbkmk must pull the full payload itself, mediated through a separate Make scenario.

### Critical question 6 — idempotency / dedupe

**Make does not natively dedupe identical webhook bodies.** Two POSTs to the same hook URL with identical bodies arriving 1 ms apart will both queue and both fire the scenario. Dedupe is purely lbkmk's responsibility ([reliabilitylayer-retry][reliabilitylayer-retry], [reliabilitylayer-dedupe][reliabilitylayer-dedupe]).

The lbkmk side already keys ingestion on `(channel, external_event_id)` per `docs/domain-model.md` §6 rule 16 — that uniqueness constraint is the actual dedupe boundary. Optionally, Make scenarios can layer a **Data Store** ledger in front of the HTTP-out module to short-circuit duplicate forwards, but this only optimizes operation cost (skips a Make → lbkmk POST that lbkmk would reject as a duplicate anyway). The authoritative dedupe must remain on the lbkmk side.

### Critical question 7 — secret storage

Three places lbkmk's shared secret with Make *could* live, ranked best to worst:

1. **Connection / Keychain** (recommended) — encrypted at rest, referenced by ID from the HTTP module, not visible in scenario JSON export, survives scenario sharing without leaking ([credentials-cli][credentials-cli], [conn-api][conn-api]).
2. **Custom Variable** at team or organization scope (Pro tier and up) — same encryption story, more flexible if the same secret is reused across many scenarios ([thinkpeak-keys][thinkpeak-keys]).
3. **Inline in the HTTP module's headers field** (**avoid**) — the value is part of the scenario blueprint, surfaces in JSON export, in scenario sharing, and in any error report.

For lbkmk: **use a Keychain.** It works on every plan, has the right encryption story, and survives scenario sharing.

### Critical question 8 — scenario versioning during edits

Make tracks **scenario history** automatically; previous versions can be restored via *three-dot menu → Previous Versions → pick a version → OK* ([previous-versions][previous-versions], [scenario-history][scenario-history]). Restored versions are **not auto-saved** — they appear as a candidate in the editor and require manual save.

The behavior of in-flight executions during an edit is not crisply documented:

- Saving a new version while an execution is mid-flight: the in-flight execution continues to run against the version it started with (Make snapshots the blueprint at execution start). New incoming webhook requests after save use the new version.
- Toggling a scenario inactive does **not** drain the queue; queued items wait. Toggling back to active resumes processing — the same community workaround surfaces in [webhook-queues-stuck][webhook-queues-stuck].
- There is no formal "draft vs published" mode for normal scenarios. The currently saved blueprint *is* the live one. Make's UI displays a "modified — unsaved changes" indicator while you edit.

For lbkmk: **edits to webhook-receiving scenarios are inherently risky.** Treat each scenario as a deployment unit. Test edits in a separate copy of the scenario pointed at a dev lbkmk endpoint before applying to the production scenario. The clone-edit-swap pattern is the closest Make-native equivalent to blue/green deployment.

### Inbound payload — raw body forwarding to lbkmk

**Make does not preserve the original raw body bytes verbatim once it has parsed the request.** Once the Custom Webhook module receives JSON, Make parses it into a structured bundle. To re-serialize it back into bytes when POSTing onward to lbkmk:

- Enable **JSON pass-through** on the Custom Webhook settings ([gateway-app][gateway-app]). This makes the original JSON available as a single text string under `1.body` rather than as parsed fields, which preserves byte-for-byte fidelity for downstream HMAC recomputation.
- Enable **Get request headers** to expose all inbound headers (including `Tickettailor-Webhook-Signature`, `Stripe-Signature`, `X-Square-Signature`, etc.) under `1.headers` ([gateway-app][gateway-app], [community-headers][community-headers]).
- In the HTTP module, set **Body type: Raw → text/plain** (or the appropriate `Content-Type`) and map the body field to `{{1.body}}`. Map the signature header into a custom header on the outbound request.

This is the right pattern for lbkmk: Make is a dumb pipe, and lbkmk verifies signatures over bytes that match what the channel signed. Without `JSON pass-through`, Make may reorder JSON keys or normalize whitespace, and the channel's HMAC will fail verification on the lbkmk side ([dev-step-by-step][dev-step-by-step], [codehooks-webhook-sec][codehooks-webhook-sec]).

### Queue limits and 5-day deactivation

| Limit | Value | Source |
|---|---|---|
| Per-webhook queue depth | **667 items per 10,000 monthly credits**, capped at **10,000 items** maximum | [webhooks-help][webhooks-help], [community-payload][community-payload] |
| Behavior when queue full | Make returns HTTP `400 Queue is full` and **rejects** the request (no buffer-of-the-buffer) | [gateway-app][gateway-app] |
| Inbound rate ceiling | **300 requests per 10-second window**, per Make (account-level, not per-webhook). 429 returned beyond this | [webhooks-help][webhooks-help] |
| Auto-disable threshold | Make **automatically deactivates webhooks not connected to any scenario for more than 5 days (120 hours)**. The hook returns `410 Gone` after deactivation | [webhooks-help][webhooks-help] |
| Webhook log retention | **3 days standard, 30 days on Enterprise.** Older logs are deleted | [webhooks-help][webhooks-help] |

For lbkmk: a Core/Pro plan at 10,000 credits/month gives a 667-item queue per webhook. At ~200 orders/month aggregated across all four channels, headroom is enormous in steady state, but a 6-hour Make outage during a busy weekend could fill the queue — monitor `queueCount` via Make's `/hooks` API endpoint ([hooks-api][hooks-api]) and alert at >50% capacity.

## API surface we'll use

The Make → lbkmk call is the HTTP module's `Make a request` action.

### HTTP module behavior — critical question 2

| Aspect | Value | Source |
|---|---|---|
| Max timeout per request | **300 seconds** (configurable, default 40s) | [http-app][http-app] |
| Behavior on 4xx/5xx | If `Return error if HTTP request fails` is **enabled** (default), the module raises an error and the run becomes incomplete or routes to the attached error handler. If disabled, the response is treated as a regular bundle and the scenario continues | [http-app][http-app] |
| Built-in retry on 5xx | **None.** Make does NOT auto-retry HTTP module failures unless a `Break` error handler is attached. With `Break` configured, the failed bundle is stored in the Incomplete Executions queue and **auto-retried up to N times at a configurable interval** | [break-eh][break-eh], [community-retry-break][community-retry-break] |
| Built-in retry on 4xx | Same as 5xx — none by default. `Break` handler treats any error class the same unless filtered | [break-eh][break-eh] |
| Built-in retry on timeout | Same — none unless `Break` handler attached. A 40-second module timeout (or whatever value is configured up to 300s) followed by no error handler = incomplete execution | [automatelab-timeout][automatelab-timeout] |
| Redirects | Follows up to **10** redirects by default. Behavior per status code documented per RFC | [http-app][http-app] |
| TLS | TLS or mutual TLS; client certs via keychain. Self-signed certs are rejected on file-download URLs ([http-app][http-app]) | [http-app][http-app] |
| Body modes | `application/json`, `application/x-www-form-urlencoded`, `multipart/form-data`, `text` (raw string), `binary` | [making-requests][making-requests] |
| Headers / custom headers | Fully configurable; supports mapping bundle data into header values | [http-app][http-app] |
| Cookie sharing | Optional per-module toggle (`Share cookies with other HTTP modules`) | [http-app][http-app] |
| Per-execution time cap | **40 minutes hard limit on the whole scenario run.** Independent of the 40-second per-module cap | [automatelab-timeout][automatelab-timeout], [community-45min][community-45min] |

For lbkmk: the right pattern is **HTTP module + Break error handler with auto-retry on transient errors**. lbkmk responds quickly (target sub-second on the `/webhooks/<channel>` endpoint — just enqueue and return 200), Make POSTs with a 30-60 second timeout, and the Break handler catches transient 5xx / timeouts and re-queues. lbkmk's idempotency on `(channel, external_event_id)` absorbs any duplicate replays from this retry path.

**Important:** Break retries run from the **Incomplete Executions queue as separate executions** — they do not consume time inside the original run's 40-minute budget ([automatelab-timeout][automatelab-timeout]). Sleep-based inline retries (Resume + Sleep + cloned HTTP) DO consume the 40-minute budget. For lbkmk, Break is the correct choice.

### Error handling — critical question 3

**`Allow storing of incomplete executions`** is the master switch ([scenario-settings][scenario-settings]):

- **Enabled:** when a module errors and no error handler catches it, the failed run is paused and moved to the Incomplete Executions folder. Operators can fix the issue and resume from the failed module. Storage counts against the plan's storage allowance.
- **Disabled:** the run stops and enters the rollback phase. Transactional modules revert; non-transactional side effects are not undone. **The data is lost.**

The five error handlers ([error-handlers][error-handlers], [quick-eh-ref][quick-eh-ref], [nguyenthanhluan-eh][nguyenthanhluan-eh]):

| Handler | What it does | When to use for lbkmk |
|---|---|---|
| **Resume** | Continue with a substitute value provided in the handler | When the failure is non-critical (e.g. an enrichment lookup) and lbkmk can ingest without it |
| **Break** | Stop the run, store it as incomplete, optionally auto-retry on a schedule | **The default for lbkmk's Make → lbkmk POST.** Pairs naturally with channel-side retry policies. |
| **Commit** | Commit transactional changes up to the failure point, then stop | Rarely useful in lbkmk's case — Make has nothing transactional to commit |
| **Rollback** | Revert all transactional changes and stop | Same — no Make-side transactions in lbkmk's scenarios |
| **Ignore** | Suppress the error, downstream modules do not run | When the failure should be silently logged but not block the scenario — e.g. a non-critical logging module errors out |

**Default-without-handler behavior:** if `Allow storing of incomplete executions` is enabled, Make treats `RateLimitError` and `ConnectionError` automatically as warnings and stores the bundle; other error classes interrupt and either store (with storage enabled) or rollback (without). Custom handlers cover any error class without extra billing — error-handler-route modules **do not consume operations** ([nguyenthanhluan-eh][nguyenthanhluan-eh]).

The scenario setting `Number of consecutive errors` (default 3) deactivates the scenario after N consecutive failed runs — **except for scenarios with instant triggers (webhooks), where the scenario is deactivated immediately after the first error** ([scenario-settings][scenario-settings]). This is a significant footgun — see Anti-patterns.

The `Sequential processing` setting ([scenario-settings][scenario-settings]) is also important: by default, Make processes webhook requests **in parallel**. If sequential processing is enabled, Make waits for the previous execution to finish before starting the next one. **lbkmk should leave this OFF** — sequential processing on a busy webhook can stall the queue if any single delivery is slow, and lbkmk's `(channel, external_event_id)` idempotency makes parallel processing safe.

### Suggested HTTP module config for the Make → lbkmk POST

| Setting | Value | Why |
|---|---|---|
| URL | `https://lbkmk.example.com/webhooks/<channel>` | Stable per-channel endpoint |
| Method | `POST` | — |
| Body type | `Raw → text/plain` (with `Content-Type: application/json` header) | Forward bytes verbatim so lbkmk can HMAC-verify the channel's signature |
| Body | `{{1.body}}` (with JSON pass-through enabled on the webhook) | Preserves the original JSON byte-for-byte |
| Headers | `Authorization: Bearer {{vars.lbkmkSecret}}` (from a Keychain or Custom Variable), plus the channel's original signature header (e.g. `Tickettailor-Webhook-Signature: {{1.headers.'Tickettailor-Webhook-Signature'}}`) | Two-layer auth: cheap Make-side bearer + channel HMAC verified in lbkmk |
| Timeout | 30-60 seconds | Well below the 300s ceiling; lbkmk should ack inside a second |
| Return error if HTTP request fails | **Yes** | We want failures to route to the error handler, not be silently treated as a successful bundle |
| Error handler | **Break**, retry every 5 minutes, max 5 attempts | Async retry without consuming scenario time |

## Best practices

1. **One scenario per channel.** Four channels → four scenarios. Keeps blast radius small: editing the Squarespace scenario can't break the Stripe one.
2. **JSON pass-through + Get request headers on every Custom Webhook receiver.** This is the only way to forward bytes that pass HMAC verification on the lbkmk side ([gateway-app][gateway-app]).
3. **Always return `200 Accepted` fast.** Make does this by default. Do not place heavy modules before the `Webhook response` module — Make replies before the rest of the scenario runs, but the channel's view of "delivered" is "Make returned 2xx", not "lbkmk processed it" ([webhooks-help][webhooks-help]).
4. **Use Break error handlers on the outbound HTTP module** with auto-retry; size the retry budget so it overlaps the channel's retry budget (TicketTailor 72h, Stripe ~3 days). Break-retries run from the Incomplete Executions queue as new executions, so they don't eat the original run's 40-minute budget ([automatelab-timeout][automatelab-timeout]).
5. **Enable `Allow storing of incomplete executions`** on every production scenario. Without it, every failure that isn't caught by an error handler is data loss.
6. **Disable `Sequential processing`** for webhook-triggered scenarios. lbkmk's `(channel, external_event_id)` idempotency makes parallel processing safe, and sequential processing causes head-of-line blocking on the queue ([scenario-settings][scenario-settings]).
7. **Store secrets as Keychains, not inline.** Inline secrets leak via scenario sharing and JSON export ([thinkpeak-keys][thinkpeak-keys]).
8. **Pin the lbkmk callback URL via DNS, not direct IP.** Make's egress IPs in a zone rotate across all customers; lbkmk should accept from any source IP but require the bearer + HMAC.
9. **Monitor queue depth.** Use `GET /hooks` on the Make API ([hooks-api][hooks-api]) to fetch `queueCount` per hook; alert at >50% of the queue limit. The default is 667 items per 10k credits, so the alert threshold on a 10k-credit plan is ~333 items.
10. **Test edits in a clone.** Make has no native staging — clone the scenario, point at a dev lbkmk endpoint, validate, then either swap URLs on the original or delete the original and rename the clone.
11. **Enable IP restrictions on the Custom Webhook** when the channel publishes static egress IPs (Stripe does; Squarespace and TicketTailor do not). Reduces the attack surface even before HMAC checks ([gateway-app][gateway-app]).
12. **Set a Data Structure on the Custom Webhook** ([gateway-app][gateway-app]) — Make will reject malformed payloads with HTTP 400 before they enter the queue, saving operations and surfacing schema regressions in the channel.

## Anti-patterns / footguns

1. **Webhooks not connected to any scenario auto-deactivate after 5 days and return `410 Gone`** ([webhooks-help][webhooks-help]). If a scenario is deleted or detached from its webhook for any reason, the channel will see 410 within 5 days and may auto-disable its end (TicketTailor disables at day 10 of continuous failure — see `docs/integrations/tickettailor.md` Anti-pattern §3). Audit periodically: `GET /hooks` returns each hook's `enabled`, `gone`, and `scenarioId` ([hooks-api][hooks-api]).

2. **Instant-trigger scenarios deactivate on the FIRST error, not after `Number of consecutive errors`** ([scenario-settings][scenario-settings]). A single transient failure can take a webhook-fed scenario down — exactly the scenario where downtime is most expensive. **Mitigation: always attach a Break or Resume error handler to every module in a webhook-triggered scenario, so the module-level error never propagates to the scenario level.**

3. **Make does not natively verify channel signatures.** There is no "verify HMAC SHA-256 with secret X" checkbox on Custom Webhook ([codehooks-webhook-sec][codehooks-webhook-sec]). Doing the verification inside a Make scenario via a Tools module is fragile (key handling, timing attacks, JSON normalization) and shifts the trust boundary off lbkmk. Push verification to lbkmk over the forwarded raw body.

4. **Make's egress IPs are shared across all customers in the zone.** Three IPs per zone, rotating ([ip-mirror][ip-mirror], [quotaguard][quotaguard]). lbkmk cannot meaningfully IP-allowlist Make on the inbound side — the same IPs are used by every other Make customer. Bearer + HMAC is the authentication contract.

5. **`Allow storing of incomplete executions` consumes storage that counts against the plan limit.** A flood of failures can fill the bucket; further failures may be lost depending on `Enable data loss` setting ([scenario-settings][scenario-settings]). Set a retention policy and clear processed incompletes regularly via the `/dlqs` API ([incomplete-api][incomplete-api]).

6. **Webhook queue overflow returns HTTP 400 to the channel, not 429 or 503.** A 400 looks like a malformed-request error to the sender, not a retry-later signal. Some channels may not retry on 400 (Stripe will, TicketTailor "treats it as failed immediately on HTTP redirect" but is unclear on 400 — see `docs/integrations/tickettailor.md` §webhook-retry). Treat queue saturation as an outage event ([gateway-app][gateway-app]).

7. **The 40-minute scenario hard limit is not configurable, even on Enterprise.** A scenario that legitimately needs more time has to be split into multiple chained scenarios connected via webhooks or data stores ([community-45min][community-45min]). For lbkmk this is irrelevant per ingestion event, but a bulk backfill scenario must be designed around the limit.

8. **There is no built-in "deduplication" on the Make Custom Webhook.** Two identical POSTs both fire ([reliabilitylayer-dedupe][reliabilitylayer-dedupe]). lbkmk's `(channel, external_event_id)` constraint is the only dedupe boundary; do not assume Make absorbs duplicates.

9. **Scenario edits have no formal "draft" / "publish" model.** Save = live ([previous-versions][previous-versions]). Editing a webhook-triggered scenario in place during business hours is functionally a production change with no rollback unless you remember to use `Previous Versions` (which is also not auto-saved on restore).

10. **Custom Variables require Pro plan and up** ([pricing-make][pricing-make]). On Core, the only secret-storage option is a Keychain or Connection. This is fine for lbkmk's secret needs but worth knowing if the team considers Make features that assume Custom Variables exist.

11. **The `x-make-apikey` header value is write-once.** Make does not redisplay the key after creation ([gateway-app][gateway-app]). Lose it and you re-issue.

12. **Scenario sharing leaks blueprint, including inline secrets.** Anyone with the share link gets the JSON of the scenario, including any value pasted into a module's field ([consultevo-sharing][consultevo-sharing]). Use Keychains / Custom Variables for anything sensitive.

13. **Make ingress IPs (channel → Make) are dynamic.** The channel cannot allowlist a stable inbound IP for Make's hook URL. Channels that require allowlisting their outbound destination (rare for webhooks; more common for API callbacks) will need a static-IP proxy in front of Make — third-party services like QuotaGuard sell this, but it adds a hop and a vendor ([ip-mirror][ip-mirror], [quotaguard][quotaguard]).

## Operations & data transfer billing

Critical question 4. **At LBK's stated volume (low hundreds of orders/month), the Core plan at $9/month annual (10,000 credits) is more than sufficient.** Math below.

### Plan tiers as of 2026-05-22

| Plan | Price (annual) | Price (monthly) | Credits/mo | Active scenarios | Min interval | Data transfer |
|---|---|---|---|---|---|---|
| **Free** | $0 | $0 | 1,000 | 2 max | 15 minutes | 512 MB / mo (some sources cite 100 MB — likely outdated) |
| **Core** | $9/mo | ~$10.59/mo | 10,000 | Unlimited | 1 minute | 5 GB per 10k credits |
| **Pro** | $16/mo | ~$18.82/mo | 10,000 | Unlimited | 1 minute (with priority execution) | 5 GB per 10k credits |
| **Teams** | $29/mo | ~$34.12/mo | 10,000 | Unlimited | 1 minute (with priority execution) | 5 GB per 10k credits |
| **Enterprise** | Custom | Custom | Custom | Unlimited | Custom | Custom + overage protection |

Source: [pricing-make][pricing-make], [pricing-stacksheriff][pricing-stacksheriff], [pricing-flowbuilder][pricing-flowbuilder], [stackscored][stackscored].

### What counts as an operation

**1 credit = 1 module execution**, with these wrinkles ([pricing-stacksheriff][pricing-stacksheriff]):

- Routers and filters: **free** (no credit consumed).
- Modules on the error-handling route: **free** ([nguyenthanhluan-eh][nguyenthanhluan-eh]).
- The Custom Webhook trigger itself: 1 credit per fired webhook.
- HTTP module: 1 credit per request.
- AI modules and Make Code: variable, often 5-50+ credits depending on token / runtime.

### lbkmk's expected monthly credit burn

Assume ~300 orders/month total across all four channels (high estimate for LBK). Each ingestion is roughly:

- 1 credit: Custom Webhook trigger fires
- 1 credit: Optional Tools/Set Variable for any per-channel normalization
- 1 credit: HTTP module POSTs to lbkmk

→ **~3 credits per ingested event × 300 events = 900 credits/month**. Even with a 3-5× overhead for retries on transient failures, this lands comfortably under the **10,000-credit Core plan** at $9/month annual.

### Cost cliffs

The Core → Pro jump ($9 → $16) is feature-driven, not credit-driven (same 10k credits). The reason to upgrade ([pricing-flowbuilder][pricing-flowbuilder]):

- **Priority scenario execution.** On Core, executions can queue during peak hours; on Pro, they run ahead of Core/Free. For lbkmk's webhook-triggered scenarios, Core's queueing risk is real — if lbkmk's `/webhooks/<channel>` endpoint is sensitive to lag (e.g. owner is watching a live event and expects sales to surface in the dashboard within seconds), Pro is the safer tier.
- **Full-text execution log search.** Essential for forensics. Worth the upgrade once lbkmk is in production.
- **Custom Variables.** Slightly nicer secret-handling than Keychains.

Above 300,000 credits/month, Core is no longer offered — upgrade to Pro is required ([stackrev-pricing][stackrev-pricing]). lbkmk will not approach this.

**Overage protection** is Enterprise-only ([pricing-make][pricing-make]). On Core/Pro/Teams, exceeding the credit allowance pauses scenarios until either (a) extra credits are purchased at 25% markup, or (b) the next month's allowance resets ([pricing-stacksheriff][pricing-stacksheriff]). For lbkmk this is a real outage risk — set an alert at 80% credit consumption.

### Data transfer

5 GB per 10k credits on paid plans ([pricing-make][pricing-make]). lbkmk webhook payloads are KB-scale; data transfer is not a binding constraint.

## Open questions for lbkmk

These items are unresolved by the public docs and warrant either an empirical test against a Make test scenario, a support ticket to Make, or an owner conversation:

1. **What does Make's API return for `queueCount` granularity?** The OpenAPI shows `queueCount` and `queueLimit` as integers ([hooks-api][hooks-api]) but the update frequency / staleness is undocumented. Real-time monitoring vs. periodic poll matters for the alerting threshold.

2. **What is Make's behavior when an inbound POST exceeds 5 MB?** Returns `413 Payload Too Large`? `400`? Silent truncation? Empirically test — the answer changes whether lbkmk needs to handle a "did Make swallow the payload?" branch.

3. **Does the Break handler retry-budget accumulate across scenario runs, or reset per execution?** Documentation says "the failed bundle is stored and retried later"; community sources say retry attempts are per-bundle ([community-retry-break][community-retry-break]) but exact semantics on a fresh delivery of the *same* upstream event are unclear. Matters for the question "if Make Break-retries a forward to lbkmk 5 times, then TicketTailor re-delivers the original webhook, does Make's queue have 1 item or 6?"

4. **Is there a documented service-level commitment from Make?** SLAs are Enterprise-only ([pricing-make][pricing-make]). On Core/Pro/Teams the operational availability is "best effort." For lbkmk this matters because the integration spine is single-vendor — a 4-hour Make outage during a busy weekend is unrecoverable for that window.

5. **Does Make's egress connection support HTTP/2 or only HTTP/1.1?** Not documented. May matter for lbkmk's Phoenix endpoint behavior if Phoenix Cowboy is configured with HTTP/2 expectations.

6. **What is Make's behavior on TLS handshake failures from lbkmk?** Specifically, does it count as a `ConnectionError` (auto-retried with delay) or a `RuntimeError` (no retry)? The error-type taxonomy ([error-handling-dev][error-handling-dev]) implies the former, but worth empirical confirmation.

7. **Can the Custom Webhook's data structure validation enforce signature header presence?** The data structure is documented for body shape ([gateway-app][gateway-app]); whether it can validate headers is unclear. If yes, that's a cheap edge filter for malformed/unsigned requests.

8. **What is the actual storage cap for incomplete executions on each plan?** "Counts against the storage limits of your subscription plan" ([scenario-settings][scenario-settings]) is vague. Concrete numbers (GB? count?) require checking the live pricing page or contacting support.

## Sources

All retrieved 2026-05-22.

Authoritative Make documentation:

- [webhooks-help][webhooks-help] — `https://help.make.com/webhooks` (overview, queue mechanics, 300 req / 10s, 5-day auto-disable, log retention)
- [gateway-app][gateway-app] — `https://apps.make.com/gateway` (Custom Webhook module: 5 MB payload cap, JSON pass-through, Get request headers, IP restrictions, data structure validation, default response timeout 180s)
- [http-app][http-app] — `https://apps.make.com/http` (HTTP module: 300s timeout, redirect handling, auth modes, TLS)
- [scenario-settings][scenario-settings] — `https://www.make.com/en/help/scenarios/scenario-settings` (Allow storing of incomplete executions, Sequential processing, Number of consecutive errors, instant-trigger deactivation on first error, Auto-commit, max number of cycles)
- [error-handlers][error-handlers] — `https://help.make.com/error-handlers`
- [quick-eh-ref][quick-eh-ref] — `https://help.make.com/quick-error-handling-reference`
- [break-eh][break-eh] — `https://help.make.com/break-error-handler`
- [previous-versions][previous-versions] — `https://www.make.com/en/help/scenarios/how-to-restore-a-previous-scenario-version`
- [scenario-history][scenario-history] — `https://help.make.com/scenario-history`
- [pricing-make][pricing-make] — `https://www.make.com/en/pricing` (plan tiers, credits, data transfer ratio)
- [ip-mirror][ip-mirror] — `https://docs.axelor.com/connect-help-center/docs/HTML/en/connections/allowing-connections-to-and-from---make---ip-addresses.html` (mirror of Make's egress IP list per zone; dynamic ingress IPs)

Make developer documentation:

- [hooks-api][hooks-api] — `https://developers.make.com/api-documentation/api-reference/hooks` (zones, `queueCount`, `queueLimit`, `enabled`, `gone`, `scenarioId`)
- [incomplete-api][incomplete-api] — `https://developers.make.com/api-documentation/api-reference/incomplete-executions` (DLQ retry / delete endpoints)
- [conn-api][conn-api] — `https://developers.make.com/api-documentation/api-reference/connections` (Connection lifecycle, encryption)
- [basic-conn][basic-conn] — `https://developers.make.com/custom-apps-documentation/app-components/connections/basic-connection` (auth modes, common data encryption)
- [credentials-cli][credentials-cli] — `https://developers.make.com/make-cli/make-cli/make-cli-reference/credentials` (keys, connections, credential-requests via CLI)
- [making-requests][making-requests] — `https://developers.make.com/custom-apps-documentation/component-blocks/api/making-requests` (body types, request structure, 40s module timeout note)
- [error-handling-dev][error-handling-dev] — `https://developers.make.com/custom-apps-documentation/app-components/base/error-handling` (error types: RuntimeError, DataError, RateLimitError, ConnectionError, etc.)
- [instant-trigger-dev][instant-trigger-dev] — `https://developers.make.com/custom-apps-documentation/app-components/modules/instant-trigger`
- [webhooks-dev][webhooks-dev] — `https://developers.make.com/custom-apps-documentation/app-components/webhooks` (respond directive, verification, body/headers/query/method IML variables)

Make community (used to confirm authoritative claims; treated as hints not answers):

- [community-payload][community-payload] — `https://community.make.com/t/webhook-and-its-limitations/42357` (5 MB cap, queue 667/10k credits, 10k max, 5-day auto-disable)
- [community-timeout][community-timeout] — `https://community.make.com/t/elevenlabs-module-times-out-when-api-doesnt-way-to-fix/19312/3` (HTTP module 300s max, generic modules 40s)
- [community-headers][community-headers] — `https://community.make.com/t/how-to-capture-request-headers-in-an-instant-trigger-webhook/28373`
- [community-sig][community-sig] — `https://community.make.com/t/custom-webhook-message-content-and-signature/4070`
- [community-retry-break][community-retry-break] — `https://community.make.com/t/break-auto-retry-attempts-how-do-they-work/35554`
- [community-45min][community-45min] — `https://community.make.com/t/scenario-timeout-after-45-minutes/37187` (40-minute hard scenario limit)
- [webhook-queues-stuck][webhook-queues-stuck] — `https://community.make.com/t/webhook-queues-not-getting-automatically-processed/57479`

Third-party analysis (used only to corroborate authoritative claims):

- [pricing-stacksheriff][pricing-stacksheriff] — `https://stacksheriff.com/automation/make-com-pricing/` (credit model, 25% markup on overages, August 2025 ops→credits rename)
- [pricing-flowbuilder][pricing-flowbuilder] — `https://www.flowbuilderhq.com/make-com-pricing-2026/` (Core vs Pro differentiation, priority execution)
- [stackrev-pricing][stackrev-pricing] — `https://www.stackrev.net/en/automation-tools/make-pricing` (300k-credit ceiling on Core)
- [stackscored][stackscored] — `https://www.stackscored.com/pricing/workflow-automation/make/` (file size limits per plan)
- [automatelab-timeout][automatelab-timeout] — `https://automatelab.tech/make-http-module-40s-timeout/` (40s module timeout, 40-minute scenario limit, Break vs inline-Sleep retry semantics)
- [nguyenthanhluan-eh][nguyenthanhluan-eh] — `https://nguyenthanhluan.com/en/glossary/overview-of-error-handling-en/` (error-route modules don't consume operations; default RateLimitError + ConnectionError handling)
- [reliabilitylayer-retry][reliabilitylayer-retry] — `https://reliabilitylayer.com/blog/make-com-retry-logic-duplicate-safe`
- [reliabilitylayer-dedupe][reliabilitylayer-dedupe] — `https://reliabilitylayer.com/blog/make-com-duplicate-prevention-guide` (Make has no native webhook dedupe; Data Store pattern)
- [codehooks-webhook-sec][codehooks-webhook-sec] — `https://codehooks.io/blog/secure-zapier-make-n8n-webhooks-signature-verification` (Make has no built-in HMAC verification)
- [dev-step-by-step][dev-step-by-step] — `https://dev.to/137foundry/step-by-step-webhook-signature-verification-for-any-sender-2nje` (raw-body byte fidelity needed for HMAC)
- [quotaguard][quotaguard] — `https://www.quotaguard.com/docs/automation/make-integration/` (Make egress IPs are shared across customers, rotating in pools of 3 per zone)
- [thinkpeak-keys][thinkpeak-keys] — `https://thinkpeak.ai/make-com-api-key-management/` (Custom Variables for secret handling, Pro tier requirement)
- [consultevo-sharing][consultevo-sharing] — `https://consultevo.com/make-com-share-scenarios-guide/` (scenario sharing leaks blueprint contents)

[webhooks-help]: https://help.make.com/webhooks
[gateway-app]: https://apps.make.com/gateway
[http-app]: https://apps.make.com/http
[scenario-settings]: https://www.make.com/en/help/scenarios/scenario-settings
[error-handlers]: https://help.make.com/error-handlers
[quick-eh-ref]: https://help.make.com/quick-error-handling-reference
[break-eh]: https://help.make.com/break-error-handler
[previous-versions]: https://www.make.com/en/help/scenarios/how-to-restore-a-previous-scenario-version
[scenario-history]: https://help.make.com/scenario-history
[pricing-make]: https://www.make.com/en/pricing
[ip-mirror]: https://docs.axelor.com/connect-help-center/docs/HTML/en/connections/allowing-connections-to-and-from---make---ip-addresses.html
[hooks-api]: https://developers.make.com/api-documentation/api-reference/hooks
[incomplete-api]: https://developers.make.com/api-documentation/api-reference/incomplete-executions
[conn-api]: https://developers.make.com/api-documentation/api-reference/connections
[basic-conn]: https://developers.make.com/custom-apps-documentation/app-components/connections/basic-connection
[credentials-cli]: https://developers.make.com/make-cli/make-cli/make-cli-reference/credentials
[making-requests]: https://developers.make.com/custom-apps-documentation/component-blocks/api/making-requests
[error-handling-dev]: https://developers.make.com/custom-apps-documentation/app-components/base/error-handling
[instant-trigger-dev]: https://developers.make.com/custom-apps-documentation/app-components/modules/instant-trigger
[webhooks-dev]: https://developers.make.com/custom-apps-documentation/app-components/webhooks
[community-payload]: https://community.make.com/t/webhook-and-its-limitations/42357
[community-timeout]: https://community.make.com/t/elevenlabs-module-times-out-when-api-doesnt-way-to-fix/19312/3
[community-headers]: https://community.make.com/t/how-to-capture-request-headers-in-an-instant-trigger-webhook/28373
[community-sig]: https://community.make.com/t/custom-webhook-message-content-and-signature/4070
[community-retry-break]: https://community.make.com/t/break-auto-retry-attempts-how-do-they-work/35554
[community-45min]: https://community.make.com/t/scenario-timeout-after-45-minutes/37187
[webhook-queues-stuck]: https://community.make.com/t/webhook-queues-not-getting-automatically-processed/57479
[pricing-stacksheriff]: https://stacksheriff.com/automation/make-com-pricing/
[pricing-flowbuilder]: https://www.flowbuilderhq.com/make-com-pricing-2026/
[stackrev-pricing]: https://www.stackrev.net/en/automation-tools/make-pricing
[stackscored]: https://www.stackscored.com/pricing/workflow-automation/make/
[automatelab-timeout]: https://automatelab.tech/make-http-module-40s-timeout/
[nguyenthanhluan-eh]: https://nguyenthanhluan.com/en/glossary/overview-of-error-handling-en/
[reliabilitylayer-retry]: https://reliabilitylayer.com/blog/make-com-retry-logic-duplicate-safe
[reliabilitylayer-dedupe]: https://reliabilitylayer.com/blog/make-com-duplicate-prevention-guide
[codehooks-webhook-sec]: https://codehooks.io/blog/secure-zapier-make-n8n-webhooks-signature-verification
[dev-step-by-step]: https://dev.to/137foundry/step-by-step-webhook-signature-verification-for-any-sender-2nje
[quotaguard]: https://www.quotaguard.com/docs/automation/make-integration/
[thinkpeak-keys]: https://thinkpeak.ai/make-com-api-key-management/
[consultevo-sharing]: https://consultevo.com/make-com-share-scenarios-guide/
