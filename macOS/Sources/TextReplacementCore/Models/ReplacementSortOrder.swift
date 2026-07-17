import Foundation

public enum ReplacementSortOrder: String, CaseIterable, Hashable, Sendable {
    /// The order replacements were imported/added in — no sort applied.
    case manual
    case dateCreated
    case alphabetical

    public var label: String {
        switch self {
        case .manual: return "Default Order"
        case .dateCreated: return "Date Created"
        case .alphabetical: return "Alphabetical"
        }
    }
}

public extension Array where Element == Replacement {
    func sorted(order: ReplacementSortOrder) -> [Replacement] {
        switch order {
        case .manual:
            return self
        case .dateCreated:
            return sorted { $0.createdAt > $1.createdAt }
        case .alphabetical:
            return sorted {
                $0.normalizedShortcut.localizedCaseInsensitiveCompare($1.normalizedShortcut) == .orderedAscending
            }
        }
    }
}
