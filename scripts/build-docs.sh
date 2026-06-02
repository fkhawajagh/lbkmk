#!/usr/bin/env bash
# Build self-contained HTML for review documents.
# Pipeline:
#   1. normalize-mermaid.py — rewrite mermaid blocks to mermaid-safe syntax
#   2. preprocess-mermaid.py — render each mermaid block to inline SVG (mmdc + headless Chromium)
#   3. quarto render — convert _render/*.md -> docs/dist/*.html (single self-contained files)
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v quarto >/dev/null 2>&1; then
  echo "Error: quarto is not installed or not on PATH." >&2
  echo "Install: brew install --cask quarto" >&2
  exit 1
fi

if [[ ! -x node_modules/.bin/mmdc ]]; then
  echo "Error: mermaid-cli not installed. Run: npm install --save-dev @mermaid-js/mermaid-cli" >&2
  exit 1
fi

echo "==> Normalizing mermaid syntax in source markdown"
python3 scripts/normalize-mermaid.py

echo ""
echo "==> Pre-rendering mermaid diagrams to inline SVG"
python3 scripts/preprocess-mermaid.py

echo ""
echo "==> Composing combined document with top nav"
python3 scripts/build-combined.py

mkdir -p docs/dist

echo ""
echo "==> Running Quarto (project mode — picks up theme + include-in-header from _quarto.yml)"
# Per-file render with `--to html` does NOT apply format-level config
# (theme, include-in-header) from _quarto.yml on quarto >=1.9; project-mode
# render does. The render: list in _quarto.yml drives which files are built.
cd docs/_render
quarto render 2>&1 | tail -5

cd ../..
echo ""
echo "Done. Outputs in docs/dist/:"
ls -lh docs/dist/*.html 2>/dev/null | awk '{print "  "$NF" ("$5")"}' || echo "  (no html files produced)"
