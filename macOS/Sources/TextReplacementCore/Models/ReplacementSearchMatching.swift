import Foundation

public extension Array where Element == Replacement {
    /// Case-insensitive search over shortcut and phrase, ranked so results closer to the query
    /// surface first. Leading punctuation on the shortcut (`~`, `/`, `+`, `!`, etc.) is ignored
    /// when comparing, and a shared *prefix* is weighted far above a substring hit anywhere else —
    /// so a query like "what" ranks a shortcut like "~where" (shares the "wh" prefix) above a
    /// replacement whose *phrase* merely contains the word "what" somewhere in its body.
    ///
    /// Ranking tiers, most relevant first (ties preserve original order):
    ///   1. Normalized shortcut equals the query exactly.
    ///   2. Normalized shortcut and query share a full prefix relationship (one starts with the other).
    ///   3. Normalized shortcut shares a leading run of at least 2 characters with the query — the
    ///      "wh" in "what"/"where" case.
    ///   4. Normalized shortcut contains the query anywhere (not as a prefix).
    ///   5. Phrase contains the query anywhere.
    ///
    /// Regression coverage: a query that only matched by shortcut (e.g. "+ask", "~ask") used to
    /// render interleaved with, and sometimes crowded out below the fold by, phrase-only matches;
    /// a query close to a shortcut by prefix (e.g. "what" vs "~where") used to be crowded out
    /// entirely by phrase matches containing the query as an ordinary word (ReplacementSearchRankingTests).
    func matchingSearch(_ query: String) -> [Replacement] {
        guard !query.isEmpty else { return self }
        let lowerQuery = query.lowercased()

        func rank(for replacement: Replacement) -> Int? {
            let normalizedShortcut = replacement.shortcut.normalizedForSearch()

            if normalizedShortcut == lowerQuery {
                return 0
            }
            if normalizedShortcut.hasPrefix(lowerQuery) || lowerQuery.hasPrefix(normalizedShortcut) {
                return 1
            }
            let closeThreshold = Swift.min(2, lowerQuery.count)
            if closeThreshold > 0, normalizedShortcut.commonPrefixLength(with: lowerQuery) >= closeThreshold {
                return 2
            }
            if normalizedShortcut.contains(lowerQuery) {
                return 3
            }
            if replacement.phrase.lowercased().contains(lowerQuery) {
                return 4
            }
            return nil
        }

        return enumerated()
            .compactMap { index, replacement -> (rank: Int, index: Int, replacement: Replacement)? in
                guard let rank = rank(for: replacement) else { return nil }
                return (rank, index, replacement)
            }
            .sorted { lhs, rhs in
                lhs.rank != rhs.rank ? lhs.rank < rhs.rank : lhs.index < rhs.index
            }
            .map(\.replacement)
    }
}

private extension String {
    /// Lowercases and strips leading non-alphanumeric characters (shortcut prefixes like `~`, `/`, `+`)
    /// so shortcuts compare on their meaningful text rather than their trigger punctuation.
    func normalizedForSearch() -> String {
        String(lowercased().drop { !$0.isLetter && !$0.isNumber })
    }

    func commonPrefixLength(with other: String) -> Int {
        var count = 0
        for (a, b) in zip(self, other) {
            guard a == b else { break }
            count += 1
        }
        return count
    }
}
