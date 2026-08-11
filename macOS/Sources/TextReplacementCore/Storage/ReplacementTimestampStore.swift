import CryptoKit
import Foundation

/// Remembers per-replacement `createdAt` / `updatedAt` across launches.
///
/// The canonical `keyboard-replacements.v1` JSON the Python bridge speaks carries no
/// timestamps, so a plain import re-stamps the whole library as brand new every launch and
/// the "Recently Changed" filter reads zero. This sidecar keeps the clock next to the app
/// instead of widening that wire contract.
///
/// Entries are keyed by normalized shortcut, not `Replacement.id`: the importer derives ids
/// with `uuid5(shortcut, phrase)`, so a row's id changes the moment its phrase is edited —
/// id is not a durable identity here. A stored content fingerprint separates "same row,
/// untouched" from "same shortcut, edited behind our back" (in System Settings, say), so
/// only the latter re-stamps `updatedAt`.
public actor ReplacementTimestampStore {
    public static let schema = "keyboard-replacement-timestamps.v1"

    private struct Entry: Codable {
        var shortcut: String
        /// Content hash as of the last time we saw the on-disk truth (import or apply).
        var fingerprint: String
        var createdAt: Date
        var updatedAt: Date
    }

    private struct Payload: Codable {
        var schema: String
        var entries: [Entry]
    }

    private let fileURL: URL
    private var cache: [String: Entry]?

    /// - Parameter fileURL: override the sidecar location (tests pass a temp path).
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    private static func defaultFileURL() -> URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("TextReplacementStudio", isDirectory: true)
            .appendingPathComponent("timestamps.json")
    }

    // MARK: - Reading the on-disk truth

    /// Stamp freshly imported (or freshly applied) rows with the timestamps we remember, and
    /// re-baseline the stored fingerprints against this known-good content.
    ///
    /// A shortcut we've never seen is "added now" — except on the very first run, where the
    /// user's existing macOS library is pre-existing history, not N rows changed today.
    /// Rebuilds the sidecar from scratch, which prunes shortcuts that no longer exist.
    @discardableResult
    public func reconcile(_ imported: [Replacement]) -> [Replacement] {
        // An empty read is far more likely a failed import than a truly empty library —
        // never let it erase the history we have.
        guard !imported.isEmpty else { return imported }

        let known = load()
        let firstRun = known.isEmpty
        let now = Date()

        var next: [String: Entry] = [:]
        var stamped: [Replacement] = []
        stamped.reserveCapacity(imported.count)

        for var replacement in imported {
            let key = Self.key(for: replacement.shortcut)
            let fingerprint = Self.fingerprint(replacement)

            if let entry = known[key] {
                replacement.createdAt = entry.createdAt
                replacement.updatedAt = entry.fingerprint == fingerprint ? entry.updatedAt : now
            } else {
                replacement.createdAt = firstRun ? .distantPast : now
                replacement.updatedAt = replacement.createdAt
            }
            stamped.append(replacement)

            guard !key.isEmpty else { continue }
            next[key] = Entry(
                shortcut: replacement.normalizedShortcut,
                fingerprint: fingerprint,
                createdAt: replacement.createdAt,
                updatedAt: replacement.updatedAt
            )
        }

        write(next)
        return stamped
    }

    // MARK: - Recording in-app edits

    /// Persist the edit clock for the current in-memory library. Leaves each entry's
    /// fingerprint alone — that tracks the on-disk truth and only `reconcile` may move it,
    /// so an edit the user never applies can't masquerade as an external change later.
    /// Does not prune: an in-flight edit is no reason to forget a row's history.
    public func record(_ replacements: [Replacement]) {
        var entries = load()
        var touched = false

        for replacement in replacements {
            let key = Self.key(for: replacement.shortcut)
            guard !key.isEmpty else { continue }   // a blank new row isn't a replacement yet
            touched = true

            if var entry = entries[key] {
                entry.createdAt = replacement.createdAt
                entry.updatedAt = replacement.updatedAt
                entries[key] = entry
            } else {
                entries[key] = Entry(
                    shortcut: replacement.normalizedShortcut,
                    fingerprint: Self.fingerprint(replacement),
                    createdAt: replacement.createdAt,
                    updatedAt: replacement.updatedAt
                )
            }
        }

        guard touched else { return }
        write(entries)
    }

    // MARK: - Persistence

    private func load() -> [String: Entry] {
        if let cache { return cache }
        guard
            let data = try? Data(contentsOf: fileURL),
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            payload.schema == Self.schema
        else {
            cache = [:]
            return [:]
        }
        let entries = Dictionary(
            payload.entries.map { (Self.key(for: $0.shortcut), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        cache = entries
        return entries
    }

    private func write(_ entries: [String: Entry]) {
        cache = entries
        // Default (`.deferredToDate`) date coding on purpose: this is a private sidecar, and
        // ISO-8601 round-tripping of `.distantPast` seed stamps is not worth the risk.
        let payload = Payload(
            schema: Self.schema,
            entries: entries.values.sorted { $0.shortcut < $1.shortcut }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoder.encode(payload).write(to: fileURL, options: .atomic)
        } catch {
            // A sidecar we can't write costs change history, not user data. Never block the app.
        }
    }

    // MARK: - Keys

    private static func key(for shortcut: String) -> String {
        shortcut.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Stable across launches, unlike `Hasher` (which is seeded per process).
    private static func fingerprint(_ replacement: Replacement) -> String {
        let canonical = [
            replacement.normalizedShortcut,
            replacement.phrase,
            replacement.enabled ? "1" : "0",
            replacement.groupName ?? "",
            replacement.notes ?? "",
        ].joined(separator: "\u{0}")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
