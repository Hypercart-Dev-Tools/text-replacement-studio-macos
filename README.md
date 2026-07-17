# Fast Key Replacement (macOS)

Tools for working with Apple's text-replacement data on macOS:

- **`macOS/`** — a Swift package: the `TextReplacementCore` library (codecs,
  importers/exporters, GRDB-backed storage, lint/merge services), a
  `TextReplacementCLI`, and the `TextReplacementStudio` SwiftUI app.
  See [macOS/README.md](macOS/README.md).
- **`scripts/`** — Python round-trip/conversion utilities between JSON, Markdown,
  the Apple SQLite store, and the native plist format.
- **`fkr/SKILL.md`** — the skill definition.

## Quick Start

Prerequisites: macOS 14+ and a Swift 6 toolchain (Xcode 16+) for the app; Python 3.9+ for the scripts.

```sh
# macOS app — build, bundle, and install Text Replacement Studio to /Applications
cd macOS && ./make-app.sh

# Python scripts — export your current macOS text replacements to JSON
python3 scripts/native_to_json.py --output replacements.json
```

## Copyright

Text Replacement Studio | Sponsored by MacNerd.xyz
© Copyright 2026 Neochrome, Inc.
GPL v2 License | Use as-is
