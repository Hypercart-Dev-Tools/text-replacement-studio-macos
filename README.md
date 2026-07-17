# Fast Key Replacement (macOS)

Tools for working with Apple's text-replacement data on macOS:

- **`macOS/`** — a Swift package: the `TextReplacementCore` library (codecs,
  importers/exporters, GRDB-backed storage, lint/merge services), a
  `TextReplacementCLI`, and the `TextReplacementStudio` SwiftUI app.
  See [macOS/README.md](macOS/README.md).
- **`scripts/`** — Python round-trip/conversion utilities between JSON, Markdown,
  the Apple SQLite store, and the native plist format.
- **`web/`** — a tiny loopback-only local editor for the JSON (`python3 web/serve.py`).
- **`.claude/skills/text-replacements/`** — the live, auto-loaded Claude Code skill
  for CRUD on text replacements from a Claude Code session.
- **`fkr/SKILL.md`** — a standalone reference for the `scripts/*.py` CLI tools,
  for terminal use or manual driving from Claude Code (not auto-loaded — see above).

## Quick Start

Prerequisites: macOS 14+ and a Swift 6 toolchain (Xcode 16+) for the app; Python 3.9+ for the scripts.

```sh
# macOS app — build, bundle, and install Text Replacement Studio to /Applications
cd macOS && ./make-app.sh

# Python scripts — export your current macOS text replacements to JSON
python3 scripts/native_to_json.py --output replacements.json
```

**Verify it worked:** the app launches from `/Applications/Text Replacement Studio.app`
and lists your current replacements; `replacements.json` contains your exported entries.
Optionally run the test suite: `cd macOS && swift test`.

**Troubleshooting:**
- `swift build` fails with `fatal: cannot use bare repository … (safe.bareRepository is 'explicit')`
  or a similarly cryptic manifest error — see the note in [macOS/README.md](macOS/README.md#build--develop).
- Running under an AI coding agent, `swift build` fails with `error: 'macos': Invalid manifest`
  and `sandbox-exec: sandbox_apply: Operation not permitted` — this is the agent's own sandbox
  blocking SwiftPM's manifest-compilation sandbox, not a problem with the repo. The agent needs
  to run the build outside its sandbox.

## Copyright

Text Replacement Studio | Sponsored by MacNerd.xyz
© Copyright 2026 Neochrome, Inc.
GPL v2 License | Use as-is
