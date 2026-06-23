---
title: Claude Code CRUD for Text Replacement Studio (Skill-first)
status: Proposed (1-INBOX — not yet active)
doc_type: project
created: 2026-06-23
updated: 2026-06-23
owner: noel
goal: >
  Let Claude Code Create/Read/Update/Delete macOS text replacements with zero new
  runtime code, by shipping a Skill that drives the existing trstudio CLI + Python
  scripts. The MCP server / adapter / HTTP API stack is deferred until a non-shell
  MCP client actually needs it.
related:
  - macOS/Sources/TextReplacementCLI
  - macOS/Sources/TextReplacementCore
  - scripts/native_to_json.py
  - scripts/json_to_apple_sqlite.py
  - scripts/lint_replacements.py
  - AGENTS.md
  - PROJECT/PDDA.md
non_goals:
  - New runtime services (HTTP server, MCP server) for the Claude Code use case
  - Re-porting the Apple Core Data write logic out of the Python scripts
  - Remote/networked access
---

# Claude Code CRUD for Text Replacement Studio (Skill-first)

> **Lifecycle note.** Proposal in `PROJECT/1-INBOX`, so per `PROJECT/PDDA.md` it carries
> **no `## Status` table** yet. On promotion to `PROJECT/2-WORKING/` add: the exact status
> table, the Phase 0 QA-gate sign-off, and a one-line `ROADMAP.md` pointer. See the
> **Promotion checklist** at the end.

## 1. Summary

Claude Code can already run shells and edit files, and `trstudio` already ships
`list / add / import / export / apply / lint / backup` (apply does preview + a timestamped
backup via the reviewed `scripts/json_to_apple_sqlite.py`). So the shippable deliverable is
**one Skill file** that teaches Claude the safe CRUD recipe over those existing tools —
**no new runtime code**.

The MCP server, adapter, and HTTP API from the earlier draft are kept, but **demoted to
future possibilities** (Section 4): they only earn their place if an MCP client that *can't
run a local shell* (Claude Desktop, the web app, ChatGPT) needs CRUD access.

## 2. Why / use cases

- "Add a `/sig` snippet with my signature." → create, preview, apply.
- "Update every replacement pointing at the old Zoom link." → read, edit, apply.
- "Disable my casual `brb`/`omw` snippets." → update `enabled`.
- "What duplicate shortcuts do I have?" → read + lint.

## 3. Phase 0 — Claude Code Skill (ship this)

The whole feature is: operate on a **throwaway JSON snapshot** and promote it with the
existing apply script. The live macOS DB stays the only *persistent* store, so there is no
dual-write authority problem. One window remains — a **stale snapshot**: edits made in
System Settings or another app *after* the export can be clobbered on apply (worst under
`replace`). Sections 3.2–3.3 keep that window closed; it is reduced, not pretended away.

### 3.1 What already exists (reuse, write nothing)

- `trstudio` subcommands: `list`, `add`, `import`, `export`, `apply`, `lint`, `backup`
  (`macOS/Sources/TextReplacementCLI/main.swift`).
- `scripts/native_to_json.py` — live DB → canonical JSON (read-only).
- `scripts/json_to_apple_sqlite.py` — canonical JSON → live DB; dry-run by default,
  `--apply` writes after a timestamped backup; `--strategy merge|replace`.
- `scripts/lint_replacements.py` / `trstudio lint` — validation.

### 3.2 The recipe the Skill documents

One canonical setup, reused verbatim in every command (no `<db>` placeholders, no ad-hoc
filenames):

```text
DB=~/Library/KeyboardServices/TextReplacements.db
SNAP=.tmp/repl.json     # repo-local, disposable, OVERWRITTEN by a fresh export each run
```

Always start from a **fresh full export** — the snapshot must mirror the whole DB, because a
`replace` apply deletes everything missing from it:

```text
python3 scripts/native_to_json.py --db "$DB" -o "$SNAP"
```

**Create / Update — additive, use `merge`:**

```text
edit "$SNAP"                                                                  # add an item, or change shortcut/phrase/enabled/group/notes
python3 scripts/lint_replacements.py "$SNAP"
python3 scripts/json_to_apple_sqlite.py "$SNAP" --db "$DB" --strategy merge           # preview (no --apply)
python3 scripts/json_to_apple_sqlite.py "$SNAP" --db "$DB" --strategy merge --apply   # write (backup first)
```

**Delete — requires `replace` on a fresh full snapshot:**

```text
# re-export $SNAP first (above) so it is the CURRENT full DB, then remove only the target item(s)
edit "$SNAP"                                                                    # drop the item(s) to delete
python3 scripts/lint_replacements.py "$SNAP"
python3 scripts/json_to_apple_sqlite.py "$SNAP" --db "$DB" --strategy replace          # preview the deletions
python3 scripts/json_to_apple_sqlite.py "$SNAP" --db "$DB" --strategy replace --apply  # write (backup first)
```

> **⚠️ `replace` deletes every shortcut absent from `$SNAP`.** Only ever run it on a
> just-exported *full* snapshot with exactly the intended item(s) removed — never on a
> partial file. `merge` never deletes; prefer it for everything except an explicit delete.

`merge` adds/updates; `replace` also deletes. The canonical `keyboard-replacements.v1` shape
and field names come from
`macOS/Sources/TextReplacementCore/Codecs/CanonicalReplacementCodec.swift`.

### 3.3 The deliverable

`.claude/skills/text-replacements/SKILL.md`, with:

- **Frontmatter:** name + description with trigger hints ("manage my mac text
  replacements / snippets / autocorrect", "add a text expansion", "fix my signature
  snippet").
- **Workflow:** read → edit JSON → **lint → preview → apply**, explaining `merge` vs
  `replace` and the "quit & reopen apps to see changes" caveat.
- **Safety rules (non-negotiable, this is the trust boundary to the live DB):**
  - always `lint` before apply; never apply data with `error`-severity issues (blank
    shortcut/phrase, duplicate shortcut);
  - always run the dry-run **preview** and show the diff before `--apply`;
  - apply writes a backup first (the script does this) — never bypass it;
  - **re-export + re-lint `$SNAP` immediately before apply** if it is more than a few minutes
    old or you are using `replace` — the live DB may have changed (System Settings / another
    app) and apply would clobber it;
  - don't edit replacements in System Settings or start a second apply while a run is in flight;
  - never apply without the user's explicit intent.

### 3.4 QA gate (Phase 0)

- A scripted read → edit (add/update/delete one shortcut each) → lint → preview → apply
  cycle runs against a **temporary copy** of the DB (reuse the gated-e2e pattern already in
  `macOS/Tests/`), asserting the change shows up on re-read and a backup exists.
- The Skill triggers on a representative prompt and, in a dry-run transcript, previews
  before applying and refuses linter-flagged data.

## 4. Future possibilities (deferred — do not build yet)

**Trigger to revisit:** a non-shell MCP client (Claude Desktop, web app, ChatGPT) needs to
CRUD replacements, or multiple clients need a shared, concurrent store. Until then these are
speculative and intentionally unbuilt.

- **A. API endpoint** — `trstudio serve`: a loopback HTTP service over `TextReplacementCore`
  (CRUD + `validate`/`import`/`preview`/`apply`), `127.0.0.1` + bearer-token. Introduces a
  persistent working store and, with it, the authority/concurrency question below.
- **B. Adapter** — a transport-agnostic typed client between the MCP server and the API (a
  seam worth nothing until there is a second transport).
- **C. MCP server** — stdio tools over the adapter for non-shell clients.
- **D. GUI ↔ store reconciliation** — point `StudioModel` at the shared store so the app and
  the bridge stay in sync.

**Authority note (only relevant to A–D).** A persistent API store becomes a *dual-written
peer* against the live DB (the system of record), reintroducing a concurrency problem that
Phase 0 avoids entirely by working on a throwaway snapshot. Classify and design for it
*before* building A.

## 5. Risks & open questions

- **Phase 0:** `trstudio` has `add` but not dedicated `update`/`delete` subcommands — the
  recipe leans on JSON editing for those. Optional ergonomic add-on: 2–3 small subcommands
  (`update`, `delete`, `disable`) reusing `TextReplacementCore`. Not required to ship.
- **`replace` strategy is destructive** (deletes shortcuts missing from the JSON) — the
  Skill must steer to `merge` unless deletion is explicitly intended, and run `replace` only
  on a fresh full snapshot (§3.2).
- **Stale snapshot:** the export is point-in-time; concurrent edits in System Settings /
  another app between export and apply can be lost (worst under `replace`). Mitigated by
  re-exporting right before apply and not editing concurrently (§3.3) — reduced, not eliminated.
- **Future A–D:** server lifecycle, HTTP dependency, MCP language, auth sufficiency,
  store-vs-GUI concurrency — all deferred with the stack.

## 6. Verification

- `swift test` (incl. the gated Python e2e) stays green.
- From Claude Code: "add a `/sig` snippet … then apply it" yields a previewed diff, a
  backup on disk, and the shortcut present on re-read.

## 7. Promotion checklist (1-INBOX → 2-WORKING)

- [ ] Move to `PROJECT/2-WORKING/MCP-CRUD-BRIDGE.md`.
- [ ] Add the exact `## Status` table (`What was just completed | What's next`).
- [ ] Create `ROADMAP.md` (pointer ledger) and add a one-line pointer.
- [ ] Keep the Phase 0 QA gate; check it off when the Skill ships.
- [ ] Add a `CHANGELOG.md` entry.
- [ ] Run `utils/pdda-run.sh` and clear deterministic findings.
