# Text Replacement Studio

A starter Swift package for a better macOS Text Replacement manager.

This skeleton contains:

- `TextReplacementCore`: models, validation types, import/export protocols, storage protocols, and placeholder service implementations.
- `TextReplacementStudio`: a minimal SwiftUI macOS app shell.
- `trstudio`: a Swift ArgumentParser-based CLI shell.

The intended architecture is protocol-first. The GRDB-backed local SQLite store and Apple plist import/export engine can be implemented behind the interfaces in `TextReplacementCore`.

## Build

```bash
swift build
```

## Run the CLI

```bash
swift run trstudio list
swift run trstudio lint
swift run trstudio export --format apple-plist --output ./TextReplacements.plist
```

## Run the SwiftUI shell

```bash
swift run TextReplacementStudio
```

This SwiftPM executable is a development shell, not a packaged `.app` bundle. For distribution, create an Xcode macOS app target that depends on `TextReplacementCore`.
