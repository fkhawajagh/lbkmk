#!/usr/bin/env python3
"""Compose the two preprocessed documents into a single combined markdown.

Produces docs/_render/combined.md with:
  - YAML frontmatter for Quarto
  - A sticky top nav (HTML at the top of the body)
  - Domain Model first, Solution Proposal second
  - Each major part introduced by an anchored container that the nav links to
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).parent.parent.resolve()
RENDER = ROOT / "docs" / "_render"

DOMAIN_MD = RENDER / "domain-model.md"
PROPOSAL_MD = RENDER / "solution-proposal.md"
COMBINED_MD = RENDER / "combined.md"


FRONTMATTER = """---
title: "Little Big Kids — Proposal"
subtitle: "Domain Model + Solution Proposal"
date: 2026-05-21
---

"""


NAVBAR_HTML = """::: {.lbk-topnav}
<a href="#part-1-domain-model" class="lbk-topnav__link" data-target="part-1-domain-model">
  <span class="lbk-topnav__num">I.</span>
  <span class="lbk-topnav__label">Domain Model</span>
</a>
<a href="#part-2-solution-proposal" class="lbk-topnav__link" data-target="part-2-solution-proposal">
  <span class="lbk-topnav__num">II.</span>
  <span class="lbk-topnav__label">Solution Proposal</span>
</a>
:::

"""


def strip_frontmatter(text: str) -> tuple[str, str]:
    """Return (frontmatter_block_without_delims, body)."""
    if not text.startswith("---\n"):
        return "", text
    end = text.find("\n---\n", 4)
    if end < 0:
        return "", text
    return text[4:end], text[end + 5 :]


def downshift_headings(body: str) -> str:
    """Bump every '# ' (and '## ', '### ' etc.) by one level so the combined
    document has a single top-level H1 (the part title) wrapping the original
    H1s as H2s.
    """
    out_lines = []
    in_code = False
    for line in body.splitlines(keepends=True):
        if line.lstrip().startswith("```"):
            in_code = not in_code
            out_lines.append(line)
            continue
        if in_code:
            out_lines.append(line)
            continue
        m = re.match(r"^(#{1,5})\s", line)
        if m:
            line = "#" + line
        out_lines.append(line)
    return "".join(out_lines)


def build() -> None:
    if not DOMAIN_MD.exists() or not PROPOSAL_MD.exists():
        raise SystemExit(
            "Preprocessed sources missing. Run preprocess-mermaid.py first."
        )

    _, domain_body = strip_frontmatter(DOMAIN_MD.read_text())
    _, proposal_body = strip_frontmatter(PROPOSAL_MD.read_text())

    parts: list[str] = [FRONTMATTER, NAVBAR_HTML]

    # Wrap each part in a pandoc fenced div so we can toggle visibility at
    # runtime. Without the wrapper, both documents render as one continuous
    # stream and the top nav can only scroll between them. With the wrapper,
    # the nav can show/hide the entire half.
    parts.append("::: {.lbk-part .is-active #part-1-domain-model}\n\n")
    parts.append("# Domain Model\n\n")
    parts.append(downshift_headings(domain_body))
    parts.append("\n\n:::\n\n")

    parts.append("::: {.lbk-part #part-2-solution-proposal}\n\n")
    parts.append("# Solution Proposal\n\n")
    parts.append(downshift_headings(proposal_body))
    parts.append("\n:::\n")

    COMBINED_MD.write_text("".join(parts))
    print(f"  combined.md written ({COMBINED_MD.stat().st_size:,} bytes)")


if __name__ == "__main__":
    build()
