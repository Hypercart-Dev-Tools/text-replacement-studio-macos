# AGENTS.md

Guidance for AI coding agents working in this repository.

## Repository overview

Fast Key Replacement (macOS) is a Swift package plus Python tooling for Apple
text-replacement data:

- `macOS/Sources/TextReplacementCore` — core library: codecs (Apple plist, JSON),
  importers/exporters, GRDB-backed storage, and lint/merge services.
- `macOS/Sources/TextReplacementCLI` — command-line entry point.
- `macOS/Apps/TextReplacementStudio` — SwiftUI app.
- `macOS/Tests` — XCTest suites.
- `scripts/*.py` — JSON ⇄ Markdown ⇄ Apple SQLite ⇄ native-plist conversion + linting.

## Code intelligence: query ask-self first

This repo is indexed with **ask-self**, an external, repo-grounded RAG tool.
**Before grep-spelunking or asking the user to re-explain repo context, query
ask-self first:**

```sh
./scripts/ask-self-query.sh "your question here"
```

**When to use it**
- Session-start orientation in an unfamiliar area of the codebase.
- Cross-file behavior questions ("how does the import → persist → export flow work?").
- Pronoun-heavy references ("that codec", "the merge engine", "the linter").

**When NOT to use it**
- Trivial single-file reads.
- Tight edit-test loops.
- Questions about current *uncommitted* state — the index reflects the last
  ingest, not your working tree.

**Refresh the index** after meaningful changes: `./scripts/ask-self-ingest.sh`.

**Staleness.** The committed portable index lags active branch work until
re-ingested. Override the ask-self checkout location with `ASK_SELF_PATH`.

### Gemini API key (ask-self)

The Gemini key lives in Google Secret Manager. The wrapper scripts default
`GOOGLE_API_KEY_SECRET_NAME=ltvera-gemini-api-key` and
`GOOGLE_API_KEY_SECRET_PROJECT=named-equator-493617-e5` automatically, so a
`gcloud`-authenticated machine needs no extra setup. If you invoke ask-self
outside the wrappers and `GOOGLE_API_KEY` is unset, resolve it first:

```sh
export GOOGLE_API_KEY=$(gcloud secrets versions access latest \
  --secret=ltvera-gemini-api-key \
  --project=named-equator-493617-e5)
```

Requires `gcloud` authenticated with an account that has
`Secret Manager Secret Accessor` on the project.
