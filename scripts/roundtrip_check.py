#!/usr/bin/env python3
"""Check JSON -> Markdown -> JSON round-trip stability."""

from __future__ import annotations

import argparse
import importlib.util
import json
import pathlib
import sys
import tempfile


def load_script(name: str):
    script_path = pathlib.Path(__file__).with_name(name)
    spec = importlib.util.spec_from_file_location(name.replace(".py", ""), script_path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def normalized_items(payload_or_items):
    items = payload_or_items.get("items", payload_or_items) if isinstance(payload_or_items, dict) else payload_or_items
    return sorted(
        [
            {
                "shortcut": str(item.get("shortcut", "")),
                "phrase": str(item.get("phrase", "")),
                "enabled": bool(item.get("enabled", True)),
                "group": item.get("group"),
                "notes": item.get("notes"),
            }
            for item in items
        ],
        key=lambda item: item["shortcut"].lower(),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Check JSON -> Markdown -> JSON round-trip stability.")
    parser.add_argument("input", type=pathlib.Path, help="Input canonical JSON path.")
    args = parser.parse_args()

    try:
        json_to_md = load_script("json_to_md.py")
        md_to_json = load_script("md_to_json.py")
        original = json.loads(args.input.read_text(encoding="utf-8"))
        markdown = json_to_md.render(original)
        parsed_items = md_to_json.parse_markdown(markdown)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if normalized_items(original) != normalized_items(parsed_items):
        print("error: round-trip changed replacement data", file=sys.stderr)
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as handle:
            handle.write(markdown)
            print(f"debug Markdown written to {handle.name}", file=sys.stderr)
        return 1

    print(f"ok: {len(parsed_items)} replacements round-tripped successfully")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
