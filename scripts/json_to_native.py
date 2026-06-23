#!/usr/bin/env python3
"""Convert canonical Keyboard Replacements JSON to Apple-importable plist."""

from __future__ import annotations

import argparse
import json
import pathlib
import plistlib
import sys

import replacements_common


def load_items(path: pathlib.Path) -> list[dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    items = payload.get("items")
    if not isinstance(items, list):
        raise ValueError("JSON must contain an items array")
    return items


def to_apple_items(items: list[dict], include_disabled: bool) -> list[dict]:
    apple_items = [
        {"shortcut": item["shortcut"], "phrase": str(item["phrase"])}
        for item in replacements_common.preflight(items, include_disabled=include_disabled)
    ]
    apple_items.sort(key=lambda row: row["shortcut"].lower())
    return apple_items


def main() -> int:
    parser = argparse.ArgumentParser(description="Convert canonical JSON to an Apple-importable Text Replacements plist.")
    parser.add_argument("input", type=pathlib.Path, help="Input JSON path.")
    parser.add_argument("--output", "-o", type=pathlib.Path, required=True, help="Output plist path.")
    parser.add_argument("--include-disabled", action="store_true", help="Include disabled items in plist export.")
    args = parser.parse_args()

    try:
        items = load_items(args.input)
        apple_items = to_apple_items(items, include_disabled=args.include_disabled)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("wb") as handle:
        plistlib.dump(apple_items, handle, sort_keys=False)
    print(f"wrote {len(apple_items)} Apple plist replacements to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
