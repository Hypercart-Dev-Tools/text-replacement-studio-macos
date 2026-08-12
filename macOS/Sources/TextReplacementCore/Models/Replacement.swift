import CryptoKit
import Foundation

public struct Replacement: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var shortcut: String
    public var phrase: String
    public var enabled: Bool
    public var groupName: String?
    public var notes: String?
    public var createdAt: Date
    public var updatedAt: Date

    /// Staged for removal on the next Apply, but still present in the library.
    ///
    /// A delete keeps its row in the array on purpose: it is what a Restore control can attach to,
    /// and it keeps `selectedReplacementID` valid. Dropping the row instead would force a general
    /// undo stack to get cancellation back (GH-2 gotcha 16). This is local staging state — it is
    /// never written to the canonical JSON and never counts as content (see `contentFingerprint`).
    public var isPendingDeletion: Bool

    public init(
        id: UUID = UUID(),
        shortcut: String,
        phrase: String,
        enabled: Bool = true,
        groupName: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPendingDeletion: Bool = false
    ) {
        self.id = id
        self.shortcut = shortcut
        self.phrase = phrase
        self.enabled = enabled
        self.groupName = groupName
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPendingDeletion = isPendingDeletion
    }
}

/// One row staged for removal, carrying the state we believe is on disk.
///
/// The writer re-reads the database at Apply time, so a target has to be verifiable: if the row
/// changed since import (another device synced, or the user edited it in System Settings), the
/// delete must abort rather than remove something the user never saw (GH-2 gotcha 12).
public struct ReplacementDeleteTarget: Codable, Hashable, Sendable {
    public var shortcut: String
    /// `Replacement.nativeFingerprint` of the state we expect to find.
    public var fingerprint: String

    public init(shortcut: String, fingerprint: String) {
        self.shortcut = shortcut
        self.fingerprint = fingerprint
    }
}

public extension Replacement {
    var normalizedShortcut: String {
        shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedPhrase: String {
        phrase.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fingerprint over every user-meaningful field. Used by `ReplacementTimestampStore` to tell
    /// "untouched" from "edited behind our back".
    ///
    /// Stable across launches, unlike `Hasher` (which is seeded per process). Do not change the
    /// canonical string without accepting that every existing sidecar entry becomes a false
    /// "changed" on the next import.
    var contentFingerprint: String {
        Self.sha256([
            normalizedShortcut,
            phrase,
            enabled ? "1" : "0",
            groupName ?? "",
            notes ?? "",
        ])
    }

    /// Fingerprint over **only the fields Apple's table actually stores** — shortcut and phrase.
    ///
    /// This is deliberately narrower than `contentFingerprint`. `enabled`, `groupName` and `notes`
    /// live only in this app; `ZTEXTREPLACEMENTENTRY` has no columns for them. A delete target is
    /// verified against the live database, so its fingerprint can only cover what the database can
    /// answer for — a full-content fingerprint would never match and every delete would abort.
    var nativeFingerprint: String {
        Self.sha256([normalizedShortcut, phrase])
    }

    private static func sha256(_ parts: [String]) -> String {
        let canonical = parts.joined(separator: "\u{0}")
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    /// Rolling window behind the "Recently Changed" smart filter.
    static let recencyWindow: TimeInterval = 7 * 24 * 60 * 60

    /// Whether this row was added or edited inside the recency window. Only meaningful once
    /// `ReplacementTimestampStore` has stamped it — the import JSON carries no timestamps.
    func isRecentlyChanged(
        now: Date = Date(),
        window: TimeInterval = Replacement.recencyWindow
    ) -> Bool {
        updatedAt > now.addingTimeInterval(-window)
    }
}
