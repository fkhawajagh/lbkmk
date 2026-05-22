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
DIAGRAMS = RENDER / "diagrams"
MMDC = ROOT / "node_modules/.bin/mmdc"
CONFIG = DOCS / "theme/mermaid-config.json"

# Files to process. Listed explicitly so we don't pick up stray markdown.
INPUTS: tuple[str, ...] = ("domain-model.md", "solution-proposal.md")

MERMAID_BLOCK = re.compile(r"^```mermaid\n(.*?)\n```", re.MULTILINE | re.DOTALL)


def render_block(src: str, idx: int) -> str:
    """Render one mermaid source string to a standalone SVG file and emit
    an HTML fragment referencing it with <img>.

    Why a file + <img> instead of inlining the SVG markup directly in the
    HTML: pandoc's citation feature interprets '@keyframes' (and any other
    '@token') inside an inline SVG's CSS as a citation marker, breaks the
    SVG mid-stream, and orphans the styling. Using <img> hands the SVG to
    the browser opaquely; pandoc never sees its contents. Quarto's
    embed-resources later inlines the file as a base64 data URI so the
    final HTML stays self-contained.
    """
    h = hashlib.sha1(src.encode()).hexdigest()[:10]
    diagram_name = f"d-{idx:02d}-{h}.svg"
    out_path = DIAGRAMS / diagram_name

    with tempfile.NamedTemporaryFile(mode="w", suffix=".mmd", delete=False) as fin:
        fin.write(src)
        in_path = Path(fin.name)

    cmd = [
        str(MMDC),
        "-i", str(in_path),
        "-o", str(out_path),
        "-c", str(CONFIG),
        "-b", "transparent",
        "--quiet",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    in_path.unlink(missing_ok=True)
    if result.returncode != 0:
        sys.stderr.write(
            f"\nmmdc failed for diagram #{idx}.\n"
            f"--- stdout ---\n{result.stdout}\n"
            f"--- stderr ---\n{result.stderr}\n"
            f"--- source ---\n{src}\n"
        )
        raise SystemExit(1)

    svg = out_path.read_text()

    # Strip the inline white-background style mermaid-cli stamps on so the
    # diagram blends with the dark page when rendered.
    svg = re.sub(r"background-color:\s*white;?", "", svg)

    # mermaid's ER (and a few other) themes compute alternating row backgrounds
    # by tweaking lightness off a derived hue. With a dark base our 'alternate'
    # rows come out at ~91% lightness — pale cream, unreadable on the dark page.
    # Replace any computed light HSL fill with our dark surface; replace the
    # primary HSL with our base navy. This guarantees attribute rows blend into
    # the Tokyo-Night palette.
    svg = re.sub(
        r'fill="hsl\([^)]*?,\s*[^,]+?%\s*,\s*9\d(?:\.\d+)?%\s*\)"',
        'fill="#1A1B26"',
        svg,
    )
    svg = re.sub(
        r'fill="hsl\([^)]*?,\s*[^,]+?%\s*,\s*[12]\d(?:\.\d+)?%\s*\)"',
        'fill="#1F2335"',
        svg,
    )
    # Any remaining HSL fills (mid-lightness) -> bg-surface.
    svg = re.sub(r'fill="hsl\([^)]+\)"', 'fill="#1F2335"', svg)

    out_path.write_text(svg)

    return (
        '\n\n<div class="diagram diagram-zoomable">\n'
        f'<img src="diagrams/{diagram_name}" alt="Diagram {idx}" class="diagram-svg" />\n'
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
    DIAGRAMS.mkdir(exist_ok=True)
    # Clear previously rendered SVGs so stale files don't accumulate.
    for old in DIAGRAMS.glob("*.svg"):
        old.unlink()
    for name in INPUTS:
        n = process(name)
        print(f"  {name}: rendered {n} diagram{'s' if n != 1 else ''} -> {(RENDER / name).relative_to(ROOT)}")


if __name__ == "__main__":
    main()
