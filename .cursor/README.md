# Cursor harness (lbkmk)

This directory is the **Cursor-only** layer for agent guidance. It does not replace or fork project canon elsewhere in the repo.

## Canonical sources (read-only for Cursor)

| Document | Role |
|----------|------|
| [`CLAUDE.md`](../CLAUDE.md) | Full project brief: identity, worktrees, open questions, architecture, external-agent workflow |
| [`AGENTS.md`](../AGENTS.md) | Implementer discipline for plan execution (Kimi, subagents, external sessions) |
| [`docs/domain-model.md`](../docs/domain-model.md) | Vocabulary and business rules; check §7–8 before feature work |
| [`docs/external-agent-protocol.md`](../docs/external-agent-protocol.md) | Execution mechanics when running implementation plans |
| [`bin/dispatch-kimi`](../bin/dispatch-kimi) | Kimi dispatch from the terminal (orchestrator-driven) |

**Do not** add Cursor-specific prose to `CLAUDE.md` or `AGENTS.md`. Put Cursor-only behavior here or under `~/.cursor/`.

## What lives here

| Path | Purpose |
|------|---------|
| [`rules/`](rules/) | Short [Cursor rules](https://cursor.com/docs/context/rules) (`.mdc`) — scoped triggers that **point at** canon above, not duplicate it |
| [`hooks.json`](hooks.json) | Cursor hooks: primary-tree `git checkout` guard, handoff reminder on `stop` |
| [`user-rules-draft.md`](user-rules-draft.md) | Copy-paste draft for **Cursor → Settings → Rules** (not loaded automatically) |

## Personal skills (machine-local)

Reusable workflows live in `~/.claude/skills/`. For Cursor, symlink into `~/.cursor/skills/` so one `SKILL.md` serves both harnesses:

```bash
mkdir -p ~/.cursor/skills
ln -sf ~/.claude/skills/writing-plans ~/.cursor/skills/writing-plans
# … add others as needed
```

Do not write into `~/.cursor/skills-cursor/` (Cursor-internal).

## Global preferences

Machine-wide habits (trust boundary, US English, commit style) belong in **Cursor → Settings → Rules** (user rules), mirrored from `~/.claude/CLAUDE.md` if you use both tools — maintain consciously; do not edit `~/.claude/` when tuning Cursor only.

## Multi-agent worktrees

Same hard rule as `CLAUDE.md`: never check out a feature branch in the primary tree at `/Users/farouk/src/lbkmk`. Use `.worktrees/<branch>` for all non-trivial work.
