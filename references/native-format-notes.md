# Native Format Notes

macOS Text Replacements have two practical external representations:

1. Apple's private local SQLite database, currently observed at:
   `~/Library/KeyboardServices/TextReplacements.db`
2. Apple's documented import/export plist shape:
   an array of dictionaries with `shortcut` and `phrase` keys.

This skill treats the SQLite database as read-only and emits plist as the safe "back into native format" target.

## SQLite read query

```sql
SELECT ZSHORTCUT, ZPHRASE
FROM ZTEXTREPLACEMENTENTRY
ORDER BY ZSHORTCUT COLLATE NOCASE;
```

## Plist shape

```xml
<plist version="1.0">
<array>
  <dict>
    <key>shortcut</key>
    <string>;sig</string>
    <key>phrase</key>
    <string>Noel Saw</string>
  </dict>
</array>
</plist>
```

## Why no direct writes by default

Direct database writes are risky because the schema is private, System Settings and iCloud may cache or resync values, and Apple may change the backing store. Keep direct-write experiments in a separate script only after backups and manual user confirmation.
