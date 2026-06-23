#!/usr/bin/env python3
"""Mock target-save harness for the direct SQLite writer.

`json_to_apple_sqlite.py --apply` mutates Apple's live Core Data store, so it
can't be tested against the real target. This builds a throwaway DB with the
columns the writer actually touches, runs the REAL CLI against it via
subprocess, and asserts the end state — surfacing any error in the scary path.

    python3 scripts/target_save_check.py        # exit 0 = all green

ponytail: mocks the columns the writer reads/writes (Z_PK, Z_ENT, ZSHORTCUT,
ZPHRASE, ZWASDELETED, ...), not a byte-for-byte Core Data replica.
"""

from __future__ import annotations

import json
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
ENTITY = 4


def make_mock_db(path: Path, rows: list[tuple[str, str]]) -> None:
    conn = sqlite3.connect(path)
    conn.executescript(
        """
        CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER);
        CREATE TABLE ZTEXTREPLACEMENTENTRY (
            Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER,
            ZWASDELETED INTEGER, ZNEEDSSAVETOCLOUD INTEGER, ZTIMESTAMP TIMESTAMP,
            ZSHORTCUT VARCHAR, ZPHRASE VARCHAR, ZUNIQUENAME VARCHAR, ZREMOTERECORDINFO BLOB
        );
        """
    )
    for i, (sc, ph) in enumerate(rows, start=1):
        conn.execute(
            "INSERT INTO ZTEXTREPLACEMENTENTRY "
            "(Z_PK,Z_ENT,Z_OPT,ZWASDELETED,ZNEEDSSAVETOCLOUD,ZTIMESTAMP,ZSHORTCUT,ZPHRASE,ZUNIQUENAME,ZREMOTERECORDINFO) "
            "VALUES (?,?,?,?,?,?,?,?,?,?)",
            (i, ENTITY, 1, 0, 0, 0.0, sc, ph, f"UUID-{i}", None),
        )
    conn.execute(
        "INSERT INTO Z_PRIMARYKEY (Z_ENT,Z_NAME,Z_SUPER,Z_MAX) VALUES (?,?,?,?)",
        (ENTITY, "TextReplacementEntry", 0, len(rows)),
    )
    conn.commit()
    conn.close()


def active(path: Path) -> dict[str, str]:
    conn = sqlite3.connect(path)
    try:
        return dict(
            conn.execute(
                "SELECT ZSHORTCUT, ZPHRASE FROM ZTEXTREPLACEMENTENTRY WHERE COALESCE(ZWASDELETED,0)=0"
            ).fetchall()
        )
    finally:
        conn.close()


def tombstoned(path: Path) -> set[str]:
    conn = sqlite3.connect(path)
    try:
        return {r[0] for r in conn.execute("SELECT ZSHORTCUT FROM ZTEXTREPLACEMENTENTRY WHERE ZWASDELETED=1")}
    finally:
        conn.close()


def write_json(path: Path, items: list[dict]) -> None:
    path.write_text(json.dumps({"schema": "keyboard-replacements.v1", "items": items}), encoding="utf-8")


def run(script: str, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, str(SCRIPTS / script), *args], capture_output=True, text=True)


def save(db: Path, inp: Path, backup: Path, strategy: str = "merge", apply: bool = True) -> subprocess.CompletedProcess:
    args = [str(inp), "--db", str(db), "--backup-dir", str(backup), "--strategy", strategy]
    if apply:
        args.append("--apply")
    return run("json_to_apple_sqlite.py", *args)


def soft_delete(path: Path, shortcut: str) -> None:
    conn = sqlite3.connect(path)
    try:
        conn.execute("UPDATE ZTEXTREPLACEMENTENTRY SET ZWASDELETED=1 WHERE ZSHORTCUT=?", (shortcut,))
        conn.commit()
    finally:
        conn.close()


def active_count(path: Path, shortcut: str) -> int:
    conn = sqlite3.connect(path)
    try:
        return conn.execute(
            "SELECT COUNT(*) FROM ZTEXTREPLACEMENTENTRY WHERE ZSHORTCUT=? AND COALESCE(ZWASDELETED,0)=0",
            (shortcut,),
        ).fetchone()[0]
    finally:
        conn.close()


def active_entity(path: Path, shortcut: str) -> int:
    conn = sqlite3.connect(path)
    try:
        return conn.execute(
            "SELECT Z_ENT FROM ZTEXTREPLACEMENTENTRY WHERE ZSHORTCUT=? AND COALESCE(ZWASDELETED,0)=0",
            (shortcut,),
        ).fetchone()[0]
    finally:
        conn.close()


def active_pk(path: Path, shortcut: str) -> int:
    conn = sqlite3.connect(path)
    try:
        return conn.execute(
            "SELECT Z_PK FROM ZTEXTREPLACEMENTENTRY WHERE ZSHORTCUT=? AND COALESCE(ZWASDELETED,0)=0",
            (shortcut,),
        ).fetchone()[0]
    finally:
        conn.close()


def set_zmax(path: Path, value: int) -> None:
    conn = sqlite3.connect(path)
    try:
        conn.execute("UPDATE Z_PRIMARYKEY SET Z_MAX=? WHERE Z_ENT=?", (value, ENTITY))
        conn.commit()
    finally:
        conn.close()


# --- scenarios ---------------------------------------------------------------

def test_dry_run_never_mutates(tmp: Path) -> None:
    db = tmp / "mock.db"
    make_mock_db(db, [("omw", "on my way")])
    inp = tmp / "in.json"
    write_json(inp, [{"shortcut": "omw", "phrase": "CHANGED"}, {"shortcut": "new", "phrase": "x"}])
    before = active(db)
    r = save(db, inp, tmp / "bak", apply=False)
    assert r.returncode == 0, r.stderr
    assert "plan:" in r.stdout, r.stdout
    assert active(db) == before, "dry-run mutated the DB"
    assert not (tmp / "bak").exists(), "dry-run created a backup"


def test_merge_add_update_skip(tmp: Path) -> None:
    db = tmp / "mock.db"
    make_mock_db(db, [("omw", "on my way"), ("ty", "thanks")])
    inp = tmp / "in.json"
    write_json(inp, [
        {"shortcut": "omw", "phrase": "on my way"},     # skip (unchanged)
        {"shortcut": "ty", "phrase": "thank you"},       # update
        {"shortcut": "brb", "phrase": "be right back"},  # add
    ])
    r = save(db, inp, tmp / "bak", "merge")
    assert r.returncode == 0, r.stderr
    assert active(db) == {"omw": "on my way", "ty": "thank you", "brb": "be right back"}
    assert list((tmp / "bak").iterdir()), "no backup created on --apply"


def test_replace_soft_deletes_missing(tmp: Path) -> None:
    db = tmp / "mock.db"
    make_mock_db(db, [("omw", "on my way"), ("ty", "thanks"), ("brb", "be right back")])
    inp = tmp / "in.json"
    write_json(inp, [{"shortcut": "omw", "phrase": "on my way"}])
    r = save(db, inp, tmp / "bak", "replace")
    assert r.returncode == 0, r.stderr
    assert active(db) == {"omw": "on my way"}
    assert tombstoned(db) == {"ty", "brb"}, "missing shortcuts should be soft-deleted, not hard-deleted"


def test_bad_input_rejected_before_write(tmp: Path) -> None:
    db = tmp / "mock.db"
    make_mock_db(db, [("omw", "on my way")])
    before = active(db)
    inp = tmp / "in.json"
    write_json(inp, [{"shortcut": "dup", "phrase": "a"}, {"shortcut": "dup", "phrase": "b"}, {"shortcut": "e", "phrase": ""}])
    r = save(db, inp, tmp / "bak", "merge")
    assert r.returncode != 0, "bad input must fail"
    assert "duplicate" in r.stderr or "phrase is empty" in r.stderr, r.stderr
    assert active(db) == before, "DB changed even though preflight rejected the input"
    assert not (tmp / "bak").exists(), "backup created for a save that never happened"


def test_tombstone_not_resurrected_on_export(tmp: Path) -> None:
    db = tmp / "mock.db"
    make_mock_db(db, [("omw", "on my way"), ("ty", "thanks")])
    write_json(tmp / "in.json", [{"shortcut": "omw", "phrase": "on my way"}])
    save(db, tmp / "in.json", tmp / "bak", "replace")  # soft-deletes 'ty'
    out = tmp / "export.json"
    r = run("native_to_json.py", "--db", str(db), "-o", str(out))
    assert r.returncode == 0, r.stderr
    exported = {i["shortcut"] for i in json.loads(out.read_text())["items"]}
    assert exported == {"omw"}, f"tombstoned shortcut leaked back into export: {exported}"


def test_readd_does_not_revive_tombstone(tmp: Path) -> None:
    db = tmp / "mock.db"
    make_mock_db(db, [("omw", "on my way"), ("foo", "old foo")])
    soft_delete(db, "foo")  # prior delete / CloudKit tombstone
    assert active(db) == {"omw": "on my way"} and tombstoned(db) == {"foo"}
    write_json(tmp / "a.json", [{"shortcut": "omw", "phrase": "on my way"}, {"shortcut": "foo", "phrase": "new foo"}])
    assert save(db, tmp / "a.json", tmp / "b1", "merge").returncode == 0
    write_json(tmp / "b.json", [{"shortcut": "omw", "phrase": "on my way"}, {"shortcut": "foo", "phrase": "edited foo"}])
    assert save(db, tmp / "b.json", tmp / "b2", "merge").returncode == 0
    assert active(db) == {"omw": "on my way", "foo": "edited foo"}
    assert active_count(db, "foo") == 1, "edit revived the tombstone -> duplicate active 'foo'"


def test_entity_inferred_from_tombstones_after_replace_all(tmp: Path) -> None:
    db = tmp / "mock.db"
    make_mock_db(db, [("omw", "on my way")])  # seeded with Z_ENT == ENTITY
    write_json(tmp / "empty.json", [])
    assert save(db, tmp / "empty.json", tmp / "b1", "replace").returncode == 0
    assert active(db) == {} and tombstoned(db) == {"omw"}  # table now holds only a tombstone
    write_json(tmp / "new.json", [{"shortcut": "new", "phrase": "x"}])
    assert save(db, tmp / "new.json", tmp / "b2", "merge").returncode == 0
    assert active(db) == {"new": "x"}
    assert active_entity(db, "new") == ENTITY, "insert after replace-all used wrong Z_ENT (ignored tombstone metadata)"


def test_pk_respects_z_primarykey_zmax(tmp: Path) -> None:
    db = tmp / "mock.db"
    make_mock_db(db, [("omw", "on my way")])  # Z_PK = 1
    set_zmax(db, 100)  # prior allocations / hard-deletes left Z_MAX ahead of MAX(Z_PK)
    write_json(tmp / "in.json", [{"shortcut": "omw", "phrase": "on my way"}, {"shortcut": "new", "phrase": "x"}])
    assert save(db, tmp / "in.json", tmp / "b", "merge").returncode == 0
    assert active_pk(db, "new") > 100, "new Z_PK reused an allocated key (ignored Z_PRIMARYKEY.Z_MAX)"


def test_export_dedupes_duplicate_shortcuts(tmp: Path) -> None:
    db = tmp / "mock.db"
    make_mock_db(db, [("dup", "a"), ("dup", "b"), ("omw", "on my way")])  # two active 'dup' rows
    out = tmp / "export.json"
    r = run("native_to_json.py", "--db", str(db), "-o", str(out))
    assert r.returncode == 0, r.stderr
    shortcuts = [i["shortcut"] for i in json.loads(out.read_text())["items"]]
    assert shortcuts.count("dup") == 1, f"export did not dedupe duplicate shortcut: {shortcuts}"
    assert "duplicate" in r.stderr.lower(), "no warning emitted for the dropped duplicate"


def main() -> int:
    tests = [
        test_dry_run_never_mutates,
        test_merge_add_update_skip,
        test_replace_soft_deletes_missing,
        test_bad_input_rejected_before_write,
        test_tombstone_not_resurrected_on_export,
        test_readd_does_not_revive_tombstone,
        test_entity_inferred_from_tombstones_after_replace_all,
        test_pk_respects_z_primarykey_zmax,
        test_export_dedupes_duplicate_shortcuts,
    ]
    failures = 0
    for t in tests:
        tmp = Path(tempfile.mkdtemp(prefix="target-save-"))
        try:
            t(tmp)
            print(f"  PASS   {t.__name__}")
        except AssertionError as exc:
            failures += 1
            print(f"  FAIL   {t.__name__}: {exc}")
        except Exception as exc:  # surface any unexpected error in the save path
            failures += 1
            print(f"  ERROR  {t.__name__}: {type(exc).__name__}: {exc}")
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    print(f"\n{len(tests) - failures}/{len(tests)} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
