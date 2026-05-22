# Shared Context Template

When starting a new feature, copy the template below to `docs/.context/{feature}/context.md` and fill in feature-specific fields. The `docs/.context/` directory is gitignored; per-feature context dirs are deleted after the branch is merged or closed.

```markdown
# Feature: {name}
## Project: lbkmk
## Tech: Elixir + Phoenix + LiveView + Ecto | PostgreSQL | Tailwind CSS
## Patterns: Phoenix contexts, Ecto schemas + changesets, server-rendered LiveView, function components for stateless UI, behaviour-based adapters for external services (Squarespace / Stripe / Square / TicketTailor / Xero / Make)
## Key Files:
- App entry: lib/lbkmk/application.ex
- Web entry: lib/lbkmk_web/router.ex
- Contexts: lib/lbkmk/<context>.ex (e.g., lib/lbkmk/ingest.ex)
- Schemas: lib/lbkmk/<context>/<schema>.ex
- LiveViews: lib/lbkmk_web/live/<resource>_live/{index,form,show}.ex
- Components: lib/lbkmk_web/components/
- External-service adapters: lib/lbkmk/adapters/<service>.ex (behaviour) and lib/lbkmk/adapters/<service>/<impl>.ex
- Migrations: priv/repo/migrations/
## Constraints:
- PostgreSQL via Ecto. Direct Ecto is the only database interface; **Ash Framework is not in use** in this project. Patterns and tooling that assume Ash (resources, policies, ash_postgres, ash_json_api, ash_paper_trail, ash_state_machine, outbox change modules) are out of scope. Revisit before adopting any Ash-flavoured convention.
- All external integrations (Squarespace, Stripe, Square, TicketTailor, Xero) are mediated by Make scenarios. The application never calls those APIs directly; it consumes Make-shaped payloads at well-defined ingress points.
- Single-operator authorization: the system has one owner role. Multi-role authorization is not in scope for v1.
- All secrets via environment variables (read in `config/runtime.exs`). Never hardcode.
- Idempotency: ingestion of any external event is harmless on re-delivery, keyed on `(channel, external_event_id)`.
- US English in all prose and code, with the standard Elixir `@behaviour` carve-out (use British `behaviour`/`behaviours`/`behavioural` to match the language keyword).
```

Fill in the template with feature-specific files, contexts, and constraints. The template is a snapshot of the project's current architectural posture — when something shifts (e.g., a new external integration, a new context), update the template before the next feature starts.
