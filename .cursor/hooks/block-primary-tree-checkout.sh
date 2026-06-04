#!/usr/bin/env bash
# Deny git checkout/switch in the primary lbkmk tree; use .worktrees/<branch> instead.
set -euo pipefail

input=$(cat)
command=""
cwd=""

if command -v jq >/dev/null 2>&1; then
  command=$(echo "$input" | jq -r '.command // empty')
  cwd=$(echo "$input" | jq -r '.cwd // .working_directory // empty')
else
  command=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("command",""))' <<<"$input" 2>/dev/null || true)
  cwd=$(python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("cwd") or d.get("working_directory") or "")' <<<"$input" 2>/dev/null || true)
fi

if [[ -z "$cwd" ]]; then
  cwd="${PWD:-}"
fi

allow() {
  echo '{ "permission": "allow" }'
  exit 0
}

deny() {
  echo "$(cat <<'EOF'
{
  "permission": "deny",
  "user_message": "Blocked: do not check out branches in the primary lbkmk tree. Create a worktree under .worktrees/<branch> first (see CLAUDE.md).",
  "agent_message": "git checkout/switch denied in primary tree. Run: git worktree add .worktrees/<branch> -b <branch>, then cd there before checkout."
}
EOF
)"
  exit 0
}

# Only gate branch-changing git commands.
if [[ ! "$command" =~ git[[:space:]]+(checkout|switch) ]]; then
  allow
fi

# Allow read-only or worktree-related git invocations.
if [[ "$command" =~ git[[:space:]]+(checkout|switch)[[:space:]]+--help ]]; then
  allow
fi
if [[ "$command" =~ git[[:space:]]+worktree ]]; then
  allow
fi

repo_root=""
if [[ -n "$cwd" ]] && [[ -d "$cwd" ]]; then
  repo_root=$(cd "$cwd" && git rev-parse --show-toplevel 2>/dev/null || true)
fi

if [[ -z "$repo_root" ]]; then
  allow
fi

# Inside the repo but outside .worktrees/ → primary (or normal tree) — block checkout/switch.
case "$cwd" in
  "$repo_root"/.worktrees/*|"$repo_root"/.worktrees)
    allow
    ;;
  "$repo_root"|"$repo_root"/*)
    deny
    ;;
  *)
    allow
    ;;
esac
