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

## Code intelligence: ask-self, if it's set up (optional)

This repo can optionally be indexed with **ask-self**, an external, repo-grounded
RAG tool — but the index is **not** committed here, so a fresh clone doesn't have
it. Only try this if you already have a working ask-self setup (a separate,
unvendored checkout, plus the credentials below); otherwise skip straight to
grep/read — don't block work on provisioning ask-self.

```sh
./scripts/ask-self-query.sh "your question here"
```

If that fails (missing checkout, missing index, no credentials), fall back to
normal grep-spelunking — that's the default path for anyone without ask-self
already configured, not a last resort.

**If you do have it working:**
- Good for session-start orientation, cross-file behavior questions, and
  pronoun-heavy references ("that codec", "the merge engine").
- Not useful for trivial single-file reads, tight edit-test loops, or questions
  about current *uncommitted* state (the index reflects the last ingest).
- Refresh after meaningful changes: `./scripts/ask-self-ingest.sh`.

### Gemini API key (ask-self)

Provisioning ask-self requires a Gemini API key. The wrapper scripts default
`GOOGLE_API_KEY_SECRET_NAME=ltvera-gemini-api-key` and
`GOOGLE_API_KEY_SECRET_PROJECT=named-equator-493617-e5`, resolved via Google
Secret Manager — this needs `gcloud` authenticated with an account that has
`Secret Manager Secret Accessor` on that specific private GCP project, which
most contributors won't have. Outside contributors should set `GOOGLE_API_KEY`
from their own key instead, or skip ask-self entirely.
