#!/usr/bin/env python3
"""Pre-render every ```mermaid block in the source markdown files to
inline SVG (via mermaid-cli / Puppeteer), so the final Quarto output
contains finished diagrams instead of relying on client-side rendering.

Writes the preprocessed files into docs/_render/ for Quarto to consume.
"""
from __future__ import annotations

import hashlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).parent.parent.resolve()
DOCS = ROOT / "docs"
RENDER = DOCS / "_render"
MMDC = ROOT / "node_modules/.bin/mmdc"
CONFIG = DOCS / "theme/mermaid-config.json"

# Files to process. Listed explicitly so we don't pick up stray markdown.
INPUTS: tuple[str, ...] = ("domain-model.md", "solution-proposal.md")

MERMAID_BLOCK = re.compile(r"^```mermaid\n(.*?)\n```", re.MULTILINE | re.DOTALL)


def render_block(src: str, idx: int) -> str:
    """Render one mermaid source string to an HTML fragment containing inline SVG."""
    h = hashlib.sha1(src.encode()).hexdigest()[:10]
    with tempfile.NamedTemporaryFile(mode="w", suffix=".mmd", delete=False) as fin:
        fin.write(src)
        in_path = Path(fin.name)
    out_path = in_path.with_suffix(".svg")
    cmd = [
        str(MMDC),
        "-i", str(in_path),
        "-o", str(out_path),
        "-c", str(CONFIG),
        "-b", "transparent",
        "--quiet",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(
            f"\nmmdc failed for diagram #{idx}.\n"
            f"--- stdout ---\n{result.stdout}\n"
            f"--- stderr ---\n{result.stderr}\n"
            f"--- source ---\n{src}\n"
        )
        raise SystemExit(1)

    svg = out_path.read_text()
    in_path.unlink(missing_ok=True)
    out_path.unlink(missing_ok=True)

    # mermaid-cli hardcodes id="my-svg" and uses #my-svg as the scope
    # selector inside the SVG's internal <style> block (and inside data-id
    # references on internal elements). We need to rewrite ALL of them
    # together so the diagram's own styling continues to apply once renamed
    # — otherwise text falls back to inherited document fonts (causing cell
    # overflow / truncation) and marker fills go to black defaults.
    unique_id = f"d-{idx:02d}-{h}"
    svg = svg.replace("my-svg", unique_id)

    # Strip the inline white-background style mermaid-cli stamps on.
    svg = re.sub(r"background-color:\s*white;?", "", svg)

    return (
        '\n\n<div class="diagram diagram-zoomable">\n'
        f'{svg}\n'
        '</div>\n\n'
    )


def process(name: str) -> int:
    src_path = DOCS / name
    text = src_path.read_text()
    count = 0

    def repl(match: re.Match[str]) -> str:
        nonlocal count
        count += 1
        return render_block(match.group(1), count)

    rendered = MERMAID_BLOCK.sub(repl, text)
    out_path = RENDER / name
    out_path.write_text(rendered)
    return count


def main() -> None:
    if not MMDC.exists():
        sys.stderr.write(
            f"mmdc not found at {MMDC}. Run: npm install --save-dev @mermaid-js/mermaid-cli\n"
        )
        raise SystemExit(1)
    if not CONFIG.exists():
        sys.stderr.write(f"Mermaid config missing: {CONFIG}\n")
        raise SystemExit(1)

    RENDER.mkdir(exist_ok=True)
    for name in INPUTS:
        n = process(name)
        print(f"  {name}: rendered {n} diagram{'s' if n != 1 else ''} -> {(RENDER / name).relative_to(ROOT)}")


if __name__ == "__main__":
    main()
