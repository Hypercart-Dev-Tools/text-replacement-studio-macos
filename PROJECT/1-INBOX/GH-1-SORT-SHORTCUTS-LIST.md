---
title: Sort-by-date-created and alphabetical sort for shortcuts list
status: Proposed (1-INBOX — not yet active)
created: 2026-07-16
owner: noelsaw1
gh_issue: 1
source: https://github.com/Hypercart-Dev-Tools/text-replacement-studio-macos/issues/1
doc_type: bugfix
complexity: 1
risk: 1
effort: 1
phases: 1
ratings_provisional: true
non_goals:
  - Persisting the chosen sort order across app restarts (out of scope unless explored in Phase 0)
  - Multi-key/compound sorting (e.g. sort by group, then alphabetically)
---

# GH-1 — Sort-by-date-created and alphabetical sort for shortcuts list

> **1-INBOX capture**, not the active-work doc — no `## Status` table yet. On promotion to
> `PROJECT/2-WORKING/`, add the status table + per-phase QA gates and carry `gh_issue` forward
> (`PROJECT/PDDA.md` → GitHub issue intake).

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
- [ ] Ground the idea in the real code/trace it touches (not the abstract)
- [ ] Name the concrete deliverable + its write-set (needed before it can be a marathon lane)
- [ ] Decide the tool shape — reuse an existing command/script before new infrastructure (`/ponytail`)
- [ ] Set/correct the triage ratings; clear `ratings_provisional` once real

### QA checklist — Phase 0
- [ ] The scope is grounded in real code/history, not a hypothetical
- [ ] Composes with existing commands rather than adding a parallel path
- [ ] A human checkpoint remains before anything fires
