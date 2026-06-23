#!/usr/bin/env python3
"""Shared preflight for Keyboard Replacements.

One source of truth for what "clean" means so every converter
(md_to_json, json_to_native, json_to_apple_sqlite, lint) agrees:

- the shortcut is trimmed of surrounding whitespace (the only auto-fix)
- empty shortcut, missing/empty phrase, and duplicate shortcuts are errors
- surrounding/interior whitespace in a shortcut is a warning, never silently
  removed beyond the trim (collapsing it could change meaning)
- phrase whitespace is preserved verbatim (it can be intentional)
"""

from __future__ import annotations


def check(items: list[dict]) -> tuple[list[dict], list[tuple[str, str]]]:
    """Normalize items and collect ``(severity, message)`` issues. Never raises.

    Warnings are judged against the RAW shortcut so a reporter (lint) can still
    flag whitespace that normalization trims out of the returned items.
    """
    normalized: list[dict] = []
    issues: list[tuple[str, str]] = []
    seen: dict[str, int] = {}

    for index, raw in enumerate(items, start=1):
        raw_shortcut = raw.get("shortcut")
        shortcut = None if raw_shortcut is None else str(raw_shortcut).strip()
        phrase = raw.get("phrase")
        label = shortcut or f"item #{index}"

        if not shortcut:
            issues.append(("error", f"{label}: shortcut is empty"))
        else:
            raw_text = str(raw_shortcut)
            if raw_text != raw_text.strip():
                issues.append(("warning", f"{shortcut}: shortcut has leading or trailing whitespace"))
            if any(char.isspace() for char in shortcut):
                issues.append(("warning", f"{shortcut}: shortcut contains whitespace"))
            if shortcut in seen:
                issues.append(("error", f"{shortcut}: duplicate shortcut at items {seen[shortcut]} and {index}"))
            else:
                seen[shortcut] = index

        if phrase is None or str(phrase) == "":
            issues.append(("error", f"{label}: phrase is empty"))

        item = dict(raw)
        if shortcut is not None:
            item["shortcut"] = shortcut
        normalized.append(item)

    return normalized, issues


def preflight(items: list[dict], *, include_disabled: bool = True) -> list[dict]:
    """Normalize + validate; raise ValueError listing every error found.

    Drops disabled items unless include_disabled. Returns normalized items.
    """
    kept = [it for it in items if include_disabled or it.get("enabled", True) is not False]
    normalized, issues = check(kept)
    errors = [msg for severity, msg in issues if severity == "error"]
    if errors:
        raise ValueError("; ".join(errors))
    return normalized


def _selftest() -> None:
    def raises(fn, needle):
        try:
            fn()
        except ValueError as exc:
            return needle in str(exc)
        return False

    assert raises(lambda: preflight([{"shortcut": "x", "phrase": "a"}, {"shortcut": "x", "phrase": "b"}]), "duplicate")
    assert raises(lambda: preflight([{"shortcut": "x", "phrase": ""}]), "phrase is empty")
    assert raises(lambda: preflight([{"shortcut": "  ", "phrase": "a"}]), "shortcut is empty")
    out = preflight(
        [{"shortcut": " om ", "phrase": "  hi  "}, {"shortcut": "d", "phrase": "x", "enabled": False}],
        include_disabled=False,
    )
    assert out == [{"shortcut": "om", "phrase": "  hi  "}], out  # trimmed shortcut, phrase intact, disabled dropped
    _, issues = check([{"shortcut": " om ", "phrase": "hi"}])
    assert any(sev == "warning" for sev, _ in issues), "whitespace warning should surface, not raise"
    print("replacements_common selftest: ok")


if __name__ == "__main__":
    _selftest()
