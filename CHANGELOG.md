# CHANGELOG

## 2026-08-11 (later)

- Added delete/remove replacement to the Studio app (GH-2). Deletion is **staged, not immediate**: a row is flagged `isPendingDeletion`, renders struck-through with a trash marker, and is only removed from macOS on Apply. Because the row stays in the array, Restore is a flag flip rather than an undo stack, and the selection never dangles. Delete via the row context menu or ⌫ (scoped to list focus so it cannot fire while you are typing in the phrase or search field); Restore from the context menu or the detail pane's banner.
- **Merge can now express a single deletion.** Previously the only way to remove anything was the Replace strategy, which sweeps everything absent from the submitted library — far too blunt for "remove this one shortcut", and the reason a naive delete button would have shipped broken. The canonical JSON gained a `deletes` array carrying each target's shortcut plus a fingerprint of the state we expect on disk, and `json_to_apple_sqlite.py` honours it under either strategy.
- Deletion is **fail-closed**. Targets are verified against the live database before any mutation, inside the existing `BEGIN IMMEDIATE`, so a bad target rolls back the adds and updates too. It aborts if the target is missing, if two active rows share the shortcut, if the row changed since the plan was computed (edited in System Settings or synced from another device), or if the schema has no `ZWASDELETED` column — in that last case the only available removal would be a hard `DELETE`, which frees a `Z_PK` and risks the sync daemon. The soft-delete addresses its row by `Z_PK`, sets `ZWASDELETED`/`ZNEEDSSAVETOCLOUD`/`ZTIMESTAMP`, bumps `Z_OPT`, and leaves `Z_PK`/`ZUNIQUENAME`/`ZREMOTERECORDINFO` intact so CloudKit keeps the row's identity.
- Renames are now transported as delete-old + add-new. The writer keys by shortcut and discards our ids, so a rename it was not told about read as an unrelated add and silently left the old row behind.
- Fixed the detail editor's bindings, which captured an array **index** while their own comment claimed id resolution. The out-of-bounds crash was the benign case: after a row is removed a stale index addresses a *different* row, so the write lands on the neighbour with no error. All bindings now resolve by id, and the index-based `touch(_ index:)` added earlier the same day was removed rather than left beside the id-based one.
- You can now delete your last replacement. Apply was gated on `!replacements.isEmpty`, which made an intentionally emptied library unappliable; it is now gated on whether an import has happened.
- Fixed `backup_database` colliding when two applies land in the same second — the directory stamp is second-granular and `mkdir()` had no collision handling, so the second apply failed outright. It now takes the next free suffix rather than reusing (and overwriting) the existing backup.
- Made delete actually findable. The first cut shipped only a right-click context menu, and the ⌫ handler was dead: it was gated on list focus, which was set by an `.onTapGesture` on the scroll view that each row's own tap handler swallowed first. There are now four routes to the same single action — a **Delete Replacement** button in the detail pane, a trash button in the list footer (which turns into Restore for a staged row), **Edit ▸ Delete Replacement (⌘⌫)**, and the ⌫ key, now that selecting a row also focuses the list.
- Verification: `swift test` 43/43 green across 6 suites, no warnings; the three new end-to-end delete tests run against a throwaway copy of the real database and were confirmed to exercise the abort paths. `make-app.sh` release build clean, signed, installed, and launched as a smoke test. Live database confirmed unmodified by the test run (no `zz_*` rows leaked out of the sandbox).

## 2026-08-11

- Fixed the "Recently Changed" filter, which could never report anything. It was a diff against an in-memory baseline that three separate paths reset — launch (import sets `replacements` and `importedBaseline` to the same array), Apply (re-baselines to the applied set), and the fact that nothing persisted at all. It is now a real rolling 7-day window over `updatedAt`, backed by a new `ReplacementTimestampStore` sidecar in Application Support. Every mutation routes through `StudioModel.touch(_:)` with a debounced write, and a **Date Modified** sort joins the footer menu.
- The sidecar keys entries by normalized shortcut rather than `Replacement.id`, because the importer derives ids as `uuid5(shortcut, phrase)` — a row's id changes the moment its phrase is edited. Each entry carries a content fingerprint of the last-known on-disk state, so an edit made outside the app (in System Settings) is correctly detected as a change while an abandoned in-app edit is not. First run seeds an existing library as `.distantPast`: inherited replacements are history, not changes.
- Fixed `json_to_apple_sqlite.py` destroying every row's `ZTIMESTAMP` on every apply. `apply_changes` ignored its own plan and issued an UPDATE for *every* desired shortcut, including the ones `plan_changes` had already classified as `skip` — so the dry-run reported `skip=N` while `--apply` rewrote all N rows, re-stamping `ZTIMESTAMP` and re-flagging `ZNEEDSSAVETOCLOUD` (forcing a full CloudKit re-upload each run). Extracted a shared `needs_update()` predicate that both the planner and the writer call, so the plan and the apply can no longer drift — that drift was the bug.
- Known data loss from the old behavior: a bulk rewrite on 2026-08-09 flattened all 128 live rows to one identical timestamp. `Z_PK` insertion order survived and remains a reliable recency proxy; the in-repo 2026-06-22 backup still holds 80 distinct real timestamps.
- Captured GH-2 (delete/remove replacement in the app) as a 1-INBOX plan doc, QA'd across two Codex relay rounds — see `PROJECT/1-INBOX/GH-2-DELETE-REPLACEMENT.md`.
- Verification: `swift test` 33/33 green across 5 suites, no warnings. The two new E2E tests were confirmed to fail with the writer fix disabled and pass with it restored. `make-app.sh` release build clean, ad-hoc signature OK, installed to `/Applications`. `pdda.sh roadmap-coverage` clean.

## 2026-07-21

- Normalized the Text Replacement Studio app icon's optical size: preserved the artwork while scaling its source canvas to 938px and centering it, so the visible icon fits within an 824px maximum footprint and no longer appears oversized beside neighboring macOS icons.

## 2026-07-19

- Promoted ⌘S (Apply to macOS) from a hidden background button to a real File menu item, so the shortcut is discoverable and works when the main window isn't the only focused surface. Replaces the `.saveItem` command group and drives the same confirmation dialog as the toolbar button via a new `applyToMacOS` focused value; a shared `canApply` predicate keeps the menu item and toolbar button enabled/disabled in lockstep.
- Verification: `macOS/make-app.sh` release build clean, ad-hoc signature OK, installed to `/Applications`.

## 2026-07-17

- Added sort-by-date-created and alphabetical sort to the Text Replacement Studio shortcuts list (GH-1): a `ReplacementSortOrder` (manual/dateCreated/alphabetical) wired into `StudioModel.filtered(_:search:)`, with a footer sort menu that shows the active mode and keeps the selected row in view across re-sorts. Default stays `.manual` so existing insertion-order behavior is unchanged.
- Verification: `swift build` clean; cross-model `/consult` review (Codex + agy) — no concurrency/binding issues found; confirmed the source Apple Text Replacements DB has no per-item creation-date field, so `.dateCreated` reflects true creation time only for shortcuts added in-app (accepted, not fixed — see `PROJECT/1-INBOX/GH-1-SORT-SHORTCUTS-LIST.md`).

## 2026-06-23

- Added the repo-local Claude skill at `.claude/skills/text-replacements/SKILL.md` for safe macOS text-replacement CRUD via fresh JSON export, lint, dry-run preview, and explicit apply.
- Kept the skill aligned to the current implementation by documenting `merge` for add/update, `replace` only for explicit deletes on a fresh full snapshot, and the current limitation that live apply persists `shortcut` and `phrase` rather than canonical metadata fields such as `enabled`, `group`, or `notes`.
- Added `ROADMAP.md` as the root pointer ledger and recorded the active skill-first CRUD effort there.
- Verification: no automated tests run in this iteration; change scope was repo documentation plus the skill file.
