#!/usr/bin/env python3
"""Lint Keyboard Replacements JSON or Markdown."""

from __future__ import annotations

import argparse
import importlib.util
import json
import pathlib
import sys

import replacements_common


def load_md_parser():
    script_path = pathlib.Path(__file__).with_name("md_to_json.py")
    spec = importlib.util.spec_from_file_location("md_to_json", script_path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def load_items(path: pathlib.Path) -> list[dict]:
    text = path.read_text(encoding="utf-8")
    if path.suffix.lower() in {".md", ".markdown"}:
        parser = load_md_parser()
        return parser.parse_markdown(text)
    payload = json.loads(text)
    items = payload.get("items")
    if not isinstance(items, list):
        raise ValueError("JSON must contain an items array")
    return items


def main() -> int:
    parser = argparse.ArgumentParser(description="Lint Keyboard Replacements JSON or Markdown.")
    parser.add_argument("input", type=pathlib.Path, help="Input JSON or Markdown path.")
    args = parser.parse_args()

    try:
        items = load_items(args.input)
        _, issues = replacements_common.check(items)
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    if not issues:
        print(f"ok: {len(items)} replacements passed lint")
        return 0

    exit_code = 0
    for severity, message in issues:
        print(f"{severity}: {message}")
        if severity == "error":
            exit_code = 1
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
