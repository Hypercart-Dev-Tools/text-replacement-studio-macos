# CHANGELOG

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
