#!/usr/bin/env python3
"""Convert canonical Keyboard Replacements JSON to editable Markdown."""

from __future__ import annotations

import argparse
import json
import pathlib
import sys


def fence_for(text: str) -> str:
    longest = 0
    current = 0
    for char in text:
        if char == "`":
            current += 1
            longest = max(longest, current)
        else:
            current = 0
    return "`" * max(3, longest + 1)


def inline_code(value) -> str:
    if value is None:
        return ""
    text = str(value)
    if "`" not in text:
        return f"`{text}`"
    return json.dumps(text, ensure_ascii=False)


def load_payload(path: pathlib.Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if "items" not in payload or not isinstance(payload["items"], list):
        raise ValueError("JSON must contain an items array")
    return payload


def render(payload: dict) -> str:
    lines = [
        "# Keyboard Replacements",
        "",
        "<!--",
        "Generated from canonical JSON. Edit replacement blocks, then run md_to_json.py.",
        "The phrase is the content inside each fenced text block.",
        "-->",
        "",
        f"- schema: `{payload.get('schema', 'keyboard-replacements.v1')}`",
        f"- source: `{payload.get('source', 'unknown')}`",
        f"- generated_at: `{payload.get('generated_at', '')}`",
        "",
    ]

    for item in payload["items"]:
        phrase = str(item.get("phrase", ""))
        fence = fence_for(phrase)
        lines.extend(
            [
                "## Replacement",
                "",
                f"- id: {inline_code(item.get('id'))}",
                f"- shortcut: {inline_code(item.get('shortcut', ''))}",
                f"- enabled: {str(bool(item.get('enabled', True))).lower()}",
                f"- group: {inline_code(item.get('group'))}",
                f"- notes: {inline_code(item.get('notes'))}",
                "",
                f"{fence}text",
                phrase,
                fence,
                "",
            ]
        )

    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert canonical Keyboard Replacements JSON to Markdown.")
    parser.add_argument("input", type=pathlib.Path, help="Input JSON path.")
    parser.add_argument("--output", "-o", type=pathlib.Path, required=True, help="Output Markdown path.")
    args = parser.parse_args()

    try:
        payload = load_payload(args.input)
        markdown = render(payload)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(markdown, encoding="utf-8")
    print(f"wrote Markdown for {len(payload['items'])} replacements to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
