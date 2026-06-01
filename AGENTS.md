# Project Instructions (External Agents)

Operative instructions for non-Claude external agents (e.g. Kimi via `bin/dispatch-kimi`) executing work in this repository. This file mirrors the subset of `CLAUDE.md` and the user's global preferences that an external agent needs while implementing a plan. `CLAUDE.md` remains the authoritative project doc for Claude Code; `docs/external-agent-protocol.md` is authoritative for execution mechanics. When this file and either of those diverge in a way that affects the task, surface the divergence in the status report rather than guessing.

## Critical: No Assumptions

- Do not assume when there is ambiguity.
- If you are not 95% confident in the answer or approach, stop and surface it — do not guess.
- When multiple valid interpretations exist, record them in the status report and let the orchestrator decide.
- Prefer one good clarifying note over a wrong assumption.

## Core Principles

- **KISS:** use the simplest viable approach before anything complex.
- **Be humble:** never reference Claude, AI, an LLM, or any model in code, comments, commit messages, documentation, or status reports. Author identity is not part of the project record.

## Code Style

- Write clean, readable code with meaningful names.
- Prefer explicit over implicit.
- Keep functions small and focused on a single responsibility.
- Add comments only when the "why" is not obvious from the code.
- **Immutability:** create new values, do not mutate existing ones in place.
- Handle errors explicitly at every level. Never silently swallow an error.
- Validate input at system boundaries; never trust external data (API responses, webhook payloads, file content).

## Communication & Workflow

- Be direct and concise.
- Commit in small, logical increments.
- Run tests after making changes when a test suite exists.
- Ask before making architectural decisions — these belong to the orchestrator, not the implementing agent.
- For long tasks, leave status notes at the checkpoints the plan defines.

## Coding Guidelines

### Bash / Shell scripting

- Shebang `#!/usr/bin/env bash`; always `set -euo pipefail`.
- Quote variables: `"${var}"`. Use `local` for function variables.
- Errors to stderr: `echo "Error: ..." >&2`. Use meaningful exit codes.

### Zsh scripting

- Shebang `#!/usr/bin/env zsh`. Arrays are 1-indexed.
- Use glob qualifiers for file matching and extended parameter expansion.
- The repo's dispatch tooling (`bin/dispatch-kimi`, `bin/wf-log`, `bin/wf-extract-segment`) is zsh — match its existing style mechanically when touching it.

### Python (documentation build pipeline)

The only code in the repo today is the doc-build pipeline under `scripts/` (Mermaid pre-processing, Quarto rendering).

- Python 3.14, modern type-hint syntax: PEP 695 `type` aliases, `X | Y` unions, lowercase generics (`list[str]`), `str | None` (not `Optional[str]`).
- Use `ruff` for linting and formatting (not black); `uv` for environments and packages.

### Elixir / Phoenix (when application code exists)

No application code exists yet — the repo is in the documentation and proposal phase. When `mix.exs` lands, follow these:

- **Ash Framework is NOT in use.** Do not lift Ash conventions (resources, policies, `ash_json_api`, Outbox change modules, `mix ash.codegen`). Persistence is direct **Ecto** changesets and `Repo`. Revisit only with explicit orchestrator approval.
- **Phoenix contexts** are the only public entry point into a domain (`Lbkmk.Ingest`, `Lbkmk.Reconciliation`, `Lbkmk.Inventory`). The web layer never calls `Repo` or schemas directly.
- **Behaviours for adapters:** external services (Squarespace, Stripe, Square, TicketTailor, Xero, Make) are `@behaviour`s with swappable dev/production implementations, called from within context functions, not controllers.
- **Error handling:** Ecto changeset errors for validation; explicit `{:ok, _} | {:error, _}` tuples for domain rules over exception-raising paths.
- Build-validation pipeline (run before committing once it exists): `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, `mix test`. Do not commit with formatting or credo failures.

### Git commit messages

- Imperative mood ("Add feature", not "Added feature"); subject under 72 chars; blank line before body.
- Conventional prefixes: `feat:`, `fix:`, `refactor:`, `docs:`, `test:`, `chore:`.
- No `Co-Authored-By` trailer and no reference to any assistant or AI.

## General Instructions

- Always read a file before editing it; preserve existing style and formatting.
- Respect `.gitignore` — never commit ignored files, and never use `git add -f` to bypass it (see protocol §2.5).
- Prefer absolute paths; validate paths before operating on them.
- Check project documentation first (`CLAUDE.md`, `docs/`).

## Worktree Scope (hard rule)

Every external agent works **only** inside the worktree the plan specifies (under `.worktrees/<branch>`). All Read / Write / Edit / shell / `git` operations use absolute paths rooted at that worktree. Never edit, delete, or commit files outside it; never commit to `main`. `cd` to the worktree once at session start and confirm with `pwd` and `git branch --show-current`. If a command appears to need a path outside the worktree, stop and surface it. See protocol §2.1–2.2.

## Code Safety

- Build dry-run capability into destructive operations.
- Never delete data from a database unless explicitly instructed.
- Never hardcode credentials, tokens, or secrets. Secrets are read from environment variables (via `config/runtime.exs` once the app exists). If a secret lands in a commit, surface it — the orchestrator handles rotation.

## Communication Conventions

- **US English** in all output — code, comments, commit messages, documentation, status reports. The one carve-out: Elixir's `@behaviour` keyword and prose naming it use the language's spelling (`behaviour`).

## lbkmk Hard Constraints

These are blocking gates. Treat them as checks before writing or committing code.

### Open Questions Policy

Before starting any feature area, check `docs/domain-model.md` §§7–8 (open vocabulary and scope questions). If an open question blocks the feature area, do not begin implementation — surface it and stop. Until questions are tagged with the areas they block, treat all of them as potentially blocking for any module touching the affected vocabulary or scope.

### Idempotency at ingress

Every external event ingestion is keyed on `(channel, external_event_id)` and must be harmless on re-delivery. See `docs/domain-model.md` §6 rule 16.

### Handoff documents

Session-end handoffs are committed to `docs/handoff/YYYY-MM-DD-<branch-or-topic-slug>.md` so they land on `main` at merge. This is distinct from the gitignored `docs/.context/<feature>/` process artefacts. See `docs/handoff/README.md`.

## External Agent Protocol

When executing an implementation plan handed off by the orchestrator, follow the standing External Agent Protocol at `docs/external-agent-protocol.md`. It consolidates worktree-scope rules, the no-push / no-PR closing protocol, in-flight (and segment-structural) checkpoints, code-quality / style / security rules, the end-of-work self-review checklist, branch hygiene, and the status-report format. The protocol is authoritative for execution mechanics; this file is the agent-side conventions summary.
