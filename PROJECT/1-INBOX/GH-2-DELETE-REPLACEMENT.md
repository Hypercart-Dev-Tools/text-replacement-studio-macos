---
title: Delete/remove replacement in the macOS app
status: Proposed (1-INBOX — not yet active)
created: 2026-08-10
owner: noelsaw1
gh_issue: 2
source: https://github.com/Hypercart-Dev-Tools/text-replacement-studio-macos/issues/2
doc_type: feature
complexity: 4
risk: 4
effort: 4
phases: 4
ratings_provisional: true
non_goals:
  - A general undo/redo history stack (NOT the same as cancelling a still-pending delete, which IS in scope — see gotcha 11)
  - Bulk multi-select delete
  - Hard-deleting rows from Apple's DB — soft-delete/tombstone only. Where the schema cannot express a tombstone, targeted deletion ABORTS rather than falling back to SQL DELETE (see gotcha 13)
  - Deleting from the Preview Plan sheet (it stays a read-only review surface)
related:
  - PROJECT/2-WORKING/MCP-CRUD-BRIDGE.md
goal: >
  A delete affordance in the Studio list that actually removes the shortcut from the live macOS
  database on Apply, with a confirmation naming what will be removed, and without the
  Merge-strategy no-op or the silent Disable+Replace deletion that both exist today.
---

# GH-2 — Delete/remove replacement in the macOS app

> **1-INBOX capture**, not the active-work doc — no `## Status` table yet. On promotion to
> `PROJECT/2-WORKING/`, add the status table + per-phase QA gates and carry `gh_issue` forward
> (`PROJECT/PDDA.md` → GitHub issue intake).

## Key concepts

- The Studio app can add and edit replacements but cannot remove one. `StudioModel` has
  `addReplacement` and `toggleEnabled` and no removal function; `ReplacementListView` has no
  `.onDelete`, `contextMenu`, `swipeActions`, or ⌫ handler.
- **The diff plumbing already exists and is unreachable.** `StudioModel.planDiff` computes a
  `removes` set, and `PreviewPlanSheet` renders a red "Removed" section plus a "Deletions are
  ignored under Merge" hint. Both are permanently empty, because nothing can take a row out of
  `replacements`. This work lights up existing dead UI rather than adding new plumbing.
- **The layer below already deletes.** `scripts/json_to_apple_sqlite.py` soft-deletes
  (`ZWASDELETED = 1`) any shortcut missing from the JSON under `--strategy replace`, and the
  `trstudio` CLI exposes `--strategy`. Deletion works from the command line today; only the GUI
  lacks it.
- The hard part is not the button. It is that **Merge — the default strategy — has no way to
  express "remove this one row"**, so a naive delete affordance would ship visibly broken.

## Idea

Add a delete/remove replacement feature to the Text Replacement Studio macOS app.

## Why

Deletion is the one missing letter of CRUD in the app, and its absence pushes users back to
System Settings or the CLI for a routine operation. Worse, the *only* way to delete from the GUI
today is an accident waiting to happen: toggle a row Disabled, switch to Replace, Apply — because
`replacements_common.preflight` drops disabled entries when `include_disabled` is false and the
app never passes it. That is silent data loss down a path nobody would guess, with no confirmation
naming what is about to be removed. Building a real delete is also the natural moment to close
that footgun.

## Known gotchas (found during capture)

Each of these was grounded in code read on 2026-08-10. They are recorded here so the plan does not
discover them mid-build and turn into a rabbit hole.

1. **Merge cannot express a deletion.** Delete locally + Apply under Merge writes nothing, and the
   row returns on the next Import. Replace *does* delete, but it removes everything missing from
   the list — too blunt for "remove this one shortcut", and dangerous if the in-memory library is
   ever incomplete. Probable resolution: give the writer a targeted delete list so Merge can carry
   specific removals. That is a `scripts/json_to_apple_sqlite.py` + `AppleDatabaseWriter` change,
   not just a UI change — **this is the phase most likely to be underestimated.**
2. **Disable + Replace + Apply already soft-deletes, silently.** Pre-existing; see Why above.
3. **Index-based mutation paths corrupt the wrong row — this is worse than a crash.**
   `stringBinding(_ index:)` captures an `Int`, while the `// MARK:` comment directly above claims
   "resolve the row by id each time". *(Sharpened after agy QA.)* The out-of-bounds crash is the
   **benign** case. The dangerous case: delete row 0, the array shrinks, and stale index 0 now
   addresses a **different row** — the write lands silently on the neighbour. For the content
   bindings that means the user's phrase or shortcut is overwritten with no error at all.
   `StudioModel.touch(_ index:)` (`macOS/Apps/TextReplacementStudio/StudioModel.swift:108-112`)
   shares the flaw and is *specifically* the benign-looking one: its `guard
   replacements.indices.contains(index)` prevents the crash and therefore guarantees the silent
   mis-stamp instead. **Note this API was introduced on 2026-08-11 by the timestamp-sidecar work
   (commit `dd5cdbc`), i.e. this plan's own recent groundwork added a delete-hostile path.**
   Phase 3 must migrate *every* mutation path to id resolution and delete the index-based `touch`
   overload rather than leaving it beside an id-based one.
4. **Selection behaviour on delete — INVERTED by gotcha 16.** *(Rewritten after agy round 2; the
   original text here prescribed dead work.)* The original concern was a dangling
   `selectedReplacementID` pointing at a removed row. Under the `isPendingDeletion` design the row
   **stays in the array**, so the selection remains valid and must **not** move on a local delete.
   The detail pane instead renders the selected row read-only with a Restore control. Selection only
   needs to move when Apply actually clears the pending set and the rows really leave the array.
5. **Tombstone re-add path.** Re-adding a previously deleted shortcut inserts a new row while the
   tombstone persists — the writer's UPDATE scopes to active rows only. Confirm this cannot
   produce a duplicate active/tombstone shortcut pair. *(Narrowed after agy QA: the `ZUNIQUENAME`
   half of this was wrong. A collision is impossible by construction — the writer mints a fresh
   `str(uuid.uuid4()).upper()` for every insert at `scripts/json_to_apple_sqlite.py:185-186`. Only
   the duplicate-shortcut concern survives.)*
6. **iCloud resurrection.** A soft-delete must reach CloudKit (`ZNEEDSSAVETOCLOUD = 1`) or another
   synced device will push the row straight back.
7. **Timestamp sidecar.** `ReplacementTimestampStore.record()` deliberately does not prune, so a
   deleted shortcut's entry lingers until the next `reconcile`. Harmless but worth an explicit
   decision.
8. **Identity is shortcut-keyed all the way down, and JSON ids are discarded.** *(Corrected after
   Codex QA — the original claim, that duplicate shortcuts reach Swift, is wrong:
   `scripts/native_to_json.py:47-57` dedupes them at export.)* The real problem is transport. The
   writer never reads the JSON `id`; it collapses active rows by shortcut
   (`scripts/json_to_apple_sqlite.py:200-206`) and its delete branch fires
   `WHERE ZSHORTCUT = ?` with **no active-row scoping** — unlike the update branch, which appends
   `AND COALESCE(ZWASDELETED,0) = 0`. So a delete hits every matching row including tombstones.
   Must decide: does deleting a conflicted shortcut mean all active matches, or a fail-closed error?

### Added after Codex QA (2026-08-10)

9. **You cannot delete your last replacement.** `StudioModel.pushToMacOS` opens with
   `guard !replacements.isEmpty`, and `ContentView.canApply` requires a non-empty library. Empty out
   the list and Apply silently does nothing. Needs an "imported and intentionally empty" flag
   distinct from `replacements.isEmpty`.
10. **Shortcut rename silently duplicates.** The UI diff is id-based, so renaming a shortcut reads as
    an *update*; the writer keys by shortcut, so it **adds the new one and leaves the old behind**.
    Rename must be modelled as delete-old + add-new, or it quietly doubles the row.
11. **No pending-deletion state machine.** Undefined today: deleting a never-applied new row (should
    be a pure local discard, never reaching the writer), deleting then re-adding the same shortcut
    before Apply, and several deletes queued together. A pending delete must also be cancellable
    before Apply — that is *not* the undo stack deferred in `non_goals`.

    **Lifecycle transitions** *(added round 2)* — the pending set and the imported baseline must have
    defined behaviour at all three exits, or the two drift apart:
    - **Apply succeeds** → clear the pending targets and refresh `importedBaseline` to what was written.
    - **Apply fails / transaction rolls back** → retain the pending targets and do **not** advance any
      local baseline state; the user must be able to retry or cancel from the same position.
    - **Import while deletes are pending** → requires an explicit discard-or-reconcile decision, never
      a silent overwrite (today's Import unconditionally clobbers both arrays).
12. **No fail-closed schema gate, no optimistic concurrency, and `Z_OPT` never advances.** Column
    validation requires only `ZSHORTCUT`/`ZPHRASE` (`scripts/json_to_apple_sqlite.py:88-92`), so a
    delete can run against a table with no `ZWASDELETED`/`ZNEEDSSAVETOCLOUD`. Update and delete
    mutations never bump Core Data's `Z_OPT` version. And confirmation is computed from the
    *imported baseline* while Apply re-reads and mutates whatever is there now — nothing checks the
    target is unchanged since import, so the user can confirm removing one row and remove a
    different one.
13. **The "soft-delete only" non-goal is not actually enforced.** When `ZWASDELETED` is absent the
    writer falls through to a real `DELETE FROM` (`scripts/json_to_apple_sqlite.py:335-337`),
    contradicting the stated boundary and freeing a `Z_PK`. Targeted deletion must abort instead.


### Added after agy QA (2026-08-11) — second, independent review

14. **`planDiff` hard-gates removals on the Replace strategy, so Preview would lie about targeted
    deletes.** `let removes = strategy == .replace ? … : []`
    (`macOS/Apps/TextReplacementStudio/StudioModel.swift:217-220`). The moment Merge can carry a
    targeted deletion, this line makes the Preview Plan sheet show **zero** removals and keep
    displaying its "Deletions are ignored under Merge" hint — directly contradicting the goal of a
    confirmation that names what will be removed.
    **Un-gating that line is necessary but NOT sufficient** *(agy round 2)*: `removes` is derived
    from baseline ids missing out of `currentIDs`, and a pending-deleted row is still in
    `replacements`, so its id is never missing — it would silently fall through into the `updates`
    bucket instead. Phase 2 must compute `removes` from `replacements.filter(\.isPendingDeletion)`
    (union the missing-id set under `.replace`) **and** exclude pending rows from `updates` and
    `unchanged`.
15. **The transport has no channel for "what was deleted".** `AppleDatabaseWriter` serializes only
    the current `replacements` array
    (`macOS/Sources/TextReplacementCore/Integration/AppleDatabaseWriter.swift:62`), which is the
    *new* state. The Python side therefore cannot know a shortcut was renamed or removed — it can
    only infer absence, which is exactly the blunt Replace behaviour gotcha 1 rejects. Phase 2 must
    extend `CanonicalReplacementCodec` with an explicit `deletes` array carrying each target's
    before-fingerprint. **This is the concrete mechanism gotchas 1 and 10 both depend on**, and
    neither of them named it.
    *(agy round 2 — spell the synthesis out, or a builder will wire only the obvious half.)* The
    `deletes` array must be populated from **both**: (a) rows flagged `isPendingDeletion`, and
    (b) the **before** state of any active row whose `shortcut` differs from its `importedBaseline`
    entry — that second source is the only thing that makes a rename land as delete-old + add-new
    (gotcha 10), because the writer discards JSON ids (gotcha 8) and cannot detect a rename itself.
    Rows flagged `isPendingDeletion` must also be **excluded** from the active `items` array.
16. **Pending deletion must be a flag on the row, not removal from the array.** If a delete simply
    drops the row out of `replacements`, there is no longer any list item to hang a "Restore"
    control on — which forces exactly the general undo stack that `non_goals` defers. Model it
    instead as `isPendingDeletion` on the row: it stays in the array, renders struck-through in
    Phase 3, and cancel is a flag flip. This is the design decision that makes the
    cancel-in-scope / undo-deferred split in `non_goals` actually buildable.
## Anticipated phase shape

Named here for scoping only; the real per-phase plan and QA gates are written on promotion to
`2-WORKING`.

**Reordered after Codex QA.** The original plan put the UI first and safety last. That is backwards:
exposing local removal before deletion identity and the DB invariants exist means the UI ships on top
of undefined semantics. Foundation first, transport second, UI last.

- **Phase 0** — Explore & scope (this doc's checklist below)
- **Phase 1 — Semantics & invariants (no user-visible change).** Define deletion identity (gotchas 8,
  10); model pending deletion as an `isPendingDeletion` flag on the row rather than removal from the
  array, so cancel stays cheap and the deferred undo stack is not forced (gotcha 16); the
  pending-deletion state machine incl. cancel-before-Apply and delete-new-unsaved (11); the
  fail-closed schema gate, `Z_OPT` handling and optimistic-concurrency check (12); abort-not-hard-delete
  (13); disabled-row semantics (2); and the empty-library flag (9).
- **Phase 2 — Targeted-delete transport.** `AppleDatabaseWriter` → `json_to_apple_sqlite.py` carrying
  each target's expected baseline fingerprint, aborting the whole transaction on a missing, changed,
  or ambiguous target. Dry-run, Preview, confirmation and Apply must all consume **one** target set
  (gotchas 1, 5, 6). Concretely, this phase owns two changes neither the original plan nor the first
  review named: extending `CanonicalReplacementCodec` with an explicit `deletes` array so the wire
  format can express a removal at all (gotcha 15), and reworking `planDiff` so `removes` is driven
  by the `isPendingDeletion` flag rather than by `strategy == .replace` (gotcha 14 — note that
  merely deleting the strategy check is not enough; pending rows must also be kept out of `updates`
  and `unchanged`).
- **Phase 3 — UI affordances.** Local removal, context menu, ⌫ **scoped to list focus** so it cannot
  fire while the cursor is in the shortcut/phrase/search field, selection handling, the id-resolved
  binding fix — migrating *every* mutation path to id resolution and removing the index-based
  `touch(_ index:)` overload rather than leaving it alongside (gotcha 3) — a struck-through
  rendering for rows flagged `isPendingDeletion` with an inline Restore control, selection
  deliberately **not** moving on a local delete (gotcha 4), and a confirmation naming exactly what
  will be removed (gotchas 3, 4, 16). Also ships the
  **restore/cancel control for a still-pending deletion** — the affordance that makes the
  cancellation carve-out in `non_goals` real rather than theoretical (gotcha 11). Without a visible
  way to undo a pending delete before Apply, "cancellable" is a claim with no UI behind it.

## Phase 0 — Explore & scope

> Discovery phase: its findings are written **back into this doc** before its QA gate can pass
> (`PROJECT/PDDA.md` → Discovery & spike phases).

### Checklist

- [ ] Ground the idea in the real code/trace it touches (not the abstract)
- [ ] Name the concrete deliverable + its write-set (needed before it can be a marathon lane)
- [ ] Decide how a deletion reaches macOS under Merge — targeted delete list vs. forced Replace
      vs. blocking Apply (gotcha 1); this decision sets the whole shape of Phase 2
- [ ] ~~Confirm whether `ReplacementDetailEditor`'s index-based bindings are a real crash risk~~ —
      **resolved by Codex QA: confirmed real.** Every editor binding captures an unchecked array
      index despite the id-resolution comment
      (`macOS/Apps/TextReplacementStudio/Views/ReplacementDetailEditor.swift:227-270`); an AppKit
      control can call a stale setter while a deletion tears down or reorders the view. Convert to
      id-resolved bindings in Phase 3.
- [ ] Decide the delete-identity contract: shortcut + phrase/content fingerprint vs. native row
      identity, and whether an ambiguous target aborts (gotchas 8, 12)
- [ ] Write the acceptance tests Codex named: delete-last-row, shortcut-rename-as-delete+add,
      delete-then-re-add-before-Apply, changed-since-import conflict, constrained-schema fixture
      (no `ZWASDELETED`), and a manual synced-device resurrection check before release
- [ ] Add the three pending-set lifecycle cases (gotcha 11): Apply-succeeds clears + refreshes
      baseline, Apply-fails retains without advancing, Import-while-pending forces an explicit decision
- [ ] Prove a pending deletion can be restored from the UI before Apply

### Acceptance matrix — DB mutation invariants (Phase 2)

Cataloguing the hazards is not the same as proving the mutation is correct. A targeted delete must be
asserted against a SQLite fixture to do **exactly** this and nothing more:

| Invariant | Assertion |
|---|---|
| Tombstone set | `ZWASDELETED = 1` on the target |
| Cloud flag set | `ZNEEDSSAVETOCLOUD = 1` so the tombstone reaches CloudKit |
| Version advanced | `Z_OPT` advances per the Core Data rule resolved in Phase 1 |
| Blast radius | exactly **one** active expected row affected — no tombstones, no siblings |
| Identity preserved | the row's `Z_PK`, `ZUNIQUENAME` and `ZREMOTERECORDINFO` are unchanged |
| Allocation untouched | `Z_PRIMARYKEY.Z_MAX` does not move (a delete must never free a PK) |
| Timestamp | `ZTIMESTAMP` re-stamped — a delete *is* a change (cf. the GH-2-adjacent writer fix that stopped no-op rewrites destroying history) |

Note that `scripts/target_save_check.py:29-38`'s mock table does not enforce `ZUNIQUENAME` uniqueness;
the fixture should mirror the real schema's UNIQUE index as basic fidelity. *(Scoped down after agy QA:
the re-add **collision** case it was meant to prove is impossible by construction — every insert mints a
fresh `uuid.uuid4()`. Keep the constraint for schema fidelity, drop the collision test.)*
- [ ] Decide the tool shape — reuse an existing command/script before new infrastructure
      (`/ponytail`)
- [ ] Set/correct the triage ratings; clear `ratings_provisional` once real

### QA checklist — Phase 0

- [ ] The scope is grounded in real code/history, not a hypothetical
- [ ] Composes with existing commands rather than adding a parallel path
- [ ] A human checkpoint remains before anything fires
- [ ] Every gotcha above is either resolved, scheduled into a phase, or explicitly deferred with a
      reason — none left silently open
