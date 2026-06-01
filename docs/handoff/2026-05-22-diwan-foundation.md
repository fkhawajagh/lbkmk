---
title: Session handoff — Diwan foundation (integration research, doc deltas, branding)
date: 2026-05-22
branch: docs/diwan-foundation
---

# Session handoff — 2026-05-22

## What landed this session

1. **Codename:** the application is now called **Diwan** (Arabic ديوان — the historical Islamic state chancery / accounting department; also the name of the calligraphic style developed for it). The repository folder name `lbkmk` is unchanged for now.

2. **Integration research (`docs/integrations/*.md`)** — six per-tool reference documents covering TicketTailor, Make.com, Squarespace, Stripe, Square, and Xero. Each follows the same template: role in Diwan, auth/credentials, key concepts, webhooks, API surface, best practices, anti-patterns, open questions, sources. Combined ~265 KB; sources are cited per claim (authoritative-first per `~/.dotfiles/rules/common/troubleshooting.md`).

3. **63 GitHub issues** (#2 → #64) — every tier-2 open question from the six integration docs filed individually with the `question` label. Many are resolvable in one ~2-hour empirical-test session against LBK's live accounts + a Square Sandbox; highest-leverage ones are flagged in `docs/solution-proposal.md` §12.

4. **Anchor doc updates** — `docs/solution-proposal.md` v0.1 → v0.2 and `docs/domain-model.md` v0.1 → v0.2, applying the corrections derived from the integration research. Notable corrections:
   - Flow 1 (Squarespace ingestion) had Stripe correlation running the wrong direction; rewrote to show Squarespace's Transactions API as the source of the Stripe `ch_...`.
   - Squarespace needs synchronous enrichment (line items not in webhook); TicketTailor does not. The v0.1 domain model said the opposite.
   - Stripe fees live on `balance_transaction`, not `Charge` — fee-enrichment step now explicit.
   - Make has no native HTTP retries — the approval-failure recovery diagram now shows the Break handler.
   - Per-channel signature schemes, ACK windows, auto-disable thresholds, and a footgun table added to §10 Operational concerns.

5. **Delta analysis doc** — `docs/2026-05-22-solution-proposal-delta.md` records every place where v0.1 of the proposal diverged from the integration research findings, with recommended actions. Functionally a changelog from v0.1 → v0.2; useful for understanding *why* each change was made.

6. **Branding concepts** — `docs/branding/` contains five SVG concept sketches (Arabic calligraphic wordmark, khatam + wordmark, standalone khatam mark, minimal Latin wordmark, Kufic-Latin attempt) plus a README explaining the rationale and limits. No direction has been chosen yet; the Kufic-Latin SVG attempt was rejected by the owner as a fail (raw-SVG hand-drawing was the wrong tool — should have used Google Fonts / a real designer from the start).

7. **Memory** — saved a feedback memory at `~/.claude/projects/-Users-farouk-src-lbkmk/memory/feedback_font_preferences.md`: prefer Google Fonts for typography work, Nerd Fonts for terminal/coding. Indexed in `MEMORY.md`.

## Status snapshot

- **Branch:** `docs/diwan-foundation` (this branch). One PR to be opened against `main`.
- **CI:** doc-build pipeline (`scripts/build-docs.sh`) was not run this session — no code changes that would affect it, but the next session may want to verify the Mermaid diagrams in the updated `solution-proposal.md` still render cleanly via the Quarto pipeline.
- **Issues:** #2 → #64 open, all `question`-labeled. Not yet triaged into milestones; the "tier-2 questions" footer in `docs/solution-proposal.md` §12 highlights the highest-leverage subset.

## What's blocked, on whom

The §12 of the solution proposal is the authoritative list. Briefly:

- **Owner-blocking:** the bank-feed configuration in LBK's Xero tenant (issue #51) is the single most load-bearing question on the whole project. Posting strategy depends on it.
- **Owner-blocking:** chart-of-accounts mapping (#56), Xero plan tier (#55), per-event ticket cap strategy (#53), and the vocabulary alignment in domain-model §7.
- **Empirical-resolvable (no owner needed):** the TicketTailor ↔ Stripe correlation question (#3, #29) is one short test against a real LBK TT order. Affirmative would upgrade most TicketTailor sales from `confidence: medium` to `confidence: high`.

## Suggested next moves for the next session

1. Verify the doc build (`scripts/build-docs.sh`) renders the updated Mermaid in `solution-proposal.md` correctly — the v0.2 changes touched Flow 1 and §5.4 diagrams.
2. Triage issues #2–#64 into GitHub milestones (Phase 0 Discovery, Phase 1 Foundation, deferred-to-v2). Cheap, makes Phase 0 ramp easier.
3. Use a Google Font (e.g. Lalezar, Reem Kufi, Aladin, Marhey) for the Diwan logo concepts rather than another hand-drawn SVG attempt. A small HTML preview file under `docs/branding/` would let the user compare directions in one tab.
4. Once the owner answers issue #51 (and ideally #55 + #56), the solution proposal can move to v0.3 with the posting-strategy section concretized.

## Files that bear re-reading

If picking this up cold, in this order:

1. `docs/domain-model.md` §1-3, §8 (the entities, glossary, and current open scope).
2. `docs/solution-proposal.md` §1-2, §10, §12 (overview, operational concerns, open questions).
3. `docs/2026-05-22-solution-proposal-delta.md` (why v0.2 looks the way it does).
4. `docs/integrations/xero.md` (highest stakes — explains the bank-feed reconciliation question).
5. `docs/integrations/tickettailor.md` and `docs/integrations/squarespace.md` (the two opposite ends of the line-items-in-webhook spectrum).

Skip the make/stripe/square integration docs unless directly relevant — they're long and on-demand.
