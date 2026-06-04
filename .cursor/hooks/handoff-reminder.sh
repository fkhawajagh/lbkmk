#!/usr/bin/env bash
# Remind on session end without auto-continuing the agent (stdout stays {}).
set -euo pipefail

cat >/dev/null || true

echo "[lbkmk] If this session produced meaningful work, write docs/.handoff/YYYY-MM-DD-<slug>.md in the primary checkout (gitignored). See docs/.handoff/README.md." >&2

echo '{}'
exit 0
