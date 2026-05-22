#!/usr/bin/env bash
# Build self-contained HTML for review documents.
# Output goes to docs/dist/. Each .md becomes a single-file .html with
# Mermaid diagrams rendered inline and all CSS/fonts embedded.
set -euo pipefail

cd "$(dirname "$0")/../docs"

if ! command -v quarto >/dev/null 2>&1; then
  echo "Error: quarto is not installed or not on PATH." >&2
  echo "Install: brew install --cask quarto" >&2
  exit 1
fi

mkdir -p dist

# Render each top-level review doc. List explicitly so we don't sweep up
# anything accidental that lands in docs/ later.
DOCS=(
  "domain-model.md"
  "solution-proposal.md"
)

for doc in "${DOCS[@]}"; do
  if [[ ! -f "${doc}" ]]; then
    echo "Skipping docs/${doc} (file not found)" >&2
    continue
  fi
  echo "Rendering docs/${doc}..."
  quarto render "${doc}" --to html
done

echo ""
echo "Done. Outputs in docs/dist/:"
ls -1 dist/*.html 2>/dev/null || echo "  (no html files produced)"
