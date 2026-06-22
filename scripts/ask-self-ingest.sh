#!/usr/bin/env bash
# ask-self ingest wrapper (portable mode) — (re)build THIS repo's committed RAG
# index at ask_self/index/fast-key-replacement-macos.sqlite.
#
#   ./scripts/ask-self-ingest.sh [--mode all|code|docs] [extra flags]
#
# Self-locates the external ask-self checkout (same resolution order as
# ask-self-query.sh) — no per-machine absolute path is baked in. Override:
#   ASK_SELF_PATH=/path/to/ask-self ./scripts/ask-self-ingest.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- Resolve the ask-self checkout (no hardcoded absolute path) ---------------
if [ -z "${ASK_SELF_PATH:-}" ]; then
  for _candidate in \
    "$REPO_ROOT/../ask-self" \
    "$HOME/Documents/GitHub-Repos/ask-self" \
    "$HOME/Documents/GitHub/ask-self" \
    "$HOME/Documents/GH Repos/ask-self" \
    "$HOME/ask-self"; do
    if [ -f "$_candidate/ask_self_query.py" ]; then
      ASK_SELF_PATH="$(cd "$_candidate" && pwd)"
      break
    fi
  done
fi
if [ -z "${ASK_SELF_PATH:-}" ] && command -v ask-self >/dev/null 2>&1; then
  _bin="$(command -v ask-self)"
  _root="$(cd "$(dirname "$_bin")/.." && pwd)"
  if [ -f "$_root/ask_self_query.py" ]; then
    ASK_SELF_PATH="$_root"
  fi
fi
if [ -z "${ASK_SELF_PATH:-}" ]; then
  echo "ask-self: could not locate your ask-self checkout." >&2
  echo "  Set ASK_SELF_PATH, e.g.: export ASK_SELF_PATH=\"\$HOME/Documents/GH Repos/ask-self\"" >&2
  exit 1
fi
# -----------------------------------------------------------------------------

HARNESS_CONFIG="$REPO_ROOT/ask_self/ask_self_harness.json"
ENTRYPOINT="$ASK_SELF_PATH/ask_self_ingest.py"
PORTABLE_DB="$REPO_ROOT/ask_self/index/fast-key-replacement-macos.sqlite"

if [ ! -d "$ASK_SELF_PATH" ]; then
  echo "ask-self: ASK_SELF_PATH does not exist: $ASK_SELF_PATH" >&2
  exit 1
fi
if [ ! -f "$ENTRYPOINT" ]; then
  echo "ask-self: ingest entry point missing: $ENTRYPOINT" >&2
  exit 1
fi
if [ ! -f "$HARNESS_CONFIG" ]; then
  echo "ask-self: local harness missing: $HARNESS_CONFIG" >&2
  exit 1
fi

if [ -n "${ASK_SELF_PYTHON:-}" ]; then
  PYTHON_BIN="$ASK_SELF_PYTHON"
elif [ -x "$ASK_SELF_PATH/.venv/bin/python" ]; then
  PYTHON_BIN="$ASK_SELF_PATH/.venv/bin/python"
else
  PYTHON_BIN="python3"
fi

# --- Gemini key via Google Secret Manager (repo-specific) ---------------------
# ask-self's credential resolver checks GOOGLE_API_KEY, then GOOGLE_API_KEY_FILE,
# then GOOGLE_API_KEY_SECRET_NAME (resolved through gcloud). Default the secret
# reference so ingest works in any shell — including VS Code agents that do not
# inherit a login shell. Override by exporting your own key/secret.
if [ -z "${GOOGLE_API_KEY:-}" ] && [ -z "${GOOGLE_API_KEY_FILE:-}" ]; then
  : "${GOOGLE_API_KEY_SECRET_NAME:=ltvera-gemini-api-key}"
  : "${GOOGLE_API_KEY_SECRET_PROJECT:=named-equator-493617-e5}"
  export GOOGLE_API_KEY_SECRET_NAME GOOGLE_API_KEY_SECRET_PROJECT
fi
# -----------------------------------------------------------------------------

mkdir -p "$REPO_ROOT/ask_self/index"

# Portable mode: write to the committed DB and never register it in the
# multi-repo registry. Default to a full code+docs ingest unless --mode is given.
BASE_ARGS=(--harness-config "$HARNESS_CONFIG" --db-path "$PORTABLE_DB" --no-register)
if [[ " $* " != *" --mode "* ]]; then
  BASE_ARGS+=(--mode all)
fi

cd "$REPO_ROOT"
exec "$PYTHON_BIN" "$ENTRYPOINT" "${BASE_ARGS[@]}" "$@"
