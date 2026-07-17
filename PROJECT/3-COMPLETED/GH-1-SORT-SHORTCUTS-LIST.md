---
title: Sort-by-date-created and alphabetical sort for shortcuts list
status: Completed (3-COMPLETED)
created: 2026-07-16
updated: 2026-07-17
owner: noelsaw1
gh_issue: 1
source: https://github.com/Hypercart-Dev-Tools/text-replacement-studio-macos/issues/1
doc_type: bugfix
complexity: 1
risk: 1
effort: 1
phases: 1
ratings_provisional: false
non_goals:
  - Persisting the chosen sort order across app restarts (out of scope unless explored in Phase 0)
  - Multi-key/compound sorting (e.g. sort by group, then alphabetically)
---

# GH-1 — Sort-by-date-created and alphabetical sort for shortcuts list

## Status

| What was just completed | What's next |
|---|---|
| Shipped in commit `b98af47`: `ReplacementSortOrder` (manual/dateCreated/alphabetical) wired into `StudioModel.filtered(_:search:)`, a footer sort menu showing the active mode, and scroll-to-selection across re-sorts. Reviewed via cross-model `/consult` (Codex + agy); `swift build` clean; rebuilt and installed to `/Applications`; committed and pushed to `origin/main`. | Nothing outstanding — closed. `.dateCreated` reflects true creation time only for shortcuts added in-app (the source Apple DB has no per-item creation-date field for imported rows); accepted as-is per operator decision, see Known limitation below. |

## Known limitation (accepted, not a bug)

The live macOS Text Replacements database has no per-item creation-date field (verified by
reading `scripts/native_to_json.py` — it extracts only `shortcut`/`phrase`). So `.dateCreated`
sort reflects true creation time only for shortcuts added in-app via the ＋ button; imported
shortcuts all get a synthetic timestamp from import/decode time. The operator chose to ship
as-is rather than rename the option or hold the sort mode back.

## Key concepts
- Two new sort modes for the shortcuts list: by `createdAt` (newest/oldest) and alphabetical by `shortcut` trigger string.
- Both fields already exist on `Replacement` (`macOS/Sources/TextReplacementCore/Models/Replacement.swift:3-11`) — no persistence-layer changes required.
- The list currently has zero sort logic — `StudioModel.filtered(_:search:)` only filters, never sorts (plain array/insertion order).

## Idea
Add sort by date created and alphabetical order buttons for the list of keyboard shortcuts.

## Why
The shortcuts list renders in insertion order with no way to reorder it. As the list grows, users have no fast way to find a recently-added shortcut or scan alphabetically. This is a small, self-contained UI + sort-logic addition.

## Phase 0 — Explore & scope
> Discovery phase: its findings are written **back into this doc** before its QA gate can pass
> (`PROJECT/PDDA.md` → Discovery & spike phases).

### Checklist
- [x] Ground the idea in the real code/trace it touches (not the abstract)
- [x] Name the concrete deliverable + its write-set (`StudioModel.swift`, `ReplacementListView.swift`, new `ReplacementSortOrder.swift`)
- [x] Decide the tool shape — reused the existing `Replacement.createdAt`/`shortcut` fields and the repo's Menu/Picker convention, no new infrastructure
- [x] Set/correct the triage ratings; cleared `ratings_provisional` — confirmed accurate (complexity/risk/effort 1/1/1, 1 phase)

### QA checklist — Phase 0
- [x] The scope is grounded in real code/history, not a hypothetical
- [x] Composes with existing commands rather than adding a parallel path
- [x] A human checkpoint remains before anything fires — operator confirmed the capture bundle and the Date Created data-provenance tradeoff before shipping
