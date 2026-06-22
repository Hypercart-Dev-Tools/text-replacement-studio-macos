---
description: Refresh the ask-self RAG index for this repo, or install ask-self if not yet set up
argument-hint: "[--mode all|docs|code] [--no-prs] [...ingest flags]"
---

Run an ask-self (re)ingest of the current codebase to refresh the RAG index. If ask-self is
not yet wired into this repo, **install it first** (see the Install section below).

As of v0.5, the index is **revision-aware**: doc files ingest additively
(history is preserved across runs) and code files ingest in overwrite mode
(working tree wins). Re-ingesting an unchanged repo is a near-instant no-op —
the planner dedupes against the existing DB before calling the embedding API,
so unchanged chunks are never re-embedded. No flags are required to opt in;
the behavior is the default.

**First run after upgrading to v0.5:** the ingester will detect a pre-v2
index, print `[ask-self] Detected pre-v2 index at <path>; rebuilding...` to
stderr, and rebuild from scratch (one-time cost, matches today's behaviour).
Subsequent ingests run on the new schema and dedupe automatically.

**After a successful ingest, you can:**
- Inspect doc revision history: `ask-self history <path>` (e.g. `ask-self history README.md`).
- Query historical doc content: `ask-self ask "..." --doc-history` or `--as-of YYYY-MM-DD`.
- Prune accumulated history: `ask-self prune-history --older-than 90d` or `--keep-last K --per-path` (add `--dry-run` to preview).

## Step 1 — Detect installation status

Run the following script. It resolves the entry point and outputs a JSON status object.
It **never exits non-zero** so the result is always parseable:

```bash
set -e

# Resolve ASK_SELF_PATH using the canonical self-location order so we can
# surface it to the install path even when no wrapper exists yet.
resolve_ask_self_path() {
  if [ -n "$ASK_SELF_PATH" ]; then
    echo "$ASK_SELF_PATH"; return
  fi
  REPO_PARENT="$(cd "$(dirname "$(git rev-parse --git-dir 2>/dev/null || echo .)")" 2>/dev/null && pwd || pwd)"
  for candidate in \
    "$REPO_PARENT/../ask-self" \
    "$HOME/Documents/GitHub-Repos/ask-self" \
    "$HOME/Documents/GitHub/ask-self" \
    "$HOME/Documents/GH Repos/ask-self" \
    "$HOME/ask-self"; do
    if [ -f "$candidate/ask_self_ingest.py" ]; then
      echo "$candidate"; return
    fi
  done
  if command -v ask-self >/dev/null 2>&1; then
    dirname "$(command -v ask-self)"/..
    return
  fi
  echo ""
}

RESOLVED_ASK_SELF_PATH="$(resolve_ask_self_path)"

if [ -f scripts/ask-self-ingest.sh ]; then
  echo '{"installed":true,"layout":"wrapper"}'
elif [ -n "$RESOLVED_ASK_SELF_PATH" ] && [ -f ask_self/ask_self_harness.json ]; then
  echo "{\"installed\":true,\"layout\":\"external\",\"ask_self_path\":\"$RESOLVED_ASK_SELF_PATH\"}"
elif [ -f ask_self/ask_self_ingest.py ]; then
  echo '{"installed":true,"layout":"portable"}'
elif [ -f ask_self_ingest.py ]; then
  echo '{"installed":true,"layout":"self"}'
else
  echo "{\"installed\":false,\"ask_self_path\":\"$RESOLVED_ASK_SELF_PATH\"}"
fi
```

## Step 2 — Branch on the result

**If `"installed": true`**: skip to the **Ingest** section and run ingest.

**If `"installed": false`**: stop here and jump to the **Install** section instead.

---

## Ingest

The repo already has ask-self wired up. Run the detection-and-ingest script below.
It re-resolves the entry point (matching the layout reported above) and runs ingest
with `--json` so the result is machine-parseable:

```bash
set -e

# Default to --mode all unless the caller already passed --mode.
# An array, not a string: zsh does not word-split unquoted variables, so a
# "--mode all" string would reach the CLI as a single bogus argument.
MODE_ARGS=(--mode all)
case " $ARGUMENTS " in *" --mode "*) MODE_ARGS=() ;; esac

if [ -f scripts/ask-self-ingest.sh ]; then
  # 1. Integrated target repo: use the wrapper (invoked via bash so a
  #    missing executable bit on the wrapper does not break the command).
  bash scripts/ask-self-ingest.sh "${MODE_ARGS[@]}" --json $ARGUMENTS
elif [ -n "$ASK_SELF_PATH" ]; then
  # 2. External install located via ASK_SELF_PATH.
  if [ -f "$ASK_SELF_PATH/ask_self/ask_self_harness.json" ]; then
    HARNESS="$ASK_SELF_PATH/ask_self/ask_self_harness.json"
  else
    HARNESS="$ASK_SELF_PATH/ask_self_harness.json"
  fi
  if [ -n "$ASK_SELF_PYTHON" ]; then
    PY="$ASK_SELF_PYTHON"
  elif [ -x "$ASK_SELF_PATH/.venv/bin/python" ]; then
    PY="$ASK_SELF_PATH/.venv/bin/python"
  else
    PY="python3"
  fi
  "$PY" "$ASK_SELF_PATH/ask_self_ingest.py" --harness-config "$HARNESS" "${MODE_ARGS[@]}" --json $ARGUMENTS
elif [ -f ask_self/ask_self_ingest.py ]; then
  # 3. Portable-mode or vendored copy inside the target repo.
  if [ -x .venv/bin/python ]; then PY=.venv/bin/python; else PY=python3; fi
  "$PY" ask_self/ask_self_ingest.py --harness-config ask_self/ask_self_harness.json "${MODE_ARGS[@]}" --json $ARGUMENTS
elif [ -f ask_self_ingest.py ]; then
  # 4. The ask-self repo itself.
  if [ -x .venv/bin/python ]; then PY=.venv/bin/python; else PY=python3; fi
  "$PY" ask_self_ingest.py --harness-config ask_self_harness.json "${MODE_ARGS[@]}" --json $ARGUMENTS
else
  echo '{"ok":false,"error":"not_installed"}'
fi
```

After the script exits, parse the JSON and summarise:

- On success (`"ok": true`): report `total_chunks`, `db_path`, and `elapsed_seconds`.
  Also report the revision-aware counters from the `revisions` block when present:
  - `new` — new file revisions written (additive doc edits or new files)
  - `refreshed` — unchanged files whose `last_seen_at` was bumped
  - `chunks_embedded` vs `chunks_reused` — embedding cost vs cache reuse
  - `deleted_paths_swept` — overwrite paths removed from disk and pruned
  A second consecutive run on an unchanged repo should show `new: 0`, `chunks_embedded: 0`, and a large `refreshed` count. If those numbers don't match expectation, flag it (it usually means a noisy auto-generated doc is churning).
- On failure (`"ok": false`, or a non-zero exit): report the `error` field plus any warnings.

Do not modify any source files. Only run the ingest command.

---

## Install

ask-self is not yet wired into this repo. Set it up now by following the integration guide.

### 1. Locate the guide

Use the `ask_self_path` value from Step 1's JSON. If it is empty, ask-self is not installed
on this machine — tell the user to clone it and set up a venv first:

```
git clone https://github.com/Hypercart-Dev-Tools/ask-self.git ~/ask-self
cd ~/ask-self && python3 -m venv .venv && source .venv/bin/activate && pip install .
```

Then set `ASK_SELF_PATH=~/ask-self` and re-run `/reingest`.

### 2. Read the integration guide

Once `ask_self_path` is known, read the full guide:

```bash
cat "$ASK_SELF_PATH/ASK_SELF_INTEGRATION.md"
```

Read the entire file before taking any action.

### 3. Follow the guide

Work through the guide exactly as written. The key milestones in order:

1. **Pre-flight questions** — ask the user Q1 (embedding provider + synthesis), Q2 (index
   placement), and Q3 (PR ingestion) before creating any files. Do not skip or guess.
2. **Detection step** — inspect the target repo (ls, package.json, composer.json, etc.) and
   pick the right harness template.
3. **Create integration files** — `ask_self/ask_self_harness.json`,
   `ask_self/ask_self_system_instructions.json`, `scripts/ask-self-ingest.sh`,
   `scripts/ask-self-query.sh`, `.claude/commands/reingest.md`,
   `.claude/commands/ask_self.md`.
4. **Update `.gitignore`, README, and `AGENTS.md`** per the guide.
5. **Smoke test** — run `./scripts/ask-self-ingest.sh --mode all` and report the output.
6. **Validate `ARCHITECTURE.md`** against the checklist in the guide before declaring done.

Copy wrapper scripts verbatim from the external repo's `templates/` directory — do not
hand-write them. Copy the claude commands from `$ASK_SELF_PATH/.claude/commands/`.

Do not modify the external ask-self repo. All changes go in the target repo only.
