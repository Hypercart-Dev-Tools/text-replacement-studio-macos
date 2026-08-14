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
}
