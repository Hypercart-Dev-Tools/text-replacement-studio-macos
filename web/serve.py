#!/usr/bin/env python3
"""Tiny local editor for the Keyboard Replacements JSON.

Loopback-only, stdlib-only, on-demand dev tool. Serves a one-page editor and
saves through the SAME preflight as the CLI (scripts/replacements_common), so
"clean up before saving" means exactly what it means everywhere else.

    python3 web/serve.py                                  # -> http://127.0.0.1:8768
    python3 web/serve.py --file temp/text-replacements.json --port 8768
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parent
REPO = ROOT.parent
sys.path.insert(0, str(REPO / "scripts"))
import replacements_common  # noqa: E402  (sibling module, resolved via the path insert above)

HTML = ROOT / "index.html"
WRITER = REPO / "scripts" / "json_to_apple_sqlite.py"
HOST = "127.0.0.1"
_save_lock = threading.RLock()  # serialize the whole read-modify-write (reentrant: _save re-takes it)


def _load(path: pathlib.Path) -> dict:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload.get("items"), list):
        raise ValueError("JSON must contain an items array")
    return payload


def _save(path: pathlib.Path, payload: dict, items: list[dict]):
    """check() -> only write when there are no errors. Backup + atomic replace.

    The server is threaded, so file mutations are serialized under a lock and the
    temp file is uniquely named — overlapping requests can't tear each other's write.
    """
    normalized, issues = replacements_common.check(items)
    if any(sev == "error" for sev, _ in issues):
        return None, issues
    out = dict(payload)
    out["items"] = normalized
    data = json.dumps(out, indent=2, ensure_ascii=False) + "\n"
    with _save_lock:
        shutil.copy2(path, path.with_name(path.name + ".bak"))  # last-known-good before overwrite
        fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=path.name + ".", suffix=".tmp")
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as handle:
                handle.write(data)
            os.replace(tmp, path)  # atomic
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    return out, issues


class Handler(BaseHTTPRequestHandler):
    file_path: pathlib.Path  # set on the class before serving

    def _json(self, code: int, obj) -> None:
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _is_local_origin(self) -> bool:
        """Reject cross-origin / DNS-rebinding POSTs to the mutating routes.

        A request from another website (or a rebound hostname) carries that site's
        Host/Origin; only a same-origin loopback page may drive a save/push.
        """
        port = self.server.server_port
        allowed = {f"{HOST}:{port}", f"localhost:{port}"}
        if self.headers.get("Host", "") not in allowed:
            return False
        origin = self.headers.get("Origin")
        if origin is not None and origin not in {f"http://{h}" for h in allowed}:
            return False
        return True

    def do_GET(self) -> None:
        if self.path in ("/", "/index.html"):
            body = HTML.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif self.path == "/api/items":
            try:
                self._json(200, _load(self.file_path))
            except Exception as exc:
                self._json(500, {"error": str(exc)})
        else:
            self._json(404, {"error": "not found"})

    def do_POST(self) -> None:
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(length) or b"{}")
        except Exception as exc:
            self._json(400, {"ok": False, "error": f"bad request body: {exc}"})
            return
        if not self._is_local_origin():
            self._json(403, {"ok": False, "error": "cross-origin request refused"})
            return
        try:
            if self.path == "/api/save":
                self._route_save(body)
            elif self.path == "/api/push":
                self._route_push(body)
            else:
                self._json(404, {"error": "not found"})
        except Exception as exc:  # don't let a handler error crash the thread / drop the connection
            self._json(500, {"ok": False, "error": f"internal error: {exc}"})

    def _route_save(self, body) -> None:
        items = body.get("items")
        if not isinstance(items, list):
            self._json(400, {"ok": False, "error": "payload must contain an items array"})
            return
        with _save_lock:  # read+write under one lock so concurrent saves can't lose an update
            base = _load(self.file_path)  # preserve schema/source/generated_at
            saved, issues = _save(self.file_path, base, items)
        if saved is None:
            self._json(422, {"ok": False, "issues": issues})  # errors -> nothing written
        else:
            self._json(200, {"ok": True, "items": saved["items"], "issues": issues})

    def _route_push(self, body) -> None:
        """Push on-screen items to the live macOS DB via json_to_apple_sqlite.

        dryRun (default True) runs the writer WITHOUT --apply: a read-only plan,
        nothing written. dryRun False applies for real (the writer backs up first).
        """
        items = body.get("items")
        if not isinstance(items, list):
            self._json(400, {"ok": False, "error": "payload must contain an items array"})
            return
        strategy = body.get("strategy", "merge")
        if strategy not in ("merge", "replace"):
            self._json(400, {"ok": False, "error": "strategy must be 'merge' or 'replace'"})
            return
        dry = bool(body.get("dryRun", True))
        # Persist the on-screen items first (with preflight) so the push matches the editor.
        with _save_lock:  # read+write under one lock (see _route_save)
            saved, issues = _save(self.file_path, _load(self.file_path), items)
        if saved is None:
            self._json(422, {"ok": False, "issues": issues})
            return
        cmd = [sys.executable, str(WRITER), str(self.file_path),
               "--strategy", strategy, "--backup-dir", str(REPO / "temp" / "db-backups")]
        if not dry:
            cmd.append("--apply")
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        except Exception as exc:
            self._json(500, {"ok": False, "error": f"writer failed to run: {exc}"})
            return
        self._json(200, {
            "ok": proc.returncode == 0,
            "dryRun": dry,
            "strategy": strategy,
            "items": saved["items"],
            "returncode": proc.returncode,
            "output": proc.stdout.strip(),
            "error": proc.stderr.strip(),
        })

    def log_message(self, *args) -> None:  # keep the console quiet
        pass


def main() -> None:
    ap = argparse.ArgumentParser(description="Local Keyboard Replacements editor.")
    ap.add_argument("--file", type=pathlib.Path, default=REPO / "temp" / "text-replacements.json")
    ap.add_argument("--port", type=int, default=8768)
    args = ap.parse_args()

    Handler.file_path = args.file.resolve()
    if not Handler.file_path.exists():
        sys.exit(f"file not found: {Handler.file_path}")
    print(f"Keyboard Replacements editor -> http://{HOST}:{args.port}  (file: {Handler.file_path})")
    print("Ctrl-C to stop.")
    try:
        ThreadingHTTPServer((HOST, args.port), Handler).serve_forever()
    except KeyboardInterrupt:
        print("\nstopped.")


if __name__ == "__main__":
    main()
