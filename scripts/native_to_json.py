#!/usr/bin/env python3
"""Export macOS Text Replacements SQLite data to canonical JSON.

This script opens Apple's current local Text Replacements database in read-only
mode and exports shortcut/phrase pairs. It does not modify Apple's database.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import pathlib
import sqlite3
import sys
import uuid


DEFAULT_DB = pathlib.Path("~/Library/KeyboardServices/TextReplacements.db").expanduser()
SCHEMA = "keyboard-replacements.v1"


def now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def stable_id(shortcut: str, phrase: str) -> str:
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"keyboard-replacements:{shortcut}\0{phrase}"))


def connect_readonly(path: pathlib.Path) -> sqlite3.Connection:
    if not path.exists():
        raise FileNotFoundError(f"Text Replacements database not found: {path}")
    uri = f"file:{path}?mode=ro"
    return sqlite3.connect(uri, uri=True)


def export_items(db_path: pathlib.Path) -> list[dict]:
    with connect_readonly(db_path) as conn:
        # Skip CloudKit tombstones; exporting them would resurrect deletes on re-apply.
        columns = {row[1] for row in conn.execute("PRAGMA table_info(ZTEXTREPLACEMENTENTRY);")}
        where = "WHERE COALESCE(ZWASDELETED, 0) = 0 " if "ZWASDELETED" in columns else ""
        query = f"SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY {where}ORDER BY ZSHORTCUT COLLATE NOCASE;"
        rows = conn.execute(query).fetchall()

    items = []
    seen = set()
    for shortcut, phrase in rows:
        if shortcut is None or phrase is None:
            continue
        shortcut = str(shortcut)
        # A macOS DB can carry duplicate active shortcuts (sync conflicts); emitting both
        # produces JSON the shared preflight rejects, blocking every later edit/lint/push.
        if shortcut in seen:
            print(f"warning: skipping duplicate shortcut on export: {shortcut!r}", file=sys.stderr)
            continue
        seen.add(shortcut)
        phrase = str(phrase)
        items.append(
            {
                "id": stable_id(shortcut, phrase),
                "shortcut": shortcut,
                "phrase": phrase,
                "enabled": True,
                "group": None,
                "notes": None,
            }
        )
    return items


def main() -> int:
    parser = argparse.ArgumentParser(description="Export macOS native Text Replacements to canonical JSON.")
    parser.add_argument("--db", type=pathlib.Path, default=DEFAULT_DB, help=f"Path to TextReplacements.db. Default: {DEFAULT_DB}")
    parser.add_argument("--output", "-o", type=pathlib.Path, required=True, help="Output JSON path.")
    args = parser.parse_args()

    try:
        items = export_items(args.db.expanduser())
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1

    payload = {
        "schema": SCHEMA,
        "source": "macos-text-replacements",
        "native_db": str(args.db.expanduser()),
        "generated_at": now_iso(),
        "items": items,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(f"exported {len(items)} replacements to {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
