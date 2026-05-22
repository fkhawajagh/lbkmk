#!/usr/bin/env python3
"""Sweep mermaid blocks in source markdown and rewrite labels that
contain parens (or other mermaid-hostile chars) into quoted form,
which mermaid 10 always parses safely.

Modifies the source markdown files in place. Idempotent.

Patterns rewritten:
  | unquoted edge label |  ->  | "unquoted edge label" |   when it contains ( ) ; , — / etc.
  [unquoted node label]   ->  ["unquoted node label"]      when it contains ( ) / etc.
  {unquoted diamond}      ->  {"unquoted diamond"}         when it contains ( ) etc.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).parent.parent.resolve()
INPUTS = ("docs/domain-model.md", "docs/solution-proposal.md")

# Characters in a label that mermaid's flowchart parser does NOT tolerate
# in unquoted form. If any appear, the whole label needs quoting.
RISKY = set("();,=±/$")

MERMAID_BLOCK = re.compile(r"(^```mermaid\n)(.*?)(\n```)", re.MULTILINE | re.DOTALL)


def needs_quoting(label: str) -> bool:
    if label.startswith('"') and label.endswith('"'):
        return False
    return any(c in RISKY for c in label)


def quote_label(text: str) -> str:
    """Quote a label, escaping any embedded double-quotes."""
    return '"' + text.replace('"', '&quot;') + '"'


def fix_node_labels(block: str) -> str:
    """Quote [...] and {...} labels that contain risky chars.

    Only handles single-line, non-nested cases; that covers everything we use.
    """
    def fix_square(m: re.Match[str]) -> str:
        label = m.group(1)
        if needs_quoting(label):
            return f'[{quote_label(label)}]'
        return m.group(0)

    def fix_diamond(m: re.Match[str]) -> str:
        label = m.group(1)
        if needs_quoting(label):
            return f'{{{quote_label(label)}}}'
        return m.group(0)

    # Square node labels: NodeId[label], excluding already-quoted ones.
    # Match [label] where label has no [ or ] inside (single-level).
    block = re.sub(r'\[([^\[\]\n]+?)\]', fix_square, block)
    # Diamond node labels: NodeId{label}
    block = re.sub(r'\{([^{}\n]+?)\}', fix_diamond, block)
    return block


def fix_edge_labels(block: str) -> str:
    """Quote edge labels in --> |label|, -. label .->, etc."""
    def fix_pipe(m: re.Match[str]) -> str:
        label = m.group(1)
        if needs_quoting(label):
            return f'|{quote_label(label)}|'
        return m.group(0)

    block = re.sub(r'\|([^|\n]+?)\|', fix_pipe, block)
    return block


def detect_kind(block: str) -> str:
    """Return 'sequence', 'flowchart', 'state', 'er', or 'other'."""
    for raw in block.split('\n'):
        line = raw.strip()
        if not line:
            continue
        if line.startswith('sequenceDiagram'):
            return 'sequence'
        if line.startswith(('flowchart', 'graph')):
            return 'flowchart'
        if line.startswith('stateDiagram'):
            return 'state'
        if line.startswith('erDiagram'):
            return 'er'
        return 'other'
    return 'other'


def fix_sequence_messages(block: str) -> str:
    """Sequence diagrams: ';' is a statement separator; convert to ',' in messages."""
    fixed = []
    for line in block.split('\n'):
        if ':' in line and ';' in line:
            head, _, tail = line.partition(':')
            tail = tail.replace(';', ',')
            line = f'{head}:{tail}'
        fixed.append(line)
    return '\n'.join(fixed)


def fix_participant_aliases(block: str) -> str:
    """sequence diagrams: <br/> inside participant aliases is unsupported."""
    fixed = []
    for line in block.split('\n'):
        if re.match(r'^\s*(participant|actor)\s+\S+\s+as\s+', line) and '<br/>' in line:
            line = line.replace('<br/>', ' ')
        fixed.append(line)
    return '\n'.join(fixed)


def fix_block(block: str) -> str:
    kind = detect_kind(block)
    if kind == 'sequence':
        block = fix_sequence_messages(block)
        block = fix_participant_aliases(block)
    elif kind == 'flowchart':
        block = fix_node_labels(block)
        block = fix_edge_labels(block)
    # 'state', 'er', 'other' — pass through unchanged. Our state and ER
    # diagrams don't hit the same pitfalls (no diamond+paren combos), and
    # other diagram types we don't use.
    return block


def process(path: Path) -> int:
    src = path.read_text()
    changes = 0

    def repl(m: re.Match[str]) -> str:
        nonlocal changes
        original = m.group(2)
        fixed = fix_block(original)
        if fixed != original:
            changes += 1
        return m.group(1) + fixed + m.group(3)

    new = MERMAID_BLOCK.sub(repl, src)
    if new != src:
        path.write_text(new)
    return changes


def main() -> None:
    total = 0
    for rel in INPUTS:
        p = ROOT / rel
        n = process(p)
        print(f"  {rel}: {n} mermaid block{'s' if n != 1 else ''} normalized")
        total += n
    print(f"Total blocks rewritten: {total}")


if __name__ == "__main__":
    main()
