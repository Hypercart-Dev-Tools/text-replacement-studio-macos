import Foundation
import Testing
@testable import TextReplacementCore

/// Regression coverage for the search bug found via the `trstudio import` harness: searching
/// "ask" matched "+ask" and "~ask" by shortcut, but they rendered interleaved with (and could be
/// scrolled below) unrelated phrase-only matches, so they weren't visible without scrolling.
/// The shortcut set below is the real library that exposed the bug, captured with
/// `trstudio import --output ...` against the live macOS database; phrase text is replaced with
/// non-personal placeholders since only "shortcut match vs. phrase-only match" matters here.
struct ReplacementSearchRankingTests {
    private let library: [Replacement] = [
        Replacement(shortcut: "+ask", phrase: "Shortcut match — real regression case."),
        Replacement(shortcut: "~commit", phrase: "Unrelated shortcut, no match anywhere."),
        Replacement(shortcut: "~ask", phrase: "Shortcut match — real regression case."),
        Replacement(shortcut: "~bug", phrase: "Mentions a task in the phrase only."),
        Replacement(shortcut: "~git", phrase: "Also references a task in its phrase only."),
        Replacement(shortcut: "~HQ", phrase: "Can you add this task into the queue."),
        Replacement(shortcut: "~task", phrase: "Shortcut also matches — \"task\" contains \"ask\"."),
        Replacement(shortcut: "~repeat", phrase: "Repeat what I'm asking for, task by task."),
    ]

    @Test func shortcutMatchesRankAheadOfPhraseOnlyMatches() {
        let ranked = library.matchingSearch("ask")

        #expect(ranked.count == 7)
        #expect(!ranked.contains { $0.shortcut == "~commit" })   // no match at all — excluded

        // Shortcut matches first, in original relative order.
        #expect(ranked.prefix(3).map(\.shortcut) == ["+ask", "~ask", "~task"])
        // Then phrase-only matches, also in original relative order.
        #expect(ranked.dropFirst(3).map(\.shortcut) == ["~bug", "~git", "~HQ", "~repeat"])
    }

    @Test func emptyQueryReturnsInputUnchanged() {
        #expect(library.matchingSearch("").map(\.shortcut) == library.map(\.shortcut))
    }

    @Test func matchingIsCaseInsensitiveOnBothFields() {
        let byShortcut = [Replacement(shortcut: "+ASK", phrase: "n/a")].matchingSearch("ask")
        #expect(byShortcut.count == 1)

        let byPhrase = [Replacement(shortcut: "x", phrase: "an ASK in here")].matchingSearch("ask")
        #expect(byPhrase.count == 1)
    }

    @Test func noMatchesReturnsEmpty() {
        #expect(library.matchingSearch("zzz-no-such-query").isEmpty)
    }

    /// Regression: searching "what" used to surface phrase-only matches (any replacement whose long
    /// phrase happened to contain the common word "what") ahead of "~where" — a shortcut that shares
    /// no substring with "what" but is a much closer match by prefix ("wh"). Prefix closeness on the
    /// shortcut must now outrank an unrelated phrase hit.
    @Test func closePrefixShortcutRanksAheadOfUnrelatedPhraseMatch() {
        let library: [Replacement] = [
            Replacement(shortcut: "~360C", phrase: "A long template that happens to mention what to do next."),
            Replacement(shortcut: "/upworkdev", phrase: "Do you use GitHub already? What's your workflow like."),
            Replacement(shortcut: "~where", phrase: "Location-only shortcut, no relation to the query word."),
            Replacement(shortcut: "~commit", phrase: "No relation at all."),
        ]

        let ranked = library.matchingSearch("what")

        #expect(ranked.count == 3)
        #expect(!ranked.contains { $0.shortcut == "~commit" })
        #expect(ranked.first?.shortcut == "~where")
        #expect(ranked.dropFirst().map(\.shortcut) == ["~360C", "/upworkdev"])
    }

    @Test func exactAndPrefixShortcutMatchesOutrankCloseMatch() {
        let library: [Replacement] = [
            Replacement(shortcut: "~where", phrase: "n/a"),
            Replacement(shortcut: "~what", phrase: "n/a"),
            Replacement(shortcut: "~whatever", phrase: "n/a"),
        ]

        let ranked = library.matchingSearch("what")

        // Exact match, then prefix match, then the merely-close "where".
        #expect(ranked.map(\.shortcut) == ["~what", "~whatever", "~where"])
    }

    @Test func leadingPunctuationIsIgnoredWhenComparingShortcuts() {
        let library: [Replacement] = [
            Replacement(shortcut: "+what", phrase: "n/a"),
            Replacement(shortcut: "!what", phrase: "n/a"),
        ]

        #expect(library.matchingSearch("what").count == 2)
    }
}
