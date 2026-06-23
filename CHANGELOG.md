# CHANGELOG

## 2026-06-23

- Added the repo-local Claude skill at `.claude/skills/text-replacements/SKILL.md` for safe macOS text-replacement CRUD via fresh JSON export, lint, dry-run preview, and explicit apply.
- Kept the skill aligned to the current implementation by documenting `merge` for add/update, `replace` only for explicit deletes on a fresh full snapshot, and the current limitation that live apply persists `shortcut` and `phrase` rather than canonical metadata fields such as `enabled`, `group`, or `notes`.
- Added `ROADMAP.md` as the root pointer ledger and recorded the active skill-first CRUD effort there.
- Verification: no automated tests run in this iteration; change scope was repo documentation plus the skill file.
