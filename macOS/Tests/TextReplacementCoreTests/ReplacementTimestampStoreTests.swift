import Foundation
import Testing
@testable import TextReplacementCore

/// The timestamp sidecar is the only thing standing between "Recently Changed" and a
/// permanent zero: the canonical import JSON carries no timestamps, so each of these pins
/// a launch-to-launch behavior the filter depends on.
struct ReplacementTimestampStoreTests {
    /// A fresh store over a throwaway file, plus the file url so a test can simulate a
    /// relaunch by building a second store over the same path.
    private func makeStore() -> (ReplacementTimestampStore, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fkr-timestamps-\(UUID().uuidString)")
            .appendingPathComponent("timestamps.json")
        return (ReplacementTimestampStore(fileURL: url), url)
    }

    /// Simulates the importer: same content in, brand-new ids and `Date()` timestamps out.
    private func reimport(_ replacements: [Replacement]) -> [Replacement] {
        replacements.map {
            Replacement(
                shortcut: $0.shortcut,
                phrase: $0.phrase,
                enabled: $0.enabled,
                groupName: $0.groupName,
                notes: $0.notes
            )
        }
    }

    @Test func firstRunSeedsExistingLibraryAsHistoryNotAsChangedToday() async {
        let (store, _) = makeStore()
        let stamped = await store.reconcile([
            Replacement(shortcut: "omw", phrase: "On my way!"),
            Replacement(shortcut: "/sig", phrase: "Sam Rivera"),
        ])

        // An inherited macOS library is pre-existing history — it must not light up the filter.
        #expect(stamped.allSatisfy { !$0.isRecentlyChanged() })
    }

    @Test func editSurvivesRelaunchAndReimport() async {
        let (store, url) = makeStore()
        let seeded = await store.reconcile([
            Replacement(shortcut: "omw", phrase: "On my way!"),
            Replacement(shortcut: "/sig", phrase: "Sam Rivera"),
        ])

        // Edit one row in-app and let the debounced save land.
        var edited = seeded
        edited[0].phrase = "On my way now!"
        edited[0].updatedAt = Date()
        await store.record(edited)

        // Relaunch: a new store over the same file, re-importing the applied content.
        let reopened = ReplacementTimestampStore(fileURL: url)
        let afterRelaunch = await reopened.reconcile(reimport(edited))

        let omw = try! #require(afterRelaunch.first { $0.shortcut == "omw" })
        let sig = try! #require(afterRelaunch.first { $0.shortcut == "/sig" })
        #expect(omw.isRecentlyChanged())        // the edit is remembered across launches
        #expect(!sig.isRecentlyChanged())       // the untouched row stays quiet
    }

    @Test func untouchedRowsStayQuietAcrossRepeatedImports() async {
        let (store, url) = makeStore()
        let library = [Replacement(shortcut: "omw", phrase: "On my way!")]
        _ = await store.reconcile(library)

        // Re-importing the same content must not look like a change, even though the
        // importer hands us fresh ids and fresh `Date()` stamps every time.
        let reopened = ReplacementTimestampStore(fileURL: url)
        let again = await reopened.reconcile(reimport(library))
        #expect(again.allSatisfy { !$0.isRecentlyChanged() })
    }

    @Test func contentChangedOutsideTheAppCountsAsRecentlyChanged() async {
        let (store, url) = makeStore()
        _ = await store.reconcile([Replacement(shortcut: "omw", phrase: "On my way!")])

        // Someone edited the phrase in System Settings between launches.
        let reopened = ReplacementTimestampStore(fileURL: url)
        let afterRelaunch = await reopened.reconcile([
            Replacement(shortcut: "omw", phrase: "Heading over now"),
        ])
        #expect(afterRelaunch[0].isRecentlyChanged())
    }

    @Test func newShortcutAfterFirstRunReadsAsAddedNow() async {
        let (store, url) = makeStore()
        _ = await store.reconcile([Replacement(shortcut: "omw", phrase: "On my way!")])

        let reopened = ReplacementTimestampStore(fileURL: url)
        let afterRelaunch = await reopened.reconcile([
            Replacement(shortcut: "omw", phrase: "On my way!"),
            Replacement(shortcut: "/new", phrase: "Freshly added"),
        ])
        let added = try! #require(afterRelaunch.first { $0.shortcut == "/new" })
        #expect(added.isRecentlyChanged())
    }

    @Test func emptyImportDoesNotEraseHistory() async {
        let (store, url) = makeStore()
        let seeded = await store.reconcile([Replacement(shortcut: "omw", phrase: "On my way!")])
        var edited = seeded
        edited[0].updatedAt = Date()
        await store.record(edited)

        // A failed import surfaces as zero rows — it must not be read as "user deleted everything".
        _ = await store.reconcile([])

        let reopened = ReplacementTimestampStore(fileURL: url)
        let afterRelaunch = await reopened.reconcile(reimport(edited))
        #expect(afterRelaunch[0].isRecentlyChanged())
    }

    @Test func recencyWindowExcludesOlderEdits() async {
        let (store, url) = makeStore()
        let seeded = await store.reconcile([Replacement(shortcut: "omw", phrase: "On my way!")])

        var stale = seeded
        stale[0].updatedAt = Date().addingTimeInterval(-Replacement.recencyWindow - 60)
        await store.record(stale)

        let reopened = ReplacementTimestampStore(fileURL: url)
        let afterRelaunch = await reopened.reconcile(reimport(stale))
        #expect(!afterRelaunch[0].isRecentlyChanged())
    }

    @Test func blankRowsAreNotPersisted() async {
        let (store, url) = makeStore()
        _ = await store.reconcile([Replacement(shortcut: "omw", phrase: "On my way!")])
        // A just-added, still-blank row has no shortcut to key on.
        await store.record([Replacement(shortcut: "  ", phrase: "")])

        let data = try! Data(contentsOf: url)
        #expect(!String(decoding: data, as: UTF8.self).contains("\"shortcut\" : \"\""))
    }
}
