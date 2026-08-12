import Foundation
import Testing
@testable import TextReplacementCore

/// The wire contract for targeted deletion (GH-2 Phase 2).
///
/// The writer keys everything by shortcut and throws our ids away, so the only way it can be told
/// "remove this one row" is the explicit `deletes` array. These pin that payload, plus the
/// fingerprint the Python side re-derives to decide whether a delete is still safe to perform.
struct DeleteTransportTests {
    let codec = CanonicalReplacementCodec()

    private func payload(_ data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func pendingDeletionsAreStrippedFromItems() throws {
        let keep = Replacement(shortcut: "omw", phrase: "On my way!")
        var drop = Replacement(shortcut: "/sig", phrase: "Sam Rivera")
        drop.isPendingDeletion = true

        let json = try payload(codec.encode([keep, drop]))
        let items = try #require(json["items"] as? [[String: Any]])

        // Leaving a staged row in `items` would tell the writer to keep the very row we are removing.
        #expect(items.count == 1)
        #expect(items.first?["shortcut"] as? String == "omw")
    }

    @Test func deletesArrayIsOmittedWhenEmpty() throws {
        let json = try payload(codec.encode([Replacement(shortcut: "omw", phrase: "On my way!")]))
        // Absent rather than `[]`, so payloads from before targeted deletes stay byte-comparable.
        #expect(json["deletes"] == nil)
    }

    @Test func deletesArrayCarriesShortcutAndFingerprint() throws {
        let doomed = Replacement(shortcut: "/sig", phrase: "Sam Rivera")
        let target = ReplacementDeleteTarget(
            shortcut: doomed.normalizedShortcut, fingerprint: doomed.nativeFingerprint
        )
        let json = try payload(codec.encode([], deletes: [target]))
        let deletes = try #require(json["deletes"] as? [[String: Any]])

        #expect(deletes.count == 1)
        #expect(deletes[0]["shortcut"] as? String == "/sig")
        #expect(deletes[0]["fingerprint"] as? String == doomed.nativeFingerprint)
    }

    /// The fingerprint must cover only what Apple's table stores. If it covered `groupName` or
    /// `notes` — which have no columns there — the Python side could never reproduce it and every
    /// delete would abort as "changed since the plan was computed".
    @Test func nativeFingerprintIgnoresFieldsTheDatabaseCannotSee() {
        let base = Replacement(shortcut: "omw", phrase: "On my way!")
        var decorated = base
        decorated.groupName = "Personal"
        decorated.notes = "casual"
        decorated.enabled = false

        #expect(decorated.nativeFingerprint == base.nativeFingerprint)
        // The content fingerprint, used by the timestamp sidecar, must still notice all of it.
        #expect(decorated.contentFingerprint != base.contentFingerprint)
    }

    @Test func nativeFingerprintChangesWithShortcutOrPhrase() {
        let base = Replacement(shortcut: "omw", phrase: "On my way!")
        var renamed = base;  renamed.shortcut = "omw2"
        var reworded = base; reworded.phrase = "Heading over"

        #expect(renamed.nativeFingerprint != base.nativeFingerprint)
        #expect(reworded.nativeFingerprint != base.nativeFingerprint)
    }

    /// Cross-language pin. This literal was produced by the Python side
    /// (`json_to_apple_sqlite.native_fingerprint("  omw  ", "On my way!")`), so if either
    /// implementation drifts, this fails loudly here instead of silently aborting every delete at
    /// runtime with "it changed since the plan was computed".
    @Test func nativeFingerprintMatchesThePythonImplementation() {
        let r = Replacement(shortcut: "  omw  ", phrase: "On my way!")
        #expect(r.nativeFingerprint == "58ffdc1e9c13635f74e6fe5d1285fdd17fa125ce09470502eacfa73222d12212")
        // Trimming is part of the contract — the DB side strips before hashing.
        #expect(r.nativeFingerprint == Replacement(shortcut: "omw", phrase: "On my way!").nativeFingerprint)
    }

    @Test func isPendingDeletionIsNotContentAndDoesNotLeakToJSON() throws {
        var staged = Replacement(shortcut: "omw", phrase: "On my way!")
        staged.isPendingDeletion = true

        // Staging is local UI state, so the canonical payload must not carry it.
        let json = try payload(codec.encode([staged], deletes: []))
        let items = json["items"] as? [[String: Any]] ?? []
        #expect(items.isEmpty)   // stripped entirely
        #expect(!String(decoding: try codec.encode([staged]), as: UTF8.self).contains("isPendingDeletion"))
    }
}
