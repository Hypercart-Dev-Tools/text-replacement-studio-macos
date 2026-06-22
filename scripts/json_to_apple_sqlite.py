#!/usr/bin/env python3
"""Experimental direct writer for macOS Text Replacements SQLite DB.

WARNING: This script writes to Apple's private implementation database:
~/Library/KeyboardServices/TextReplacements.db

It defaults to dry-run. Use --apply to mutate the database. The script creates
a timestamped backup of TextReplacements.db and companion -wal/-shm files before
any applied write.
"""

from __future__ import annotations

import argparse
import collections
import datetime as dt
import json
import pathlib
import shutil
import sqlite3
import sys
import time
import uuid


DEFAULT_DB = pathlib.Path("~/Library/KeyboardServices/TextReplacements.db").expanduser()
TABLE = "ZTEXTREPLACEMENTENTRY"
CORE_DATA_EPOCH_OFFSET = 978_307_200


def now_stamp() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M%S")


def core_data_timestamp() -> float:
    return time.time() - CORE_DATA_EPOCH_OFFSET


def load_items(path: pathlib.Path, include_disabled: bool) -> list[dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    items = payload.get("items")
    if not isinstance(items, list):
        raise ValueError("JSON must contain an items array")

    result = []
    seen = set()
    for item in items:
        if not include_disabled and item.get("enabled", True) is False:
            continue
        shortcut = item.get("shortcut")
        phrase = item.get("phrase")
        if shortcut is None or str(shortcut).strip() == "":
            raise ValueError(f"item has empty shortcut: {item!r}")
        if phrase is None:
            raise ValueError(f"item has missing phrase: {item!r}")
        shortcut = str(shortcut)
        if shortcut in seen:
            raise ValueError(f"duplicate shortcut in input JSON: {shortcut}")
        seen.add(shortcut)
        result.append({"shortcut": shortcut, "phrase": str(phrase)})
    return result


def backup_database(db_path: pathlib.Path, backup_dir: pathlib.Path) -> pathlib.Path:
    backup_dir.mkdir(parents=True, exist_ok=True)
    target_dir = backup_dir / f"text-replacements-backup-{now_stamp()}"
    target_dir.mkdir()

    for suffix in ["", "-wal", "-shm"]:
        source = pathlib.Path(str(db_path) + suffix)
        if source.exists():
            shutil.copy2(source, target_dir / source.name)

    return target_dir


def connect(db_path: pathlib.Path, readonly: bool) -> sqlite3.Connection:
    if not db_path.exists():
        raise FileNotFoundError(f"database not found: {db_path}")
    if readonly:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    else:
        conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    return conn


def table_columns(conn: sqlite3.Connection) -> list[sqlite3.Row]:
    rows = conn.execute(f"PRAGMA table_info({TABLE});").fetchall()
    if not rows:
        raise RuntimeError(f"table not found: {TABLE}")
    names = {row["name"] for row in rows}
    missing = {"ZSHORTCUT", "ZPHRASE"} - names
    if missing:
        raise RuntimeError(f"table {TABLE} is missing expected columns: {sorted(missing)}")
    return rows


def column_names(columns: list[sqlite3.Row]) -> list[str]:
    return [row["name"] for row in columns]


def active_where(names: set[str]) -> str:
    if "ZWASDELETED" in names:
        return "WHERE COALESCE(ZWASDELETED, 0) = 0"
    return ""


def fetch_current(conn: sqlite3.Connection, names: set[str]) -> list[sqlite3.Row]:
    return conn.execute(f"SELECT * FROM {TABLE} {active_where(names)};").fetchall()


def infer_entity(rows: list[sqlite3.Row], names: set[str]) -> int | None:
    if "Z_ENT" not in names:
        return None
    values = [row["Z_ENT"] for row in rows if row["Z_ENT"] is not None]
    if not values:
        return None
    return collections.Counter(values).most_common(1)[0][0]


def next_pk(conn: sqlite3.Connection, names: set[str]) -> int:
    if "Z_PK" not in names:
        raise RuntimeError("cannot insert because Z_PK column does not exist")
    value = conn.execute(f"SELECT COALESCE(MAX(Z_PK), 0) + 1 FROM {TABLE};").fetchone()[0]
    return int(value)


def parse_default(raw):
    if raw is None:
        return None
    text = str(raw)
    if text.upper() == "NULL":
        return None
    if len(text) >= 2 and text[0] == "'" and text[-1] == "'":
        return text[1:-1].replace("''", "'")
    try:
        return int(text)
    except ValueError:
        pass
    try:
        return float(text)
    except ValueError:
        pass
    return text


def value_for_insert_column(
    column: sqlite3.Row,
    shortcut: str,
    phrase: str,
    pk: int,
    entity: int | None,
    template: sqlite3.Row | None,
):
    name = column["name"]

    if name == "Z_PK":
        return pk
    if name == "Z_ENT":
        if entity is not None:
            return entity
        if template is not None:
            return template[name]
        return 1
    if name == "Z_OPT":
        return 1
    if name == "ZSHORTCUT":
        return shortcut
    if name == "ZPHRASE":
        return phrase
    if name == "ZWASDELETED":
        return 0
    if name == "ZNEEDSSAVETOCLOUD":
        return 1
    if name == "ZTIMESTAMP":
        return core_data_timestamp()
    if name == "ZUNIQUENAME":
        return str(uuid.uuid4()).upper()
    if name == "ZREMOTERECORDINFO":
        return None

    default = parse_default(column["dflt_value"])
    if default is not None:
        return default
    if template is not None and name in template.keys():
        return template[name]
    if column["notnull"]:
        raise RuntimeError(f"cannot infer required column {name}; create one text replacement in System Settings first so the script has a template row")
    return None


def current_by_shortcut(rows: list[sqlite3.Row]) -> dict[str, sqlite3.Row]:
    result = {}
    for row in rows:
        shortcut = row["ZSHORTCUT"]
        if shortcut is not None and shortcut not in result:
            result[str(shortcut)] = row
    return result


def plan_changes(current: dict[str, sqlite3.Row], desired: list[dict], delete_missing: bool) -> list[tuple[str, str, str | None]]:
    desired_by_shortcut = {item["shortcut"]: item for item in desired}
    plan = []

    for shortcut, item in desired_by_shortcut.items():
        row = current.get(shortcut)
        if row is None:
            plan.append(("add", shortcut, item["phrase"]))
        elif str(row["ZPHRASE"]) != item["phrase"]:
            plan.append(("update", shortcut, item["phrase"]))
        else:
            plan.append(("skip", shortcut, None))

    if delete_missing:
        for shortcut in sorted(set(current) - set(desired_by_shortcut), key=str.lower):
            plan.append(("delete", shortcut, None))

    return plan


def print_plan(plan: list[tuple[str, str, str | None]]) -> None:
    counts = collections.Counter(action for action, _, _ in plan)
    print(
        "plan: "
        + ", ".join(
            f"{name}={counts.get(name, 0)}"
            for name in ["add", "update", "delete", "skip"]
        )
    )
    for action, shortcut, phrase in plan:
        if action == "skip":
            continue
        if phrase is None:
            print(f"  {action:6} {shortcut}")
        else:
            preview = phrase.replace("\n", "\\n")
            if len(preview) > 80:
                preview = preview[:77] + "..."
            print(f"  {action:6} {shortcut} -> {preview}")


def update_primary_key_table(conn: sqlite3.Connection, entity: int | None, max_pk: int) -> None:
    exists = conn.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='Z_PRIMARYKEY';").fetchone()
    if not exists:
        return

    rows = conn.execute("PRAGMA table_info(Z_PRIMARYKEY);").fetchall()
    names = {row["name"] for row in rows}
    if "Z_MAX" not in names:
        return
    if entity is not None and "Z_ENT" in names:
        conn.execute("UPDATE Z_PRIMARYKEY SET Z_MAX = MAX(Z_MAX, ?) WHERE Z_ENT = ?;", (max_pk, entity))
    if "Z_NAME" in names:
        conn.execute("UPDATE Z_PRIMARYKEY SET Z_MAX = MAX(Z_MAX, ?) WHERE Z_NAME = ?;", (max_pk, TABLE))


def apply_changes(conn: sqlite3.Connection, columns: list[sqlite3.Row], desired: list[dict], delete_missing: bool) -> None:
    names = set(column_names(columns))
    rows = fetch_current(conn, names)
    current = current_by_shortcut(rows)
    desired_by_shortcut = {item["shortcut"]: item for item in desired}
    template = rows[0] if rows else None
    entity = infer_entity(rows, names)
    pk = next_pk(conn, names) if "Z_PK" in names else 1
    max_inserted_pk = pk - 1

    for shortcut, item in desired_by_shortcut.items():
        existing = current.get(shortcut)
        if existing is not None:
            set_parts = ["ZPHRASE = ?"]
            params = [item["phrase"]]
            if "ZNEEDSSAVETOCLOUD" in names:
                set_parts.append("ZNEEDSSAVETOCLOUD = 1")
            if "ZTIMESTAMP" in names:
                set_parts.append("ZTIMESTAMP = ?")
                params.append(core_data_timestamp())
            if "ZWASDELETED" in names:
                set_parts.append("ZWASDELETED = 0")
            params.append(shortcut)
            conn.execute(f"UPDATE {TABLE} SET {', '.join(set_parts)} WHERE ZSHORTCUT = ?;", params)
            continue

        insert_names = column_names(columns)
        values = [value_for_insert_column(column, shortcut, item["phrase"], pk, entity, template) for column in columns]
        placeholders = ", ".join("?" for _ in insert_names)
        conn.execute(f"INSERT INTO {TABLE} ({', '.join(insert_names)}) VALUES ({placeholders});", values)
        max_inserted_pk = max(max_inserted_pk, pk)
        pk += 1

    if delete_missing:
        for shortcut in sorted(set(current) - set(desired_by_shortcut), key=str.lower):
            if "ZWASDELETED" in names:
                set_parts = ["ZWASDELETED = 1"]
                params = []
                if "ZNEEDSSAVETOCLOUD" in names:
                    set_parts.append("ZNEEDSSAVETOCLOUD = 1")
                if "ZTIMESTAMP" in names:
                    set_parts.append("ZTIMESTAMP = ?")
                    params.append(core_data_timestamp())
                params.append(shortcut)
                conn.execute(f"UPDATE {TABLE} SET {', '.join(set_parts)} WHERE ZSHORTCUT = ?;", params)
            else:
                conn.execute(f"DELETE FROM {TABLE} WHERE ZSHORTCUT = ?;", (shortcut,))

    if max_inserted_pk > 0:
        update_primary_key_table(conn, entity, max_inserted_pk)


def main() -> int:
    parser = argparse.ArgumentParser(description="EXPERIMENTAL: write canonical JSON directly to Apple's TextReplacements.db.")
    parser.add_argument("input", type=pathlib.Path, help="Input canonical JSON path.")
    parser.add_argument("--db", type=pathlib.Path, default=DEFAULT_DB, help=f"TextReplacements.db path. Default: {DEFAULT_DB}")
    parser.add_argument("--backup-dir", type=pathlib.Path, default=pathlib.Path("./keyboard-replacements-backups"), help="Backup directory.")
    parser.add_argument("--strategy", choices=["merge", "replace"], default="merge", help="merge updates/adds only; replace also deletes shortcuts missing from JSON.")
    parser.add_argument("--include-disabled", action="store_true", help="Include disabled JSON entries when writing.")
    parser.add_argument("--apply", action="store_true", help="Actually mutate the SQLite database. Without this, only prints the plan.")
    args = parser.parse_args()

    try:
        db_path = args.db.expanduser()
        desired = load_items(args.input, include_disabled=args.include_disabled)
        delete_missing = args.strategy == "replace"

        with connect(db_path, readonly=not args.apply) as conn:
            columns = table_columns(conn)
            names = set(column_names(columns))
            rows = fetch_current(conn, names)
            current = current_by_shortcut(rows)
            plan = plan_changes(current, desired, delete_missing)
            print_plan(plan)

        if not args.apply:
            print("dry-run only. Re-run with --apply to write changes.")
            return 0

        backup_path = backup_database(db_path, args.backup_dir)
        print(f"backup written to {backup_path}")

        with connect(db_path, readonly=False) as conn:
            columns = table_columns(conn)
            conn.execute("BEGIN IMMEDIATE;")
            try:
                apply_changes(conn, columns, desired, delete_missing)
            except Exception:
                conn.rollback()
                raise
            else:
                conn.commit()

        print("applied changes. Quit/reopen System Settings and target apps; reboot if replacements do not refresh.")
        return 0
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
