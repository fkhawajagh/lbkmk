---
title: Owner discovery questions
status: active
version: "1.0"
date: 2026-06-02
updated: 2026-06-02
tags:
  - type/reference
  - phase/0-discovery
  - domain/posting
  - domain/ingest
  - domain/inventory
  - domain/reconciliation
  - external/squarespace
  - external/stripe
  - external/square
  - external/tickettailor
  - external/xero
related:
  - project-status.yaml
  - domain-model.md
  - integrations/squarespace.md
  - integrations/stripe.md
  - integrations/square.md
  - integrations/xero.md
---

> **Document Version: 1.0** | 2026-06-02

# Owner discovery questions

Consolidated, plain-language version of the 17 `owner-input` discovery questions
that need LBK's owner to answer before (and during) the Phase 1 build. Each
question maps back to a tracked GitHub issue in the [Traceability](#traceability)
section. The four flagged as blockers gate Phase 1 design; they correspond to the
`phase/1-foundation` open questions recorded in `docs/project-status.yaml`.

## How to use this

- **Audience:** LBK's owner, and for the Xero accounting questions, their
  bookkeeper. The wording is deliberately non-technical.
- **What to send:** copy the [Questionnaire](#questionnaire) section. The rest of
  this document (purpose, traceability) is for the lbkmk team, not the owner.
- **When answers arrive:** record each answer on its GitHub issue, close the ones
  that are settled, and flip the four blockers. Closing the blockers moves Phase 1
  off `Pending` in `docs/project-status.yaml`.
- **Resolution split:** these 17 are the questions only the owner can answer. The
  other 46 discovery issues carry the `empirical` label and the team resolves them
  without the owner. See the [domain model](../domain-model.md) and the per-channel
  references under [integrations/](../integrations/) for the technical background.

## Questionnaire

> **lbkmk: a few questions to get the sales and stock system connected**
>
> Hi. To wire up the system that itemizes your sales and keeps Xero in sync, I
> need to confirm a handful of things about how LBK's Squarespace, Stripe, Square,
> and Xero accounts are set up. Most are quick. The four under "Start here" block
> the build, so please do those first if nothing else. The Xero ones may be
> easiest to answer with your bookkeeper, or by looking at Xero together for about
> 10 minutes.

### Start here: these four unblock everything

1. **Which Xero plan is LBK on?** Starter, Standard, Premium, or Cashbook. "Not
   sure" is fine; I can confirm from a screenshot. (Xero, then Settings, then
   Subscription, or your Xero billing email.)
   *Why:* tracked stock needs Standard or higher, and foreign-currency sales need
   Premium. It decides how we model your catalog.

2. **Where should each kind of sale and fee land in Xero?** Specifically: which
   account for merch sales, which for event ticket sales, which for Stripe fees,
   and which for Square fees. The easiest answer is a screenshot of your Chart of
   Accounts plus a sentence on which is which.
   *Why:* we cannot post a sale into Xero without knowing the account it belongs
   to.

3. **How do Stripe and Square reach Xero today, and do any "bank rules"
   auto-categorize them?** Are Stripe and Square already connected to Xero as
   automatic bank feeds? Do you have any bank rules that automatically mark those
   deposits as income? Who reconciles them today, you or a bookkeeper?
   *Why:* if Xero already records those deposits as income and we also record the
   itemized sale, your income would be counted twice. Knowing your current setup is
   how we avoid that. (Best answered with your bookkeeper.)

4. **How do you want event tickets tracked?** Our plan: each event's ticket
   becomes its own stock item in Xero (for example, "Spring 2026, Adult"), so you
   get stock and sales per event. The alternative is one generic "Adult Ticket"
   reused across all events, which is simpler but loses per-event stock and
   history. Which do you prefer?

### Squarespace

5. **Which Squarespace plan is LBK on?** (For example, Commerce Advanced?)
   (Squarespace, then Settings, then Billing.)
   *Why:* the top "Commerce Advanced" plan lets us connect with a simple key.
   Lower plans need a longer approval process, so it affects timeline.

### Stripe

6. **Other than Squarespace and TicketTailor, do you ever charge customers
   directly through Stripe?** (For example, a Stripe payment link or checkout you
   set up yourself.)
   *Why:* tells us whether to watch for stand-alone Stripe sales.

7. **When customers buy on Squarespace or TicketTailor, do those payments appear
   in LBK's own Stripe dashboard?** (Log into Stripe and check whether those
   charges show up.)
   *Why:* confirms we can see those payments to match them back to the right sale.

8. **In Stripe, under Settings then Connect (or "Connected accounts"), are
   Squarespace or TicketTailor listed? And under Developers then API version, what
   version shows?** Easier option: give me read-only access to Stripe and I will
   check these (and question 7) myself.
   *Why:* affects how the payment data reaches us. (Low stakes, and also: are you
   on a standard Stripe account, or any special or negotiated plan? Only if you
   happen to know.)

### Square

9. **Do you sell anything through "Square Online" (a Square-powered web store), or
   is Square in-person only?**
   *Why:* if items sell both online via Square and on Squarespace, we need to tell
   those apart.

10. **Do you ever send customers "Square Invoices" (Square's emailed invoice
    feature)?**
    *Why:* if yes, those are a separate kind of sale we would need to track.

### Xero (the rest)

11. **In Xero, should each customer be their own contact, or should sales be
    grouped under one contact per channel** (for example, a single "Squarespace
    Sales" contact)? Default is one per channel, which means fewer contacts and
    less personal data in Xero.

12. **Do you already use any Xero "Tracking Categories"** (for example, by sales
    channel or by event)? If so, which? (Xero, then Settings, then Tracking
    Categories, or I can check with read-only access.)

13. **Do you already have an expense account for card processing fees** (for
    example, "Stripe fees" or "Square fees")?
    *Why:* if yes, we leave fees to your existing setup; if no, we may add them
    explicitly.

14. **Do you ever take sales in a currency other than GBP** (for example, USD),
    and roughly how often?
    *Why:* foreign-currency sales need Xero's multi-currency feature (Premium
    plan), so this affects what we support first.

> That is everything. Even partial answers help. Thanks!

## Traceability

Each questionnaire item maps to one or more GitHub issues. Question 3 merges the
two "current Stripe and Square to Xero reconciliation" issues (#51 and #38), and
question 8 bundles the three Stripe-dashboard lookups (#34, #32, #31) behind a
single "or grant read-only access" shortcut.

| Question | Issue(s) | Blocker | Milestone |
|---|---|---|---|
| 1. Xero plan tier | #55 | yes | Phase 1 |
| 2. Chart of accounts | #56 | yes | Phase 1 |
| 3. Bank feeds and rules | #51, #38 | yes (#51) | Phase 1 |
| 4. Per-event ticket Items | #53 | yes | Phase 1 |
| 5. Squarespace plan tier | #19 | no | Phase 1 |
| 6. Direct Stripe sales | #36 | no | Phase 1 |
| 7. Channel charges in LBK Stripe | #27 | no | Phase 1 |
| 8. Stripe Connect, API version, rate tier | #34, #32, #31 | no | Phase 1 |
| 9. Uses Square Online | #47 | no | Phase 2 |
| 10. Uses Square Invoices | #48 | no | Phase 2 |
| 11. Xero contact strategy | #52 | no | Phase 1 |
| 12. Xero tracking categories | #57 | no | Phase 1 |
| 13. Processing-fee expense account | #61 | no | Phase 1 |
| 14. Multi-currency sales | #62 | no | Phase 1 |

All 17 `owner-input` issues are covered. The two Phase 2 items (#47, #48) ride
along because they are quick "yes or no" questions in the same owner conversation,
even though they do not block Phase 1.
