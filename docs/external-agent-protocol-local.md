# lbkmk — External Agent Protocol Local Addendum

Companion to the user-level `external-agent-protocol` skill at `~/.dotfiles/skills/external-agent-protocol/`. The skill carries the universal, project-agnostic rules (`rules/*.md`); this file carries only what is specific to lbkmk. The dispatched agent reads this after `SKILL.md` and `rules/*.md`, per the kickoff prompt.

## Project-specific invariants

- **Ash Framework is not in use.** Direct Ecto changesets and `Repo` are the persistence layer. Do not lift Ash-flavoured conventions (resources, policies, `ash_json_api`, Outbox change modules) into lbkmk code. Revisit this decision before introducing any Ash-flavoured pattern.
- **Idempotency at ingress.** Every external event ingestion is keyed on `(channel, external_event_id)` and must be harmless on re-delivery. See `domain-model.md` §6 rule 16.
- **Domain vocabulary is governed by `docs/domain-model.md`.** It is the source of truth for what every term means. Match its terms exactly when naming contexts, schemas, events, and routes.
- **Open-questions gate.** Do not begin design or implementation of a feature area that has unresolved open questions in `docs/domain-model.md` §§7-8. Surface a blocking open question rather than assuming an answer.
- **Phoenix context boundary.** Business logic lives in Phoenix contexts (`Lbkmk.Ingest`, `Lbkmk.Reconciliation`, `Lbkmk.Inventory`, etc.); the web layer never calls `Repo` or schemas directly. External services are behaviours with swappable dev/production implementations, called from within context functions, not from controllers. (Full conventions: `CLAUDE.md` → "Architecture Conventions".)

## Build pipeline notes

`.eap.toml#build_pipeline` is `["scripts/build-docs.sh"]`, the only working pipeline in the repo today. It renders `docs/{domain-model,solution-proposal}.md` to self-contained HTML in `docs/dist/`. It depends on the mermaid-cli installed by `npm install`, so run that once before the pipeline if `node_modules/` is absent.

The Phoenix pipeline (`mix deps.get`, `mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, `mix test`) is intentionally absent until `mix.exs` lands. When it does, replace `build_pipeline` in `.eap.toml` with those commands and update this note.

## User-facing surfaces (for stale-reference sweep)

n/a today: lbkmk has no application code or UI yet (documentation and proposal phase). When the Phoenix app comes online, the directories `rules/self-review.md`'s user-facing-surface sweep should scan are:

- `lib/lbkmk_web/live/` (LiveView modules)
- `lib/lbkmk_web/components/` (function components)

Update this list when those directories first appear.

## Project-specific tool surfaces

- `scripts/build-docs.sh` — the documentation build (see "Build pipeline notes" above). Currently the only project-local executable.

No custom test runner or project-only linter exists yet (no `mix.exs`). Do not duplicate the universal scripts under `~/.dotfiles/skills/external-agent-protocol/scripts/` here.

## Memory references

lbkmk's auto-memory lives at `~/.claude/projects/-Users-farouk-src-lbkmk/memory/` (indexed by `MEMORY.md`). These entries are not loaded automatically; reference them by name when the work calls for it. Notable entries:

- `feedback_worktrees_required` — never branch off main in the primary tree; always work in `.worktrees/<branch>`.
- `feedback_no_em_dashes` — hard rule: no em dashes anywhere (code, comments, docs, commits).
- `feedback_handoffs_in_dot_handoff` — session handoffs are gitignored bridges in `docs/.handoff/`, not committed.
- `feedback_agents_md_for_kimi` — `AGENTS.md` is the external-agent (Kimi) doc; `CLAUDE.md` is Claude's. Do not conflate them.

## Update history

- 2026-06-10 — Created at the toolkit cutover (issue #81): lbkmk adopts the shared `external-agent-protocol` skill with all advanced features off.
