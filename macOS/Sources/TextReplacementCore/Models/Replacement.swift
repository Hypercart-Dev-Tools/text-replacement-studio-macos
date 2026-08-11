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

    public init(
        id: UUID = UUID(),
        shortcut: String,
        phrase: String,
        enabled: Bool = true,
        groupName: String? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.shortcut = shortcut
        self.phrase = phrase
        self.enabled = enabled
        self.groupName = groupName
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public extension Replacement {
    var normalizedShortcut: String {
        shortcut.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var normalizedPhrase: String {
        phrase.trimmingCharacters(in: .whitespacesAndNewlines)
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
