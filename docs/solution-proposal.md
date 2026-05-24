---
title: Little Big Kids — Solution Proposal
audience: Owner review (technical)
status: Draft v0.1
date: 2026-05-21
depends_on: docs/domain-model.md
---

> **Document Version: 0.1** | 2026-05-21
>
> Draft for owner review. This document proposes **how** the system described in `docs/domain-model.md` will be built. The vocabulary used here assumes the domain model has been read first.

## 1. Executive overview

### The problem

LBK sells across four channels (Squarespace, Stripe, Square, TicketTailor) and accounts in Xero. Xero today receives net daily bank deposits from Stripe and Square, with no itemized detail. Result: LBK cannot answer item-level revenue questions, cannot reconcile what was actually sold against what was deposited, and cannot reliably track inventory across channels.

### The proposed solution

A small system with two halves:

- **Make.com** as the integration backbone — its strength is having pre-built connectors for every system in scope (Squarespace, Stripe, Square, TicketTailor, Xero). It handles all external API access.
- **A custom Phoenix LiveView dashboard** (this repo) as the reconciliation cockpit — where the owner reviews each sale, approves it, and posts an itemized invoice to Xero.

Every sale, from every channel, lands in the dashboard. The owner reviews and approves. The system posts a properly itemized invoice to Xero, which automatically decrements tracked inventory and posts revenue with per-item granularity. Existing Xero bank feeds continue to bring in payouts; the dashboard helps confirm those payouts reconcile against the approved invoices.

### Why this split

Make's strength is integration breadth (every connector pre-built); its weakness is holding state and orchestrating workflows. Phoenix LiveView's strength is reactive UIs and state management; its weakness would be reimplementing connectors LBK doesn't need to own. Combining them plays to each's strengths.

### What ships in v1, and what doesn't

**Ships:** end-to-end flow from channel sale → owner review → itemized Xero invoice → tracked inventory decrement. All four channels supported. Approval workflow with audit trail. SKU mapping admin. Read-only inventory view.

**Defers:** automated refunds, multi-user roles, mobile UI, multi-org Xero, analytics dashboards (Xero already has those), bidirectional sync from Xero back to channels.

## 2. High-level architecture

```mermaid
flowchart LR
    subgraph Sources["Channels & Processors"]
        SQS[Squarespace]
        STR[Stripe]
        SQR[Square]
        TT[TicketTailor]
    end

    subgraph Make["Make.com (stateless integration)"]
        SCN1[Source ingress scenarios]
        SCN2[Cross-channel matcher]
        SCN3[Xero write scenario]
        SCN4[Inventory snapshot scenario]
        SCN5[Daily reconciliation sweep]
    end

    subgraph Phoenix["Phoenix LiveView (this repo)"]
        API["REST API /api/v1"]
        CTX["Contexts:<br/>Ingest · Reconciliation ·<br/>Inventory · Audit"]
        LV[LiveView UI]
        DB["(Postgres)"]
    end

    Xero["(Xero<br/>accounting + inventory)"]
    Owner((Owner))

    Sources -- webhooks / polling --> SCN1
    SCN1 -- "POST /sale-events" --> API
    SCN2 <-- "GET unmatched / POST correlations" --> API
    Xero -- "tracked items + payouts" --> SCN4
    SCN4 -- "POST inventory-snapshot" --> API
    Sources -- "missed-event recovery" --> SCN5
    SCN5 -- "POST sale-events / payouts" --> API
    API --> CTX
    CTX <--> DB
    CTX --> LV
    Owner -- "browser" --> LV
    LV -- "approve action" --> CTX
    CTX -- "POST action: post_xero_invoice" --> SCN3
    SCN3 --> Xero
    SCN3 -- "POST xero-write-result" --> API
```

**Key boundaries:**

- **The dashboard never reaches outside its own DB and Make.** No direct calls to Squarespace, Stripe, Square, TicketTailor, or Xero from Phoenix.
- **Make holds no business state.** Scenarios are stateless transformers + HTTP relays. Re-running a scenario produces no harmful side effects.
- **The owner only interacts with the LiveView UI.** They do not touch Make's web UI for day-to-day operations; that's where the system was built, not where it is run.

## 3. Component view

### Make scenarios (5 types)

| # | Scenario | Trigger | Job |
|---|---|---|---|
| 1 | **Source-ingress** (one per channel: Squarespace, Stripe, Square, TicketTailor) | Webhook (preferred) or schedule | Receive raw event, normalize to canonical shape, POST to Phoenix `/api/v1/sale-events`. |
| 2 | **Cross-channel matcher** | Schedule (~15 min) | Pull unmatched sale events from Phoenix; for each, look up the paired payment event in the source (e.g. fetch the Stripe charge matching a TT order's metadata); POST correlations back. |
| 3 | **Xero-write** | HTTP webhook (Phoenix calls it on approval) | Build a Xero invoice payload from the approved Sale Event, post to Xero, send result (invoice id or failure) back to Phoenix. |
| 4 | **Inventory-snapshot** | Schedule (~hourly) | Pull all tracked items from Xero, POST a full snapshot to Phoenix. |
| 5 | **Reconciliation sweep** | Schedule (daily) | Pull Stripe/Square payouts from Xero's bank feed view; pull recent events from each source as a safety net for missed webhooks; POST any gaps to Phoenix. |

### Phoenix contexts

| Context | Responsibility | Key modules |
|---|---|---|
| **`Ingest`** | Accept normalized events from Make, dedupe, persist, route to lifecycle. | `Ingest.upsert_event/1`, `Ingest.resolve_lines/1` |
| **`Reconciliation`** | Match payment-to-sale events (catalog kind 1, §6), check line totals (kind 2), apply state transitions, run the matching ladder. Hosts the daily payout sweep job (kind 4). | `Reconciliation.try_correlate/1`, `Reconciliation.approve/2`, `Reconciliation.reject/2`, `Reconciliation.sweep_payouts/0` |
| **`Inventory`** | Mirror Xero tracked items, expose stock snapshots. | `Inventory.snapshot_from_xero/1`, `Inventory.item_by_xero_code/1` |
| **`Audit`** | Append-only logging, forensic queries. | `Audit.record/3`, `Audit.timeline_for/1` |
| **`Channels`** | Channel SKU mapping admin: register unmapped SKUs, link to items, retire. | `Channels.upsert_sku/1`, `Channels.map_to_item/2` |
| **`XeroWrites`** | Outbound action dispatcher to Make's webhook + result handler. | `XeroWrites.dispatch/1`, `XeroWrites.handle_result/1` |
| **`Dashboard`** | LiveView modules. | `DashboardLive.Inbox`, `DashboardLive.EventDetail`, `DashboardLive.Skus`, `DashboardLive.Inventory` |

## 4. Key interaction flows

### Flow 1 — Sale ingestion from a single-channel sale (Squarespace)

```mermaid
sequenceDiagram
    autonumber
    actor Customer
    participant Squarespace
    participant Stripe
    participant Make as Make scenario (Squarespace ingress)
    participant Phoenix as Phoenix /api/v1
    participant DB as Postgres
    participant UI as LiveView (owner)

    Customer->>Squarespace: place order, pay
    Squarespace->>Stripe: create charge
    Stripe-->>Squarespace: charge succeeded
    Squarespace->>Make: order.created webhook
    Make->>Make: normalize to canonical shape<br/>(extract line items + SKUs)
    Make->>Phoenix: POST /sale-events (channel=squarespace)
    Phoenix->>DB: upsert sale_event (idempotent on external id)
    Phoenix->>DB: resolve lines via channel_skus
    Phoenix-->>Make: 201 + sale_event id

    Note over Stripe,Make: Separately, Stripe charge.succeeded<br/>webhook fires the Stripe ingress scenario
    Stripe->>Make: charge.succeeded webhook
    Make->>Phoenix: POST /sale-events (channel=stripe, metadata=squarespace_order_id)
    Phoenix->>DB: upsert, trigger correlation attempt
    Phoenix->>Phoenix: id_match strategy succeeds<br/>(charge.metadata.order_id == squarespace event id)
    Phoenix->>DB: insert correlation (high confidence)

    Phoenix->>UI: PubSub broadcast: new event ready
    UI-->>UI: inbox row appears in real time
```

### Flow 2 — Cross-channel correlation (TicketTailor + Stripe, fuzzy match)

```mermaid
sequenceDiagram
    autonumber
    actor Attendee
    participant TT as TicketTailor
    participant Stripe
    participant Make as Make scenarios
    participant Phoenix
    participant Matcher as Make matcher (scheduled)
    participant UI as LiveView

    Attendee->>TT: buy 2× Adult Pass
    TT->>Stripe: create charge $70
    Stripe-->>TT: charge succeeded
    TT-)Make: order.completed (TT ingress)
    Stripe-)Make: charge.succeeded (Stripe ingress)

    Make->>Phoenix: POST /sale-events × 2<br/>(TT event + Stripe event)
    Phoenix->>Phoenix: TT event: resolve lines<br/>(may require enrichment — see §5)
    Phoenix->>Phoenix: try_correlate(TT event):<br/>id_match fails (no Stripe id on TT side)<br/>metadata_match fails (no order_id on Stripe charge)<br/>amount_time_window: $70 ± 0¢, 60s window → match!
    Phoenix->>Phoenix: confidence: medium → route to needs_resolution<br/>reason: "fuzzy match — please confirm"

    Note over Matcher,Phoenix: 15 min later, scheduled matcher also runs
    Matcher->>Phoenix: GET /sale-events?state=needs_resolution&reason=fuzzy_match
    Matcher->>Stripe: lookup charge by id (re-check metadata)
    Stripe-->>Matcher: charge details (still no order_id)
    Matcher->>Phoenix: no new info, correlation unchanged

    UI-->>UI: owner sees event in needs_resolution<br/>with the proposed Stripe match
    actor Owner
    Owner->>UI: review, click "confirm match"
    UI->>Phoenix: confirm correlation
    Phoenix->>Phoenix: state → pending (ready to approve)
```

### Flow 3 — Owner approval → Xero post

```mermaid
sequenceDiagram
    autonumber
    actor Owner
    participant UI as LiveView (Event Detail)
    participant Phoenix
    participant DB as Postgres
    participant Make as Xero-write scenario
    participant Xero

    Owner->>UI: click "Approve & Post"
    UI->>Phoenix: approve(sale_event_id, user_id)
    Phoenix->>DB: state pending → approved<br/>(transactional with audit_log insert)
    Phoenix-->>UI: optimistic update: "posting…"
    Phoenix->>Make: POST webhook<br/>{action: "post_xero_invoice", payload}

    Make->>Make: build Xero invoice payload<br/>(line items, customer, account codes,<br/>Reference: "lbkmk:<sale_event.id>")
    Make->>Xero: check for existing invoice<br/>by Reference (idempotency)
    Xero-->>Make: not found
    Make->>Xero: POST /Invoices (status=AUTHORISED)
    Xero->>Xero: decrement tracked inventory<br/>post revenue to accounts
    Xero-->>Make: invoice created<br/>(InvoiceID, InvoiceNumber)

    Make->>Phoenix: POST /xero-write-result<br/>{sale_event_id, xero_invoice_id, status: success}
    Phoenix->>DB: state approved → posting → posted<br/>insert xero_writes row<br/>(transactional with audit_log)
    Phoenix->>UI: PubSub broadcast: posted
    UI-->>Owner: badge flips to "posted ✓"
```

### Flow 4 — Daily reconciliation sweep (catalog kind 4 — see §6)

```mermaid
sequenceDiagram
    autonumber
    participant Cron as Make schedule (daily 2am)
    participant Make as Sweep scenario
    participant Sources as Squarespace · Stripe · Square · TicketTailor
    participant Xero
    participant Phoenix
    participant UI as Payouts LiveView

    Cron->>Make: trigger sweep
    par Source pull (missed-event recovery)
        Make->>Sources: list events since yesterday's cursor
        Sources-->>Make: events[]
        Make->>Phoenix: POST /sale-events for any not already known<br/>(idempotent — already-known events return 200 no-op)
    and Payout pull
        Make->>Xero: list Stripe + Square bank transactions<br/>since yesterday
        Xero-->>Make: payouts[]
        Make->>Phoenix: POST /payouts
    end

    Phoenix->>Phoenix: match payouts to approved invoices<br/>(by date range + processor + total ± tolerance)
    Phoenix->>Phoenix: flag drift where sums don't reconcile

    UI-->>UI: payouts view updates with<br/>per-payout reconciled / drift status
```

## 5. Decision points

The non-trivial business decisions the system makes, made explicit.

### 5.1 SKU resolution at ingestion

```mermaid
flowchart TD
    A[Sale event arrives with line items] --> B{"For each line item:<br/>is channel_sku known?"}
    B -->|"Yes, mapped to item"| C{Item active in Xero?}
    B -->|"No, unknown external id"| D["Create channel_sku<br/>in 'unmapped' state"]
    B -->|"Yes, but unmapped"| D
    D --> E["Mark sale_event as<br/>needs_resolution<br/>reason: 'unmapped SKU'"]
    E --> Z((park for owner action))
    C -->|Yes| F{All lines resolved?}
    C -->|"No, retired/deleted"| E
    F -->|Yes| G[Continue to correlation]
    F -->|No| E
    G --> Z2((next decision: correlation))
```

### 5.2 Correlation strategy ladder

```mermaid
flowchart TD
    Start[Sale event needs correlation] --> S1{"id_match:<br/>does payment event ID appear<br/>explicitly on this event?"}
    S1 -->|Yes| H1["Correlate · confidence=high · strategy=id_match"]
    S1 -->|No| S2{"metadata_match:<br/>does any payment event<br/>reference this event's external ID?"}
    S2 -->|Yes| H2["Correlate · confidence=high · strategy=metadata_match"]
    S2 -->|No| S3{"amount_time_window:<br/>exactly one payment event<br/>with same gross ±0¢<br/>within ±60s, both unmatched?"}
    S3 -->|Yes| M1["Correlate · confidence=medium · strategy=amount_time_window"]
    S3 -->|No| NM[No correlation found]
    H1 --> R1{"event is Squarespace<br/>or TicketTailor?"}
    H2 --> R1
    R1 -->|Yes| AP[continue to approval readiness]
    R1 -->|No| AP
    M1 --> NR1["needs_resolution<br/>reason: 'fuzzy match — confirm'"]
    NM --> AGE{"event > 30 min old<br/>without correlation?"}
    AGE -->|Yes| NR2["needs_resolution<br/>reason: 'no payment side'"]
    AGE -->|No| WAIT[stay pending — re-try on next matcher run]
```

### 5.3 Approval readiness gate

```mermaid
flowchart TD
    A[Sale event in pending] --> B{All lines resolved?}
    B -->|No| NR1[needs_resolution: unmapped SKU]
    B -->|Yes| C{"Correlation present<br/>(or Square self-correlated)?"}
    C -->|No| NR2[needs_resolution: no payment side]
    C -->|"Yes, confidence=high"| D{"Sum of lines = gross ±$0.50?"}
    C -->|"Yes, confidence=medium"| NR3[needs_resolution: confirm fuzzy match]
    D -->|Yes| READY[ready to approve · show in 'ready' tab]
    D -->|No| NR4[needs_resolution: amount mismatch]
```

### 5.4 Approval failure recovery

```mermaid
flowchart TD
    A[Owner clicks Approve] --> B[state: approved]
    B --> C[Dispatch to Make Xero-write webhook]
    C --> D{Make scenario succeeds end-to-end?}
    D -->|Yes — invoice posted| E[state: posted · audit entry · UI updates]
    D -->|"No — Xero rejected (4xx)"| F[state: failed · capture Xero error]
    D -->|"No — Make scenario error / 5xx"| G{Within Make retry budget?}
    G -->|Yes| H[Make retries with backoff]
    G -->|"No, exhausted"| I[state: failed · reason: 'integration error']
    F --> J["owner sees error · fixes underlying issue<br/>(remap SKU, update item, etc.)"]
    J --> K[owner clicks Retry · state: pending]
    K --> A
    I --> J
    H --> D
```

## 6. Reconciliation Catalog

Reconciliation is the load-bearing feature of this system, and the docs that came before this section have used the word loosely. To be precise: **LBK's "transaction reconciliation" is a family of four distinct comparisons**, each with its own pair of sides, its own source systems, its own trigger, and its own definition of success. This section lists them. §7 ("Reconciliation cadence") describes *when* each one runs.

### The four kinds

| # | Kind | Left side | Right side | Source of left | Source of right | Trigger | Actor | Success criterion |
|---|---|---|---|---|---|---|---|---|
| 1 | **Sale ↔ Payment correlation** | A sale-side event | The payment-side event that paid for it | Squarespace, TicketTailor | Stripe (Square is unified — self-correlates) | On ingest of either side | System | Both sides linked; one Sale Event covers both rows |
| 2 | **Line totals ↔ event gross** (internal sanity check) | Sum of resolved Line Item amounts | The event's gross amount | Channel payload (lines) | Same channel payload (header) | On ingest | System | Difference within $0.50 tolerance |
| 3 | **Sale Event ↔ Xero Invoice** | Approved Sale Event in Phoenix | Posted Invoice in Xero | Phoenix DB | Xero API (idempotent on `Reference`) | Owner clicks Approve | Owner (initiates), System (writes) | Xero confirms `posted`; Invoice id stored on Sale Event |
| 4 | **Approved invoices ↔ Payout** | Sum of net amounts of approved Invoices for a (processor, date-window) | Payout amount landed in Xero via bank feed | Phoenix + Xero | Stripe / Square payout via Xero bank feed | Daily sweep | System flags, Owner reviews drift | Sums match within tolerance; else `drift_flagged` |

### Where each kind physically happens

- **Kind 1 (sale ↔ payment correlation)** runs in the Phoenix `Reconciliation` context, triggered by webhook ingest from Make. The matching ladder in §5.2 — `id_match`, then `metadata_match`, then `amount_time_window` — is the algorithm for this kind. Square does not need this step because its sale and payment arrive in one payload.
- **Kind 2 (line totals ↔ event gross)** also runs in the `Reconciliation` context, on ingest. Rule 3 in `domain-model.md` §6 sets the $0.50 tolerance. A failure routes the Sale Event to `needs_resolution` with reason `amount mismatch`.
- **Kind 3 (Sale Event ↔ Xero Invoice)** is the outbound side. The Phoenix `XeroWrites` context dispatches to the Make Xero-write scenario on owner approval; the result handler closes the loop. Idempotency on the `Reference` field carrying the Sale Event id prevents duplicate Invoices on retry.
- **Kind 4 (approved invoices ↔ Payout)** runs in a scheduled job inside the `Reconciliation` context (`Reconciliation.sweep_payouts/0`), triggered by the daily Make sweep — see Flow 4 in §4. Compares the local sum of approved Invoice nets against the payout amount that the bank feed brought into Xero.

### How the catalog overlays the architecture

```mermaid
flowchart LR
    Make_Ingress[Make: source-ingress scenarios] --> K1["Kind 1<br/>sale ↔ payment"]
    Make_Ingress --> K2["Kind 2<br/>lines ↔ gross"]
    Owner((Owner clicks approve)) --> K3["Kind 3<br/>sale → Xero invoice"]
    K3 --> Make_Xero[Make: Xero-write scenario]
    Make_Sweep[Make: reconciliation sweep] --> K4["Kind 4<br/>invoices ↔ payout"]
    K1 -. "feeds approval readiness" .-> K3
    K2 -. "feeds approval readiness" .-> K3
    K3 -. "produces the invoices that<br/>kind 4 sums" .-> K4
```

Reading the diagram: kinds 1 and 2 must succeed at ingest before a Sale Event can be approved. Kind 3 runs at the moment of approval. Kind 4 closes the loop end-to-end, days later, against the bank deposit.

### What "drift" looks like, per kind

| Kind | Drift / failure surface | Resolution |
|---|---|---|
| 1 | No matching payment side after 30 min → `needs_resolution`, reason `no payment side` | Owner investigates; usually a missing webhook or a refund |
| 2 | Line sums don't equal gross beyond $0.50 → `needs_resolution`, reason `amount mismatch` | Owner inspects line items; usually a fee anomaly or split charge |
| 3 | Xero rejects the invoice post → Sale Event state `failed` | Owner fixes underlying issue (remap SKU, update item), clicks Retry |
| 4 | Payout total ≠ sum of approved invoices → Payout state `drift_flagged` | Owner reviews; usually a missing ingest, a duplicate, or a fee/timing edge case |

## 7. Reconciliation cadence — continuous vs daily

Where §6 enumerates *what* gets reconciled, this section describes *when*. The four catalog kinds run on two cadences:

- **Continuous** — every event, in real time: kinds 1 and 2 (at ingest) and kind 3 (at approval).
- **Daily** — once per day, at the end-of-period sweep: kind 4 (payout closure).

```mermaid
flowchart TB
    subgraph Continuous["Continuous reconciliation (kinds 1, 2, 3)"]
        direction LR
        E1[Sale event arrives] --> E2["Kind 1: payment-side correlated<br/>Kind 2: lines sum to gross"]
        E2 --> E3[Owner approves]
        E3 --> E4["Kind 3: Itemized Invoice in Xero"]
    end

    subgraph Daily["Daily reconciliation (kind 4)"]
        direction LR
        P1["Payout lands in Xero<br/>via existing bank feed"] --> P2[Sweep pulls payout into Phoenix]
        P2 --> P3{"Sum of approved invoices<br/>for date range and processor<br/>== payout gross ± tolerance?"}
        P3 -->|Yes| P4[Payout reconciled]
        P3 -->|No| P5[Drift flagged for review]
    end

    Continuous -. "invoices produced by kind 3<br/>feed kind 4" .-> Daily
```

**Continuous reconciliation (kinds 1–3)** is what the owner sees most days: events arrive, kinds 1 and 2 fire automatically on ingest, the owner approves clean events, kind 3 posts the itemized invoice to Xero. One approval = one invoice.

**Daily reconciliation (kind 4)** is the closure step. Every few days, Stripe or Square deposits a lump sum into the bank account, the existing Xero bank feed brings it in as a bank transaction, and the daily sweep (Flow 4 in §4) compares the deposit against the sum of approved invoices for the matching window. Drift means a missing invoice (we never ingested the event), a duplicated invoice, or a fee/timing edge case worth investigating.

**Why both cadences matter:** continuous reconciliation gives item-level revenue granularity (without it, Xero just sees lump-sum payouts). Daily reconciliation closes the loop end-to-end against the bank account (without it, the per-item picture could quietly diverge from the actual money).

## 8. Audit trail

Every meaningful action emits an audit entry. The audit log is append-only and forensically complete: it answers "show me the full history of TicketTailor order TT-12345" in one query.

### What gets logged

| Action | What's captured |
|---|---|
| Sale event ingested | source, external id, normalized payload, ingestion time |
| State transition (any) | from_state, to_state, actor (system / user id), reason |
| Channel SKU created (unmapped) | external id, source, triggering sale event |
| Channel SKU mapped | sku id, mapped-to item id, actor |
| Correlation created | primary id, payment id, strategy, confidence |
| Owner approval | sale event id, user id, dashboard URL at time of approval |
| Make webhook dispatched | sale event id, action, payload sent |
| Xero write result received | request payload, response payload, status, latency |
| Voiding an invoice | xero invoice id, reason, user id |

### Example: end-to-end trace of one sale

```mermaid
sequenceDiagram
    autonumber
    participant E as Event
    participant Audit as audit_log
    Note over E,Audit: Each box below = one audit_log row

    E->>Audit: 1. event ingested · source=tickettailor · ext_id=TT-12345
    E->>Audit: 2. channel_sku auto-created · TT-12345 → unmapped
    E->>Audit: 3. state pending → needs_resolution · reason='unmapped SKU'
    E->>Audit: 4. owner mapped SKU TT-12345 → item TICKET-SPRING2026-ADULT
    E->>Audit: 5. state needs_resolution → pending · reason='SKU resolved'
    E->>Audit: 6. correlation found · strategy=amount_time_window · confidence=medium
    E->>Audit: 7. state pending → needs_resolution · reason='fuzzy match — confirm'
    E->>Audit: 8. owner confirmed correlation
    E->>Audit: 9. state needs_resolution → pending · reason='correlation confirmed'
    E->>Audit: 10. owner approved · user=owner@littlebigkids.com
    E->>Audit: 11. state pending → approved
    E->>Audit: 12. dispatched to Make: action=post_xero_invoice · payload=<...>
    E->>Audit: 13. state approved → posting
    E->>Audit: 14. Xero result · status=success · invoice_id=INV-9876 · response=<...>
    E->>Audit: 15. state posting → posted
```

A single query against `audit_log WHERE subject_id = 'TT-12345'` reproduces the full trace above.

### Immutability guarantees

- Audit log rows are written, never updated or deleted. Enforced by database role permissions in production, not just by application convention.
- Every state transition writes its audit row in the same database transaction as the state change itself. There is no window where a state has changed without a corresponding audit entry, or vice versa.
- The `xero_writes` table captures the full request and response payloads to/from Xero, in JSON. Useful for both forensic review and reproducing a failure offline.

## 9. Data model

The full entity-relationship diagram appears in `docs/domain-model.md` §4.1. Here we focus on the **implementation specifics** — concrete table names, column types, indexes.

```mermaid
erDiagram
    sale_events ||--o{ sale_event_lines : has
    sale_events ||--o{ correlations : "primary side"
    sale_events ||--o{ correlations : "payment side"
    sale_events ||--o| xero_writes : "yields on post"
    sale_event_lines }o--|| channel_skus : "resolves via"
    channel_skus }o--|| items : "maps to"
    items ||--o{ xero_write_lines : "decremented by"
    sale_events ||--o{ audit_log : "logs"
    xero_writes ||--o{ xero_write_lines : has
    payouts ||--o{ payout_invoices : "settles"
    xero_writes ||--o{ payout_invoices : "is settled in"

    sale_events {
        uuid id PK
        text source
        text external_event_id
        text source_event_type
        timestamptz occurred_at
        timestamptz received_at
        text currency
        bigint gross_cents
        bigint fee_cents
        bigint net_cents
        text state
        text state_reason
        uuid reviewed_by_id FK
        timestamptz reviewed_at
        jsonb raw_payload
        timestamptz inserted_at
        timestamptz updated_at
    }
    sale_event_lines {
        uuid id PK
        uuid sale_event_id FK
        int line_index
        uuid channel_sku_id FK
        text description
        int quantity
        bigint unit_price_cents
        bigint subtotal_cents
        bigint tax_cents
        bool resolved
    }
    correlations {
        uuid id PK
        uuid primary_sale_event_id FK
        uuid payment_sale_event_id FK
        text confidence
        text strategy
        timestamptz inserted_at
    }
    items {
        uuid id PK
        text xero_item_id
        text xero_item_code UK
        text name
        text kind
        int current_stock
        bigint unit_cost_cents
        text revenue_account_code
        timestamptz last_synced_at
    }
    channel_skus {
        uuid id PK
        uuid item_id FK "nullable until mapped"
        text source
        text external_id
        text external_name
        bool active
    }
    xero_writes {
        uuid id PK
        uuid sale_event_id FK
        text xero_invoice_id
        text xero_invoice_number
        jsonb payload_sent
        jsonb response_received
        text status
        timestamptz posted_at
    }
    xero_write_lines {
        uuid id PK
        uuid xero_write_id FK
        uuid item_id FK
        int quantity
        bigint unit_price_cents
    }
    payouts {
        uuid id PK
        text processor
        text external_payout_id UK
        date paid_on
        bigint gross_cents
        bigint fee_cents
        bigint net_cents
        text reconciliation_state
    }
    payout_invoices {
        uuid id PK
        uuid payout_id FK
        uuid xero_write_id FK
    }
    audit_log {
        uuid id PK
        text actor_type
        text actor_id
        text subject_type
        uuid subject_id
        text action
        jsonb metadata
        timestamptz occurred_at
    }
    users {
        uuid id PK
        text email UK
        text hashed_password
        timestamptz confirmed_at
    }
```

**Key indexes:**

- `sale_events`: `unique(source, external_event_id)` for idempotency; index on `(state, occurred_at)` for inbox queries; index on `(state_reason)` for filter chips.
- `channel_skus`: `unique(source, external_id)`; partial index on rows where `item_id IS NULL` (the "unmapped" queue).
- `correlations`: `unique(primary_sale_event_id)` and `unique(payment_sale_event_id)` to enforce "at most one correlation per side".
- `xero_writes`: `unique(sale_event_id)` to enforce "at most one invoice per sale event"; `unique(xero_invoice_id)`.
- `audit_log`: index on `(subject_type, subject_id, occurred_at)` for forensic queries.

## 10. API contract (Make ↔ Phoenix)

All endpoints under `/api/v1`. JSON request/response. Bearer token auth (`Authorization: Bearer <env-var>`).

### Inbound (Make → Phoenix)

| Method | Path | Purpose | Idempotency |
|---|---|---|---|
| `POST` | `/sale-events` | Ingest a normalized event. | `unique(source, external_event_id)` + `Idempotency-Key` header (24h dedupe). |
| `POST` | `/correlations` | Push a discovered pairing. | `unique(primary_id, payment_id)`. |
| `POST` | `/inventory-snapshot` | Bulk-replace cached item stock. | Whole-snapshot replace; per-call ok to retry. |
| `POST` | `/payouts` | Push payout records from Xero bank feed. | `unique(processor, external_payout_id)`. |
| `POST` | `/xero-write-result` | Callback from Xero-write scenario with success/failure. | `unique(sale_event_id)` — once posted, second result is logged but ignored for state. |

Sample inbound payload (`POST /sale-events`):

```json
{
  "source": "squarespace",
  "external_event_id": "sqs_order_9876",
  "source_event_type": "order.created",
  "occurred_at": "2026-05-21T14:23:11Z",
  "currency": "USD",
  "gross_cents": 8500,
  "fee_cents": 280,
  "net_cents": 8220,
  "lines": [
    {
      "line_index": 0,
      "external_sku": "var_tshirt_red_L",
      "description": "LBK T-shirt — red, large",
      "quantity": 2,
      "unit_price_cents": 2500,
      "subtotal_cents": 5000,
      "tax_cents": 0
    },
    {
      "line_index": 1,
      "external_sku": "var_book_adventure",
      "description": "Picture book: The Big Adventure",
      "quantity": 1,
      "unit_price_cents": 3500,
      "subtotal_cents": 3500,
      "tax_cents": 0
    }
  ],
  "raw_payload": { "...": "verbatim source webhook for forensics" }
}
```

### Outbound (Phoenix → Make)

Phoenix calls a single Make webhook URL. Make routes by `action`:

| `action` | Trigger | Payload |
|---|---|---|
| `post_xero_invoice` | Owner approves an event | sale_event_id + full invoice payload |
| `refresh_inventory` | Manual refresh button in dashboard | (no payload) |
| `reprocess_event` | Owner clicks "retry" on a failed event | sale_event_id |
| `void_invoice` | Owner voids a posted invoice | xero_invoice_id + reason |

## 11. Operational concerns

### Idempotency (four layers, see §5.4 for context)

1. `sale_events` unique on `(source, external_event_id)` — webhook re-deliveries no-op.
2. `Idempotency-Key` header on every API call — short-lived dedupe cache.
3. LiveView approve actions are state-guarded — re-clicking is a no-op.
4. Xero `Invoice.Reference = "lbkmk:<sale_event.id>"` — Make checks for existing before creating.

### Failure modes

See §5.4 and Flow 4. The TL;DR: webhooks for happy path, scheduled sweep as safety net, no single point of data loss because each source keeps its own record of every event.

### Deployment shape (high level — specifics chosen at deploy time)

- **Phoenix app** runs in any container host (Fly.io, Railway, Render, self-hosted). Two requirements: a publicly reachable URL (so Make can webhook in) and a Postgres database.
- **Postgres** managed by the host or external (Supabase, Neon). Daily backups; retention TBD by the owner.
- **Secrets** (bearer token, DB URL, Make webhook URL) injected via the host's secrets management. Bearer token rotates on a quarterly cadence; runbook in Phase 4.
- **Make.com** runs as SaaS. Subscription tier sized to total monthly ops; sized after Phase 0 volume estimates.

### Observability

- Phoenix LiveDashboard for runtime metrics (request rates, query times).
- Structured logs on every Make→Phoenix call: source, event_id, outcome, latency.
- Error tracking (Sentry / AppSignal / Honeybadger) added at deploy time.

## 12. What's explicitly **not** in scope (v1)

| Not in scope | Reason | When to revisit |
|---|---|---|
| Refund / return flow | Volume low; manual in Xero is acceptable. | Once monthly refund volume > ~10. |
| Multi-currency | USD only. | If LBK ever sells internationally. |
| Multi-org / multi-tenant | Single LBK org. | Not foreseen. |
| Multi-user roles | One operator. | When hiring second ops staff. |
| Mobile UI | Desktop bookkeeper workflow. | If usage patterns shift. |
| Analytics / BI dashboards | Xero already has reporting. | Not foreseen. |
| Sync **from** Xero back to channels | Product catalog stays managed in channels. | If channels need centralized catalog management. |
| Direct Phoenix → external APIs | Make owns all external API access. | Deliberate later decision, not drift. |

## 13. Open questions (must close before implementation starts)

| # | Question | Affects | Owner |
|---|---|---|---|
| Q1 | Does TicketTailor expose line items in webhooks/API, or do we need enrichment? | Line-item ingestion code path; potential extra Make API ops cost | Phase 0 spike |
| Q2 | Are Xero bank feeds active for Stripe and Square already? | Whether our invoices reconcile against existing deposits or risk duplicates | Owner / accountant |
| Q3 | Are existing Xero items tracked or untracked? | Onboarding scope: conversion + seeding | Owner / accountant |
| Q4 | Per-event ticket types: separate Inventory Items per event, or reused? | Domain model: §4.2 Inventory Item assumes per-event | Owner |
| Q5 | What's the expected monthly transaction volume across all channels? | Make.com plan sizing; Phoenix capacity | Owner |
| Q6 | Vocabulary alignment (see domain model §7) | UI labels and documentation tone | Owner review |
| Q7 | Hosting target preference (Fly.io / Railway / Render / self-host) | Deploy script and secrets management | Owner / ops |

## 14. Proposed delivery phases (high level)

Detailed phasing belongs in the implementation plan (next document). At a glance:

1. **Phase 0 — Discovery** (close all questions in §13).
2. **Phase 1 — End-to-end proof with Squarespace + Stripe + Xero.**
3. **Phase 2 — Add Square and TicketTailor; correlation across channels.**
4. **Phase 3 — Reconciliation sweep + payouts view.**
5. **Phase 4 — Hardening, audit UI, invoice void.**

Each phase produces a usable system; later phases add coverage and depth.
