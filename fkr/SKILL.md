---
name: keyboard-replacements
description: "Manage macOS Keyboard Settings Text Replacements through Claude Code or terminal workflows. Use when exporting Apple Text Replacements, converting native replacements to JSON, editing replacements as Markdown, converting Markdown back to JSON, generating Apple-importable plist files, linting replacements, or preparing a safer MVP workflow before building a SwiftUI UI."
license: MIT
compatibility: "macOS with Python 3.9+ and sqlite3. Uses read-only access to ~/Library/KeyboardServices/TextReplacements.db by default. Does not directly write Apple's private database."
metadata:
  version: '0.1.0'
  author: Noel Saw / Perplexity Computer
---

# Keyboard Replacements

## When to Use This Skill

Use this skill when the user wants Claude Code to help manage macOS Keyboard Settings → Text Replacement entries without relying on Apple's limited UI.

Common requests:

- Export current macOS text replacements.
- Convert native replacements into JSON.
- Convert JSON into a human-editable Markdown file.
- Edit replacements in Markdown.
- Convert edited Markdown back to JSON.
- Generate an Apple-importable plist.
- Lint replacements for duplicates, empty fields, whitespace issues, or malformed Markdown.
- Prototype the data model before building a SwiftUI app.

## Safety Model

Default workflow is intentionally conservative:

1. Read Apple's current local SQLite database in read-only mode.
2. Convert entries to canonical JSON.
3. Convert JSON to a human-editable Markdown document.
4. Convert edited Markdown back to JSON.
5. Generate an Apple-compatible plist that the user can manually import through System Settings.

Do not directly write `~/Library/KeyboardServices/TextReplacements.db` unless the user explicitly asks for an experimental private-API workflow and accepts the risks. Apple's database schema and iCloud sync behavior are private implementation details.

## Bundled Scripts

The scripts live in `scripts/`.

- `native_to_json.py`: read current macOS native text replacements from SQLite and write canonical JSON.
- `json_to_md.py`: convert canonical JSON into editable Markdown.
- `md_to_json.py`: parse editable Markdown back into canonical JSON.
- `json_to_native.py`: convert canonical JSON into an Apple-compatible plist file.
- `lint_replacements.py`: validate JSON or Markdown replacements.
- `roundtrip_check.py`: test JSON → Markdown → JSON stability.

## Canonical JSON Format

Use this JSON shape as the source of truth:

```json
{
  "schema": "keyboard-replacements.v1",
  "source": "macos-text-replacements",
  "generated_at": "2026-06-21T00:00:00Z",
  "items": [
    {
      "id": "optional-stable-id",
      "shortcut": ";sig",
      "phrase": "Noel Saw\nNeochrome",
      "enabled": true,
      "group": null,
      "notes": null
    }
  ]
}
```

Only `shortcut` and `phrase` are required for Apple plist export. The other fields are retained for the user's richer workflow.

## Recommended Workflow

From a project directory:

```bash
mkdir -p keyboard-replacements

python3 path/to/keyboard-replacements/scripts/native_to_json.py \
  --output keyboard-replacements/replacements.json

python3 path/to/keyboard-replacements/scripts/json_to_md.py \
  keyboard-replacements/replacements.json \
  --output keyboard-replacements/replacements.md
```

The user edits `keyboard-replacements/replacements.md`, then run:

```bash
python3 path/to/keyboard-replacements/scripts/md_to_json.py \
  keyboard-replacements/replacements.md \
  --output keyboard-replacements/replacements.edited.json

python3 path/to/keyboard-replacements/scripts/lint_replacements.py \
  keyboard-replacements/replacements.edited.json

python3 path/to/keyboard-replacements/scripts/json_to_native.py \
  keyboard-replacements/replacements.edited.json \
  --output keyboard-replacements/TextReplacements.plist
```

Then import `TextReplacements.plist` manually through System Settings → Keyboard → Text Replacements.

## Claude Code Instructions

When using this skill from Claude Code:

1. Create a working folder such as `keyboard-replacements/`.
2. Export the current native state with `native_to_json.py`.
3. Commit or copy the raw export before editing.
4. Convert JSON to Markdown.
5. Let the user edit or ask Claude to edit the Markdown.
6. Convert Markdown back to JSON.
7. Run lint.
8. Generate the Apple plist.
9. Ask the user to manually import the plist into System Settings.

Never overwrite source files without creating a timestamped backup first.

## Editing Markdown

Each replacement appears as an `## Replacement` block:

```markdown
## Replacement

- id: `abc123`
- shortcut: `;sig`
- enabled: true
- group:
- notes:

```text
Noel Saw
Neochrome
```
```

The phrase is the text inside the fenced `text` block. Preserve the fences. If a replacement phrase needs backticks, use longer fences manually and verify with `md_to_json.py`.

## Importing the Result into macOS

The output of `json_to_native.py` is a plist compatible with Apple's Text Replacement import/export flow. Import it by opening System Settings → Keyboard → Text Replacements and dragging the plist into the Text Replacements window.

## Troubleshooting

- If `native_to_json.py` cannot open the database, ask the user to grant terminal access or manually copy `~/Library/KeyboardServices/TextReplacements.db`.
- If Markdown parsing fails, run `lint_replacements.py` against the Markdown file to locate malformed blocks.
- If duplicate shortcuts exist, resolve them before plist export unless the user explicitly wants Apple to handle conflicts.
- If iCloud sync changes entries unexpectedly, export again and compare JSON files before making another plist.
