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

## Code Intelligence (ask-self) — optional, internal teammates

*Optional, and currently internal-only: querying or refreshing the index needs `gcloud`
access to a private GCP project (see **Credentials** below). You do not need ask-self to
build or use the tools above.*

This repo is indexed with [ask-self](https://github.com/Hypercart-Dev-Tools/ask-self),
an external, repo-grounded RAG tool. Ask grounded, citation-backed questions about
the codebase instead of grepping blind:

```sh
./scripts/ask-self-query.sh "how are Apple text replacements imported and persisted?"
```

Refresh the index after changes:

```sh
./scripts/ask-self-ingest.sh            # full code + docs ingest
```

**Index placement: portable.** The vector index is committed at
`ask_self/index/fast-key-replacement-macos.sqlite`, so a fresh clone can query
immediately — no ingest required first. The index reflects the **last ingest**,
not current uncommitted changes.

- **Last ingested:** 2026-06-21 @ `e744b69` (182 chunks, 4.0 MB index)

**Credentials.** Embeddings use Gemini (`gemini-embedding-001`). The wrapper
scripts resolve the API key from Google Secret Manager automatically
(`ltvera-gemini-api-key` in project `named-equator-493617-e5`) on any
`gcloud`-authenticated machine — so both querying and refreshing the index need
`gcloud auth login`. Override with `GOOGLE_API_KEY=...`, or point at a different
ask-self checkout with `ASK_SELF_PATH=/path/to/ask-self`.

> Because the index is committed and Gemini-embedded, the embeddings of indexed
> source travel with the repo (partially reconstructable) and the Gemini key is
> still required to query or refresh it. Review before making this repo public.
