<!-- ask_self:managed architecture_doc_v1 -->

# Fast Key Replacement (macOS) — Architecture Overview

Tools for working with Apple's text-replacement data on macOS:

## Repo stats (approximate)
- Files indexed in repo: ~62
- Total lines of code: ~5,160
- By language:
  - Markdown: 11 files, 1,964 LOC
  - Other: 33 files, 1,365 LOC
  - Shell: 10 files, 950 LOC
  - Python: 7 files, 871 LOC
  - JSON: 1 files, 10 LOC
- Git: branch `main` at `e744b69`

## Top-level layout
- `PROJECT/` (~2 files)
- `fkr/` (~1 files)
- `macOS/` (~31 files)
- `references/` (~1 files)
- `scripts/` (~9 files)
- `utils/` (~8 files)

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

### Source: policy
- `ARCHITECTURE.md` (priority 5, 29 chunks)
- `fkr/SKILL.md` (priority 5, 13 chunks)
- `AGENTS.md` (priority 5, 4 chunks)
- `macOS/README.md` (priority 5, 4 chunks)
- `README.md` (priority 5, 2 chunks)

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
- Generated at: `2026-06-22T05:49:37+00:00`
- Generated from commit: `e744b69`
- Current HEAD at ingest: `e744b69`
- Working tree at ingest: dirty (13 files)
- This document should be considered stale once the repo moves to a different HEAD or the working tree changes materially.

## How it fits together
The repository provides tools for managing macOS text replacements through two parallel toolchains: a Swift package in `macOS/` and a set of Python utilities in `scripts/`. The Python scripts handle direct SQLite interactions and format conversions (JSON, Markdown, plist), while the Swift package provides a protocol-first foundation for a CLI and a SwiftUI app.

Within the Swift package, the domain logic resides in `TextReplacementCore`. Data is represented by `Replacement.swift` and `AppleTextReplacementItem.swift`, with modifications tracked via `ReplacementChange.swift`. Format conversions are handled by specific codecs like `ApplePlistCodec.swift` and `JSONReplacementCodec.swift`, which implement the protocols defined in `ImportExport.swift`.

The `DefaultReplacementImportExportRegistry.swift` acts as the central registry for these codecs, wiring together the import/export engine. This core library is consumed by `macOS/Sources/TextReplacementCLI/main.swift`, which uses `ArgumentParser` to expose the functionality as a command-line tool, alongside the `TextReplacementStudio` SwiftUI app shell.

Finally, `fkr/SKILL.md` defines a Claude Code skill that exposes these terminal workflows to AI agents, enabling automated exporting, converting, and linting of replacements using the underlying Python and Swift tools.

---
_Generated by ask-self ingest at 2026-06-22T05:49:37+00:00 using gemini-pro-latest (compact retry). Embed model: gemini-embedding-001 (dim=768). Indexed chunks: 211._

_Chunks by source: module=77, script=52, policy=52, doc=47, test=2, config=2, overview=1._
