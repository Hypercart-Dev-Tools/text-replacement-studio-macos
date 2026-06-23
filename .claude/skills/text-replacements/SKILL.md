---
name: text-replacements
description: Manage macOS text replacements, text expansions, snippets, and autocorrect entries from Claude Code by exporting the live database to a fresh JSON snapshot, editing it, linting it, previewing add/update/delete changes, and applying them safely with backup. Trigger on requests like "add a text expansion", "update my signature snippet", "delete a shortcut", "disable some snippets", or "find duplicate shortcuts".
---

# Text Replacements

Use this skill when the user wants to create, read, update, delete, disable, lint, or inspect macOS text replacements from Claude Code.

The source of truth is the live macOS database at `~/Library/KeyboardServices/TextReplacements.db`. Work on a disposable full JSON snapshot, then preview and apply changes back to that DB.

## Setup

Run from the repo root and use this exact setup:

```bash
mkdir -p .tmp
DB=~/Library/KeyboardServices/TextReplacements.db
SNAP=.tmp/repl.json
```

The snapshot is disposable and should be overwritten from a fresh export whenever a new edit session starts.

## Canonical Shape

The JSON schema is `keyboard-replacements.v1`. Each item may include:

- `id`
- `shortcut`
- `phrase`
- `enabled`
- `group`
- `notes`

Only edit fields that already belong to this schema.

## Standard Workflow

Always start from a fresh full export:

```bash
python3 scripts/native_to_json.py --db "$DB" --output "$SNAP"
```

Inspect or edit `"$SNAP"` directly. Do not build partial JSON files for apply operations.

### Create or Update

Use `merge` for additive changes and edits. `merge` adds new shortcuts and updates existing phrases, but never deletes shortcuts that are absent from the snapshot.

```bash
python3 scripts/lint_replacements.py "$SNAP"
python3 scripts/json_to_apple_sqlite.py "$SNAP" --db "$DB" --strategy merge
python3 scripts/json_to_apple_sqlite.py "$SNAP" --db "$DB" --strategy merge --apply
```

Typical edits:

- add a new item
- change `shortcut`
- change `phrase`

### Delete

Deletion requires `replace`, because `merge` never deletes. Only use `replace` on a freshly exported full snapshot with exactly the intended item or items removed.

```bash
python3 scripts/native_to_json.py --db "$DB" --output "$SNAP"
# edit "$SNAP" and remove only the shortcuts you intend to delete
python3 scripts/lint_replacements.py "$SNAP"
python3 scripts/json_to_apple_sqlite.py "$SNAP" --db "$DB" --strategy replace
python3 scripts/json_to_apple_sqlite.py "$SNAP" --db "$DB" --strategy replace --apply
```

`replace` deletes every shortcut missing from `"$SNAP"`. Never use it on a partial file.

### Read or Audit

For read-only inspection, export a fresh snapshot and inspect the JSON. To check for duplicates or invalid entries:

```bash
python3 scripts/native_to_json.py --db "$DB" --output "$SNAP"
python3 scripts/lint_replacements.py "$SNAP"
```

## Safety Rules

These are non-negotiable:

- Always export a fresh full snapshot before editing.
- Always run `python3 scripts/lint_replacements.py "$SNAP"` before any apply.
- Never apply if lint exits non-zero or reports `error:` lines such as empty shortcut, empty phrase, or duplicate shortcut.
- Always run the dry-run preview first and show the planned add/update/delete output before `--apply`.
- Never use `replace` unless the task is an explicit delete and the snapshot was freshly re-exported from the full live DB.
- Re-export immediately before apply if the snapshot is more than a few minutes old or if System Settings or another app may have changed replacements since export.
- Never apply while System Settings or another tool is actively editing text replacements.
- Never apply without the user's explicit intent to write the live DB.
- Do not bypass backups. `json_to_apple_sqlite.py --apply` writes a timestamped backup first.

## Verification

After an apply, re-export and confirm the result:

```bash
python3 scripts/native_to_json.py --db "$DB" --output "$SNAP"
python3 scripts/lint_replacements.py "$SNAP"
```

If macOS apps do not reflect the change immediately, quit and reopen System Settings and affected apps. A reboot may be needed if replacements stay stale.

## Notes

- `scripts/native_to_json.py` is read-only.
- `scripts/json_to_apple_sqlite.py` is dry-run by default. It only writes with `--apply`.
- The live SQLite apply path currently persists `shortcut` and `phrase` only. Fields like `enabled`, `group`, and `notes` belong to the canonical JSON shape, but they are not written back to the native macOS DB by `json_to_apple_sqlite.py`.
- If the user asks to disable entries in the live DB, explain that the current Phase 0 workflow does not support a true native disabled state. Deletion is supported; metadata-only edits are not.
