---
id: ADR-0001
title: Xero posting strategy — clearing-account integration
status: Proposed
date: 2026-06-04
tags:
  - type/adr
  - topic/integration
  - topic/accounting
  - external/xero
related:
  - ../domain-model.md
  - ../solution-proposal.md
  - ../integrations/xero.md
  - ../project-status.yaml
---

# ADR-0001: Xero posting strategy — clearing-account integration

## Status

Proposed

## Context and Problem Statement

LBK already has Stripe and Square connected to Xero via official bank feeds. The owner reconciles manually using a **clearing-account flow**:

1. Itemized sales post to a Stripe or Square **clearing account** (a current asset account in Xero), each line categorized to the right revenue account.
2. The bulk deposit from Stripe/Square is **transferred manually** from the clearing account to the Novo bank account.
3. The actual Stripe/Square bank-feed deposit is then reconciled against that transfer.
4. Stripe fees are auto-stripped in the Stripe clearing account; Square fee handling is unknown.

lbkmk's default model (per `docs/integrations/xero.md`) is to post `ACCREC` Invoices that create Accounts Receivable, expecting bank-feed deposits to clear the AR via Xero's "Find & Match." This is incompatible with the clearing-account flow, which bypasses AR entirely. If lbkmk posts `ACCREC` Invoices while the existing bank rules auto-categorize feed deposits as revenue, the books are double-counted.

The decision: **what Xero document type and account structure should lbkmk use so that itemized sales decrement inventory, post revenue to the right accounts, and integrate cleanly with the owner's existing reconciliation flow?**

## Decision Drivers

- **No double-counting.** The existing bank feeds must continue to work without duplicating revenue.
- **Inventory decrement.** Every sale must decrement the relevant tracked (or untracked) Item's quantity.
- **Minimal owner workflow change.** The owner already has a working reconciliation habit; lbkmk should slot into it, not replace it.
- **Itemized revenue.** The owner needs per-product, per-event revenue granularity that the bank feeds alone cannot provide.
- **Fee separation.** Stripe and Square processing fees must remain clearly separated from gross revenue.
- **Future-proof.** The chosen pattern should not paint lbkmk into a corner if the owner later changes reconciliation habits or Xero plan tier.

## Considered Options

- **Option A: `ACCREC` Invoices + disable bank rules + manual "Find & Match"** — Post standard `ACCREC` Invoices. Disable or modify the existing Xero bank rules so feed deposits no longer auto-categorize as revenue. The owner reconciles each feed deposit against the sum of recent Invoices via Xero's "Find & Match" UI.
- **Option B: `ACCREC` Invoices to clearing account** — Post `ACCREC` Invoices, but each line item's revenue posts to the **same clearing account** the owner already uses, not to a revenue account. The bank feed then reconciles against the clearing account balance. Inventory decrements still happen. Revenue is recognized when the clearing account is transferred to Novo.
- **Option C: `RECEIVE` BankTransactions (cash sale) to clearing account** — Post `RECEIVE` BankTransactions directly into the clearing account, with line items carrying `ItemCode` and revenue account codes. This is Xero's "cash sale" pattern: no AR, immediate impact on the bank account (in this case, the clearing account). Inventory decrements via `ItemCode` (`RECEIVE` is a sales transaction in Xero's model, alongside `ACCREC` Invoice).
- **Option D: `ACCPAY` Bills (reverse pattern)** — Post incoming sales as `ACCPAY` Bills (as if LBK were the customer). This is a known workaround in the Xero community for cash-sale-like flows. Unconventional and confusing.

## Decision Outcome

Chosen option: **Option C — `RECEIVE` BankTransactions (cash sale) to clearing account**, because it is the only option that simultaneously (1) decrements inventory via `ItemCode`, (2) posts itemized revenue to the right accounts, (3) lands directly in the clearing account the owner already uses, and (4) leaves the existing bank-feed reconciliation flow completely untouched.

### Pros and cons of the options

#### Option A: `ACCREC` Invoices + disable bank rules + manual "Find & Match"
- Good: Standard Xero sales pattern; well-documented; AR aging reports work.
- Bad: Requires the owner to change their reconciliation habit (from clearing-account transfer to AR matching); bank rules must be disabled or reconfigured; Stripe feed deposits are net-of-fees and do not match 1:1 to any single Invoice, making "Find & Match" a multi-step manual process for every payout; double-counting risk if any rule is missed.

#### Option B: `ACCREC` Invoices to clearing account
- Good: Inventory decrements; itemized lines; uses existing clearing account.
- Bad: `ACCREC` creates an AR balance that is immediately "paid" by the clearing account — conceptually odd and may confuse Xero's AR reports; the clearing account is not a bank account in Xero's sense, so the "payment" against AR requires a manual Receive Money transaction or a journal, adding steps; does not actually simplify the owner's flow.

#### Option C: `RECEIVE` BankTransactions (cash sale) to clearing account
- Good: `RECEIVE` with `ItemCode` decrements inventory exactly like an `ACCREC` Invoice (Xero classifies `RECEIVE` as a sales transaction alongside `ACCREC`); line items post revenue to the configured account codes; the transaction lives directly in the clearing account, so the owner's existing transfer-to-Novo step needs no change; bank feeds continue exactly as today; no AR layer, no "Find & Match" step for the sales side; fees remain separate (Stripe feed brings fee lines into the same clearing account, which the owner already handles).
- Bad: `RECEIVE` is semantically "money received" — using it for not-yet-deposited sales is slightly odd, though correct in Xero's transaction-type model; Xero's built-in "Sales Overview" report may not include `RECEIVE` transactions by default (the owner may need to run a custom report or a General Ledger report); the `Reference` field on `BankTransaction` is less prominent than on `Invoice`; if Xero ever restricts `RECEIVE` behavior around `ItemCode`, this breaks.

#### Option D: `ACCPAY` Bills (reverse pattern)
- Good: None significant.
- Bad: Confusing semantics (LBK is not a customer buying from itself); breaks every standard report; not maintainable.

## Consequences

- **Xero document type changes.** lbkmk posts `BankTransaction` with `Type: "RECEIVE"` instead of `Invoice` with `Type: "ACCREC"`. The `Reference` field carries `lbkmk:<sale_event.id>` for idempotency. The `BankAccount` is the Stripe or Square clearing account (a `Code`, not a `BankAccountID` — the clearing account must be an Account of type `CURRENT` or `BANK`).
- **Inventory still decrements.** `RECEIVE` BankTransactions support `ItemCode` on line items, and Xero decrements tracked inventory on these exactly as it does for `ACCREC` Invoices (both are sales transactions in Xero's model). This is the load-bearing feature that makes Option C viable.
- **Revenue accounts unchanged.** Each line item carries the same `AccountCode` mapping (merch → `4000`, tickets → `4010`, etc.) as it would on an Invoice. The revenue hits the P&L the same way.
- **Owner workflow unchanged.** The owner continues to: (a) see itemized sales in the clearing account, (b) see the bulk deposit arrive via bank feed, (c) transfer the net from clearing to Novo, (d) reconcile the transfer. The only difference is that the itemized sales are now posted by lbkmk instead of entered manually.
- **Reporting consideration.** The owner must use General Ledger or custom reports to see itemized revenue by product/event, because Xero's built-in "Sales Overview" report may filter to Invoices only. This is a training/docs item, not a code change.
- **Idempotency strategy.** `BankTransaction` supports `Idempotency-Key` the same way `Invoice` does. The belt-and-braces strategy (`Idempotency-Key` header + `Reference` field pre-check) remains valid.
- **Daily reconciliation sweep (kind 4).** The sweep compares sum of lbkmk-posted `RECEIVE` transactions in the clearing account against the Stripe/Square payout that hits the same account via bank feed. The math is identical; only the Xero document type changes.
- **Future flexibility.** If the owner later switches to a pure `ACCREC` + "Find & Match" workflow (e.g., after hiring a bookkeeper), lbkmk can add a config toggle to post Invoices instead. The Sale Event → Xero mapping layer is abstracted enough to support both.
- **Documentation updates required.** `docs/integrations/xero.md` best-practice #1 ("One invoice per Sale Event") and anti-pattern #12 (bank-feed reconciliation) need revision. `docs/domain-model.md` §8 Q2 and `docs/solution-proposal.md` §3 Flow 3 (Xero write) need updates. `docs/project-status.yaml` Phase 1 open question `xero-posting-clearing-account` closes.
- **Square fee handling still open.** The owner does not know how the Square Xero feed handles Square fees. This ADR assumes they behave like Stripe fees (separate line items in the clearing account). If not, a follow-up adjustment may be needed. Tracked as issue #76.
