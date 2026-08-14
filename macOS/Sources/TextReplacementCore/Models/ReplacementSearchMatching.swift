import Foundation

public extension Array where Element == Replacement {
    /// Case-insensitive search over shortcut and phrase, with shortcut matches ranked ahead of
    /// phrase-only matches — a shortcut hit is what the user is almost always looking for.
    /// Relative order is preserved within each rank. An empty query returns `self` unchanged.
    ///
    /// Regression coverage: a query that only matched by shortcut (e.g. "+ask", "~ask") used to
    /// render interleaved with, and sometimes crowded out below the fold by, phrase-only matches
    /// (ReplacementSearchRankingTests).
    func matchingSearch(_ query: String) -> [Replacement] {
        guard !query.isEmpty else { return self }
        let shortcutMatches = filter { $0.shortcut.localizedCaseInsensitiveContains(query) }
        let phraseOnlyMatches = filter {
            !$0.shortcut.localizedCaseInsensitiveContains(query)
                && $0.phrase.localizedCaseInsensitiveContains(query)
        }
        return shortcutMatches + phraseOnlyMatches
    }
}
