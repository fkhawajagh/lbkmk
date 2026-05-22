# lbkmk — Project Instructions

Project-local instructions for Claude Code working in this repo. Personal and global preferences live in `~/.claude/CLAUDE.md` and are not duplicated here; this file only captures conventions that are specific to lbkmk.

## Project Identity

**lbkmk** is a multi-channel inventory and sales reconciliation system for LBK. It ingests sale events from Squarespace, Stripe, Square, and TicketTailor, correlates them across sales and payment sides, decrements tracked inventory, and posts itemized invoices to Xero — so the owner can answer per-item revenue and stock questions that Xero's lump-sum bank feeds cannot.

Current state: documentation and proposal phase. No application code yet.

Anchor documents:

- `docs/domain-model.md` — vocabulary, entities, business rules. Source of truth for what every term means.
- `docs/solution-proposal.md` — proposed solution shape.

## Stack

- **Application:** Phoenix (LiveView) — planned. No app code in the repo yet.
- **Ash Framework:** likely not in use. Patterns and tooling that assume Ash (resources, policies, `ash_json_api`, Outbox change modules) are intentionally out of scope. Revisit this decision before lifting any Ash-flavoured convention.
- **Doc build:** Python plus Mermaid plus a Pandoc/Quarto-style pipeline under `scripts/`.

## Common Commands

```bash
# Documentation build (current state of the repo)
scripts/build-docs.sh                          # Render docs/{domain-model,solution-proposal}.md to self-contained HTML in docs/dist/
npm install                                    # Install mermaid-cli used by the doc build

# Phoenix application (placeholder — to be filled in once mix.exs lands)
# mix setup                                    # Install deps + create DB + migrate + seed
# mix phx.server                               # Dev server with live reload
# mix test                                     # Run all tests
# mix format                                   # Format code
# mix credo --strict                           # Lint
```

## Project Documents

All project documents (design docs, analysis, specs, etc.) live in `docs/` at the project root. Today this directory contains:

- **Domain model**: `domain-model.md` — vocabulary, entities, business rules. Source of truth for what every term means.
- **Solution proposal**: `solution-proposal.md` — proposed solution shape.
- **Module / component designs**: added here as they are built.

Naming conventions for new documents:

- **Final documents (PDF)**: include version in filename — `lbkmk-{name}-v{major}.{minor}.pdf` (e.g., `lbkmk-resilience-strategy-v1.0.pdf`).
- **Intermediate HTML**: used for review and validation only, no version number (e.g., `lbkmk-resilience-strategy.html`).
- **Design and plan documents**: `{date}-{name}-design.md` (e.g., `2026-06-01-ingestion-pipeline-design.md`).
- When a document is revised, update the version in both the filename and the document body (per the global `~/.claude/CLAUDE.md` document-versioning rule: major.minor only, no patch).

The existing top-level anchor docs (`domain-model.md`, `solution-proposal.md`) keep their current names — they are the canonical project anchors and do not follow the dated-design pattern.

## Handoff Documents

Session-end handoff documents — short notes that let the next session pick up where the previous one left off — live in **`docs/handoff/`** and are checked into git on `main`. This is distinct from `docs/.context/{feature}/` (the multi-agent pipeline's transient process artifacts), which is gitignored and disappears with the worktree.

Before wrapping any session that produced a meaningful unit of work (a merged PR, a mid-flight branch left for the next session, a decision made in conversation that isn't captured in the plan, PR, or memory), write a handoff to `docs/handoff/YYYY-MM-DD-<branch-or-topic-slug>.md` and commit it to the relevant branch so it lands on `main` at merge time. See `docs/handoff/README.md` for the full convention — when to write, the document skeleton, and how it relates to plan docs, PR descriptions, CLAUDE.md, and the memory system.

**Rule of thumb:** if losing the worktree would erase context the next session needs, it belongs in `docs/handoff/`, not `docs/.context/`.

## Open Questions Policy

**Do not begin implementation of any feature area that has unresolved open questions in `docs/domain-model.md`.**

The domain model carries two open-question sections that must be resolved (or explicitly accepted as risk) before related work begins:

- **§7 Open vocabulary questions** — terms where the owner needs to weigh in before the vocabulary is locked.
- **§8 Open scope questions** — concrete unknowns (TicketTailor line-item availability, existing Xero state, event-specific ticket caps, refund flow) that block parts of the solution.

When a future feature area is identified that an open question would block, tag the question in `domain-model.md` with the feature area it blocks (e.g., "blocks: ingestion-pipeline"). Until that tagging exists, treat all open questions as potentially blocking and surface them when planning any module touching the affected vocabulary or scope.

Check `docs/domain-model.md` §§7-8 before starting design or implementation on any module.

## Worktree Configuration

Use `.worktrees/` (project-local) for git worktrees during feature development:

```bash
git worktree add .worktrees/{feature-branch} -b {feature-branch}
```

The `.worktrees/` directory is gitignored. Each worktree gets its own isolated working copy.

## Tracking Deferred Work

Any work that surfaces during implementation but is out of scope for the current PR — bugs in pre-existing code, refactor candidates, tech debt, items the design explicitly defers — should be filed as a **GitHub issue**, not buried in a closing report, plan footnote, or `.context/` feedback file. GitHub issues are the single source of truth for open scope.

**When to file:**

- **Immediately** when an implementer surfaces something out of scope mid-flight (a checkpoint question that resolves to "defer; file an issue").
- **At PR-close** when the closing review pipeline accepts a Nit or Important as a follow-up rather than addressing inline.
- **At session-end** when wrapping up surfaces unresolved scope.

**Issue content:**

- Title is action-oriented (verb-first), under 70 chars.
- Body links back to the PR, closing report, or checkpoint that surfaced it, and references the relevant design doc or plan footnote so future readers do not have to dig.
- Use the default repo labels (`bug` for defects, `enhancement` for refactors or new work, `tech-debt` where it fits) unless richer labelling is established later.

**Trail:**

- The session wrap-up summary lists any issues filed.
- Closing reports, checkpoint files, and memory entries reference issues by number rather than duplicating content.

This keeps deferred work findable via `gh issue list` instead of scattered across worktree process files that disappear with the merge.

## Project Status

When the user asks for project status — typical phrasings include "project status", "where are we", "what's the state", "status update", "where do we stand" — synthesize a snapshot from the existing sources of truth. This is a query, not a tracker; do NOT create or modify a status doc to support it.

Sources to query, in order:

1. **In-flight PRs** — `gh pr list --state open --json number,title,headRefName,updatedAt,statusCheckRollup`. Note CI status on each.
2. **Open issues** — `gh issue list --state open --limit 30 --sort updated --json number,title,labels,updatedAt`. Group by label (`bug`, `enhancement`, `tech-debt`, etc.); flag stale ones (>30 days untouched).
3. **Last session's bridge** — most recent file in `docs/handoff/*.md` by mtime; one-line summary of where the prior session left off.
4. **Recent merges** — `git log main --oneline -10` for what landed lately.
5. **Open questions blocking work** — `docs/domain-model.md` §§7-8; surface any items that block feature areas under active development.

Synthesize into one structured report:

- **Shipped recently** — last N merges, one line each.
- **In flight** — open PRs, one line each, with CI/check status.
- **Open scope** — issues grouped by label and age; flag stale.
- **Blocked** — open questions or external dependencies blocking feature work.
- **Next obvious step** — recommendation based on the synthesis, with the reasoning in one sentence.

Keep the report tight (under one screen). The user can drill into any item by asking a followup.

## External Agent Workflow

When an implementation plan is handed off to a separately-orchestrated external agent (Claude- or Kimi-driven, not the main interactive session), the plan document **must** reference the standing External Agent Protocol. Add this line as the final paragraph of the plan, after task-specific instructions:

> Follow the standing External Agent Protocol at `docs/external-agent-protocol.md` in addition to the task-specific instructions above.

The protocol at `docs/external-agent-protocol.md` consolidates worktree-scope rules, the no-push / no-PR closing protocol, in-flight checkpoint requirements, code-quality / style / security rules, the end-of-work self-review checklist (cross-module consistency diff, stale-reference sweep, UX/code contradiction sweep, self-Opus pass), branch hygiene, and the status-report template. Plan authors do not copy these rules into each plan — they reference the standing doc so updates apply uniformly.

### Choosing the implementer

The main session (Opus) decides who executes a plan. Four options, in rough order of preference for routine implementation work:

| Option | When to use |
|---|---|
| **Kimi via `bin/dispatch-kimi`** | Default for routine lbkmk implementation tasks. Cheaper per token than Opus or Sonnet, runs in a subprocess, full Opus review pipeline still applies after. |
| **External Claude session** | Tasks that benefit from Claude-specific tools (particular MCPs, Claude-only skills) or where the team prefers Claude-trained code style. Plan handoff is manual — paste the plan into a new Claude Code session pointed at the worktree. |
| **In-process Sonnet via the `Agent` tool** | Small bounded sub-tasks where you want results back in the main conversation immediately. Use the `model: "sonnet"` per-call override. |
| **Opus does it directly** | Judgment-heavy work, or tasks too small to be worth dispatching. |

In all four cases, the closing Opus review pipeline (integration-reviewer + build-validator + `superpowers:code-reviewer` or `feature-dev:code-reviewer`) runs at Opus tier before push / PR — see the user-global `~/.claude/CLAUDE.md` "Model Routing Policy" section for the model-tier breakdown.

### Dispatch mechanics

For **Kimi**: `bin/dispatch-kimi <plan_path> <worktree_path>` for the initial dispatch, then `bin/dispatch-kimi --review <feedback_path> <worktree_path>` for any review-round follow-up. Both modes generate a kickoff prompt that points Kimi at `CLAUDE.md`, the protocol, and the plan; both write a per-run log to `docs/.context/<branch>/kimi-run-<timestamp>.log`. Kimi-specific implementer notes are in protocol §15.

For an **external Claude session**: paste the plan into a fresh Claude Code session pointed at the worktree. The plan must end with the standing-pointer line above.

### Authoring plans

Plans handed to Kimi or external Claude sessions should be authored via the `writing-plans` skill — a thin wrapper around `superpowers:writing-plans` that reads plan-quality lessons from `~/.claude/skills/writing-plans/lessons/`. The wrapper dispatches plan-writing to a fresh Opus subagent so the lessons apply at write-time. See `~/.claude/skills/writing-plans/SKILL.md` for the flow.

### Post-merge retrospective glean

After the PR merges, the orchestrator (main Opus session) reviews the gitignored process artefacts left in the worktree's `docs/.context/<feature>/` directory:

- `checkpoint-*.md` and `checkpoint-*-feedback.md` — implementer questions, orchestrator answers, plan defects surfaced mid-flight
- `code-review-feedback.md` — Blocker / Important / Nit findings from the Opus review pipeline
- `final-status.md` — what shipped, deviations from plan, test counts

The glean asks: what surfaced here that should propagate beyond this single feature? Lessons are auto-routed by category:

| Category | Destination |
|---|---|
| Plan-quality patterns (defects in the plan itself, missing context, ambiguous specs) | New file in `~/.claude/skills/writing-plans/lessons/<slug>.md` |
| External-agent behaviour (rules the implementer should have followed) | New subsection in `docs/external-agent-protocol.md` (bump protocol version) |
| Dispatch mechanics (Kimi / external-Claude bridge) | `bin/dispatch-kimi` itself |
| Orchestrator-side workflow (model routing, review pipeline, this workflow itself) | This section of `CLAUDE.md` or `~/.claude/CLAUDE.md` |
| Deferred work / followups surfaced but not addressed in this PR (out-of-scope items, surfaced bugs, refactor candidates, tech debt) | GitHub issue, filed at PR-close with cross-reference to the closing report (see "Tracking Deferred Work" above) |

The orchestrator summarises findings for the user before applying any routed changes; each destination edit lands as its own commit (or separate PR if the destination is outside the lbkmk repo) after user sign-off.

Skip the glean only when the run produced no `docs/.context/<feature>/` artefacts (e.g., a 1-task hotfix with no checkpoint).

## Shared Context Template

When starting a new feature, copy the template at [`docs/shared-context-template.md`](docs/shared-context-template.md) to `docs/.context/{feature}/context.md` and fill in feature-specific fields. The `docs/.context/` directory is gitignored; per-feature context dirs are deleted after the branch is merged or closed.

## Build Validation Commands

The `build-validator` agent should use these commands for this project. **Stub until `mix.exs` lands** — uncomment as the Phoenix app comes online:

```bash
# Documentation build (currently the only build pipeline in this repo)
scripts/build-docs.sh                          # Render docs/{domain-model,solution-proposal}.md → docs/dist/*.html

# Phoenix application (uncomment when mix.exs exists)
# mix deps.get                                  # Step 1: Dependencies
# mix compile --warnings-as-errors              # Step 2: Compile (strict)
# mix format --check-formatted                  # Step 3: Format check
# mix credo --strict                            # Step 4: Lint
# mix test --trace                              # Step 5: Tests
```

Frontend will be Phoenix LiveView (server-rendered) — no separate frontend build validation needed. Tailwind CSS is built via Phoenix's built-in asset pipeline.

## Architecture Conventions

**Stub — to be expanded as architecture emerges.** When designing features for lbkmk, follow these patterns:

- **Phoenix contexts**: business logic is expressed as Phoenix contexts (e.g., `Lbkmk.Ingest`, `Lbkmk.Reconciliation`, `Lbkmk.Inventory`). Each context wraps a set of Ecto schemas and is the only public entry point into its domain. The web layer never calls `Repo` or schemas directly.
- **Ecto schemas**: under `lib/lbkmk/<context>/<schema>.ex`. **Ash Framework is not in use** — direct Ecto changesets and `Repo` are the persistence layer.
- **LiveView**: UI state and user interaction handled server-side via LiveView modules. Organized under `lib/lbkmk_web/live/<resource_singular>_live/<action>.ex` with modules `LbkmkWeb.<Resource>Live.<Action>` (Phoenix 1.8 convention).
- **Components**: reusable UI pieces as function components (stateless) in `lib/lbkmk_web/components/`.
- **Forms**: standard `Phoenix.Component.to_form/2` over Ecto changesets. Standard `<.form for={@form}>` markup.
- **Router**: `lib/lbkmk_web/router.ex` — LiveView routes for the dashboard, plus plain Phoenix controllers for webhook ingest endpoints (Squarespace, Stripe, Square, TicketTailor — all mediated by Make).
- **Error handling**: use Ecto changeset errors for validation. For domain rules, prefer explicit `{:ok, _} | {:error, _}` tuples over exception-raising code paths. Let Phoenix render HTTP errors via the standard `ErrorView`.
- **Behaviours for adapters**: external services (Squarespace, Stripe, Square, TicketTailor, Xero, Make) are defined as behaviours with swappable implementations (dev vs production). Adapters are called from within context functions, not from controllers, so the test surface stays at the context boundary.
- **Idempotency at ingress**: every external event ingestion is keyed on `(channel, external_event_id)` and is harmless on re-delivery. See `docs/domain-model.md` §6 rule 16.
