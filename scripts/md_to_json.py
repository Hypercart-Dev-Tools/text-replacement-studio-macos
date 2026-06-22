#!/usr/bin/env python3
"""Parse editable Keyboard Replacements Markdown back to canonical JSON."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import re
import sys
import uuid


SCHEMA = "keyboard-replacements.v1"
BLOCK_RE = re.compile(
    r"^## Replacement\s*\n(?P<meta>.*?)(?P<fence>`{3,})text\s*\n(?P<phrase>.*?)(?P=fence)\s*",
    re.MULTILINE | re.DOTALL,
)
FIELD_RE = re.compile(r"^-\s+(?P<key>[a-zA-Z_][a-zA-Z0-9_-]*):\s*(?P<value>.*)$")


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def stable_id(shortcut: str, phrase: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"keyboard-replacements:{shortcut}\0{phrase}"))


def parse_scalar(raw: str):
    value = raw.strip()
    if value == "":
        return None
    if value.lower() == "true":
        return True
    if value.lower() == "false":
        return False
    if value.startswith("`") and value.endswith("`") and len(value) >= 2:
        return value[1:-1]
    try:
        return json.loads(value)
    except Exception:
        return value


def parse_meta(meta: str) -> dict:
    fields = {}
    for line in meta.splitlines():
        match = FIELD_RE.match(line.strip())
        if not match:
            continue
        fields[match.group("key")] = parse_scalar(match.group("value"))
    return fields


def parse_markdown(text: str) -> list[dict]:
    items = []
    for match in BLOCK_RE.finditer(text):
        fields = parse_meta(match.group("meta"))
        shortcut = fields.get("shortcut")
        phrase = match.group("phrase")
        if phrase.endswith("\n"):
            phrase = phrase[:-1]
        if not shortcut:
            raise ValueError("Replacement block is missing shortcut")

        item_id = fields.get("id") or stable_id(str(shortcut), phrase)
        items.append(
            {
                "id": str(item_id),
                "shortcut": str(shortcut),
                "phrase": phrase,
                "enabled": bool(fields.get("enabled", True)),
                "group": fields.get("group"),
                "notes": fields.get("notes"),
            }
        )

    if not items:
        raise ValueError("No replacement blocks found. Expected '## Replacement' sections with fenced text blocks.")
    return items


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert editable Keyboard Replacements Markdown to canonical JSON.")
    parser.add_argument("input", type=pathlib.Path, help="Input Markdown path.")
    parser.add_argument("--output", "-o", type=pathlib.Path, required=True, help="Output JSON path.")
    args = parser.parse_args()

    try:
        text = args.input.read_text(encoding="utf-8")
        items = parse_markdown(text)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    payload = {
        "schema": SCHEMA,
        "source": "markdown",
        "generated_at": now_iso(),
        "items": items,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"parsed {len(items)} replacements to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
