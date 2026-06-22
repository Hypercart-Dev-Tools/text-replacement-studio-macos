<!-- ask_self:managed architecture_doc_v1 -->

# Fast Key Replacement (macOS) — Architecture Overview

Tools for working with Apple's text-replacement data on macOS:

## Repo stats (approximate)
- Files indexed in repo: ~50
- Total lines of code: ~3,781
- By language:
  - Markdown: 9 files, 1,365 LOC
  - Other: 31 files, 1,355 LOC
  - Python: 7 files, 871 LOC
  - Shell: 2 files, 180 LOC
  - JSON: 1 files, 10 LOC
- Git: branch `main` at `e744b69`

## Top-level layout
- `fkr/` (~1 files)
- `macOS/` (~31 files)
- `references/` (~1 files)
- `scripts/` (~9 files)

## Most important files
### Source: module
- `macOS/Sources/TextReplacementCLI/main.swift` (priority 3, 8 chunks)
- `macOS/Sources/TextReplacementCore/Models/ImportExport.swift` (priority 3, 8 chunks)
- `macOS/Sources/TextReplacementCore/Codecs/ApplePlistCodec.swift` (priority 3, 3 chunks)
- `macOS/Sources/TextReplacementCore/Codecs/JSONReplacementCodec.swift` (priority 3, 3 chunks)
- `macOS/Sources/TextReplacementCore/Models/AppleTextReplacementItem.swift` (priority 3, 3 chunks)
- `macOS/Sources/TextReplacementCore/Models/Replacement.swift` (priority 3, 3 chunks)
- `macOS/Sources/TextReplacementCore/Models/ReplacementChange.swift` (priority 3, 3 chunks)
- `macOS/Sources/TextReplacementCore/Services/DefaultReplacementImportExportRegistry.swift` (priority 3, 3 chunks)
- `macOS/Sources/TextReplacementCore/Services/ReplacementExporter.swift` (priority 3, 3 chunks)
- `macOS/Sources/TextReplacementCore/Services/ReplacementImporter.swift` (priority 3, 3 chunks)
- `macOS/Sources/TextReplacementCore/Services/ReplacementLinter.swift` (priority 3, 3 chunks)
- `macOS/Sources/TextReplacementCore/Services/ReplacementMergeEngine.swift` (priority 3, 3 chunks)

### Source: script
- `scripts/json_to_apple_sqlite.py` (priority 2, 20 chunks)
- `scripts/md_to_json.py` (priority 2, 7 chunks)
- `scripts/json_to_md.py` (priority 2, 6 chunks)
- `scripts/native_to_json.py` (priority 2, 6 chunks)
- `scripts/lint_replacements.py` (priority 2, 5 chunks)
- `scripts/json_to_native.py` (priority 2, 4 chunks)
- `scripts/roundtrip_check.py` (priority 2, 4 chunks)

### Source: doc
- `macOS/macos-text-replacement-studio-notes.md` (priority 1, 30 chunks)
- `PDDA-INSTALL.md` (priority 1, 12 chunks)
- `references/native-format-notes.md` (priority 1, 5 chunks)

### Source: policy
- `fkr/SKILL.md` (priority 5, 13 chunks)
- `AGENTS.md` (priority 5, 4 chunks)
- `macOS/README.md` (priority 5, 4 chunks)
- `README.md` (priority 5, 2 chunks)

### Source: config
- `macOS/Package.swift` (priority 3, 2 chunks)

### Source: test
- `macOS/Tests/TextReplacementCoreTests/ApplePlistCodecTests.swift` (priority 4, 2 chunks)

## Symbol index
### `scripts/json_to_apple_sqlite.py`
- Functions: `now_stamp`, `core_data_timestamp`, `load_items`, `backup_database`, `connect`, `table_columns`, `column_names`, `active_where`, +11 more

### `scripts/md_to_json.py`
- Functions: `now_iso`, `stable_id`, `parse_scalar`, `parse_meta`, `parse_markdown`, `main`

### `scripts/json_to_md.py`
- Functions: `fence_for`, `inline_code`, `load_payload`, `render`, `main`

### `scripts/native_to_json.py`
- Functions: `now_iso`, `stable_id`, `connect_readonly`, `export_items`, `main`

### `scripts/lint_replacements.py`
- Functions: `load_md_parser`, `load_items`, `lint`, `main`

### `scripts/json_to_native.py`
- Functions: `load_items`, `to_apple_items`, `main`

### `scripts/roundtrip_check.py`
- Functions: `load_script`, `normalized_items`, `main`

## Dependency map
### `scripts/json_to_apple_sqlite.py`
- Imports: _none_
- Used by: _none_

### `scripts/md_to_json.py`
- Imports: _none_
- Used by: _none_

### `scripts/json_to_md.py`
- Imports: _none_
- Used by: _none_

### `scripts/native_to_json.py`
- Imports: _none_
- Used by: _none_

### `scripts/lint_replacements.py`
- Imports: _none_
- Used by: _none_

### `scripts/json_to_native.py`
- Imports: _none_
- Used by: _none_

### `scripts/roundtrip_check.py`
- Imports: _none_
- Used by: _none_

## Freshness
- Generated at: `2026-06-22T05:40:46+00:00`
- Generated from commit: `e744b69`
- Current HEAD at ingest: `e744b69`
- Working tree at ingest: dirty (9 files)
- This document should be considered stale once the repo moves to a different HEAD or the working tree changes materially.

## How it fits together
_Narrative fallback used: Gemini finish reason was MAX_TOKENS; compact retry: Gemini finish reason was MAX_TOKENS._

The repository is organized around `macOS/Sources/TextReplacementCLI/main.swift`, `macOS/Sources/TextReplacementCore/Models/ImportExport.swift`, `macOS/Sources/TextReplacementCore/Codecs/ApplePlistCodec.swift`, and `macOS/Sources/TextReplacementCore/Codecs/JSONReplacementCodec.swift`, which appear to be the highest-signal implementation files in the indexed corpus. Together they act as the main execution and coordination layer, with the remaining modules filling in supporting configuration, helper, and documentation roles.

At the symbol level, `scripts/json_to_apple_sqlite.py` exposes `now_stamp`, `core_data_timestamp`; `scripts/md_to_json.py` exposes `now_iso`, `stable_id`; `scripts/json_to_md.py` exposes `fence_for`, `inline_code`. That index is meant to shorten the jump from architectural overview into the exact function or class a new session probably needs to inspect next.

Outside the main implementation path, documentation and policy context lives in `macOS/macos-text-replacement-studio-notes.md`, `PDDA-INSTALL.md`, `references/native-format-notes.md` while behavioral expectations are exercised in `macOS/Tests/TextReplacementCoreTests/ApplePlistCodecTests.swift`. Those files are useful for understanding intended usage, invariants, and recent architectural decisions without reading every source file front to back.

---
_Generated by ask-self ingest at 2026-06-22T05:40:46+00:00 using deterministic-fallback. Embed model: gemini-embedding-001 (dim=768). Indexed chunks: 182._

_Chunks by source: module=77, script=52, doc=47, policy=23, test=2, config=2, overview=1._
