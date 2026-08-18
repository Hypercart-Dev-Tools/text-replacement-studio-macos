import XCTest
@testable import TextReplacementCore

/// The bug these cover: an incomplete row produced "Apply failed" with a Retry that could only
/// fail again, because the real cause never left the Python subprocess.
final class ReplacementApplyPreflightTests: XCTestCase {
    private func row(
        _ shortcut: String,
        _ phrase: String,
        enabled: Bool = true,
        pendingDeletion: Bool = false
    ) -> Replacement {
        Replacement(
            shortcut: shortcut,
            phrase: phrase,
            enabled: enabled,
            isPendingDeletion: pendingDeletion
        )
    }

    func testBlankRowIsOneBlockerNotTwo() {
        let blockers = ReplacementApplyPreflight().blockers(in: [row("", "")])
        XCTAssertEqual(blockers.count, 1)
        XCTAssertEqual(blockers.first?.kind, .blank)
        XCTAssertTrue(blockers[0].message.contains("give it a shortcut and a phrase"), blockers[0].message)
    }

    func testEmptyShortcutIsNamedByItsPhrase() {
        let blockers = ReplacementApplyPreflight().blockers(in: [row("", "on my way")])
        XCTAssertEqual(blockers.map(\.kind), [.emptyShortcut])
        XCTAssertTrue(blockers[0].message.contains("on my way"), blockers[0].message)
    }

    func testEmptyPhraseIsNamedByItsShortcut() {
        let blockers = ReplacementApplyPreflight().blockers(in: [row("omw", "")])
        XCTAssertEqual(blockers.map(\.kind), [.emptyPhrase])
        XCTAssertTrue(blockers[0].message.contains("“omw”"), blockers[0].message)
    }

    func testWhitespaceOnlyShortcutCountsAsEmpty() {
        let blockers = ReplacementApplyPreflight().blockers(in: [row("   ", "hi")])
        XCTAssertEqual(blockers.map(\.kind), [.emptyShortcut])
    }

    /// The Python writer compares the phrase untrimmed, so a spaces-only phrase applies fine.
    /// Rejecting it here would block a write that succeeds today.
    func testWhitespaceOnlyPhraseIsAllowed() {
        XCTAssertTrue(ReplacementApplyPreflight().blockers(in: [row("sp", "   ")]).isEmpty)
    }

    func testDuplicateShortcutsBlockEveryCopy() {
        let blockers = ReplacementApplyPreflight().blockers(in: [row("omw", "a"), row(" omw ", "b")])
        XCTAssertEqual(blockers.count, 2)
        XCTAssertTrue(blockers.allSatisfy { $0.kind == .duplicateShortcut })
        XCTAssertTrue(blockers[0].message.contains("2 replacements share"), blockers[0].message)
    }

    /// Mirrors the writer: disabled rows are dropped before validation unless asked for.
    func testDisabledRowsAreExemptUnlessIncluded() {
        let library = [row("", "", enabled: false)]
        XCTAssertTrue(ReplacementApplyPreflight().blockers(in: library).isEmpty)
        XCTAssertEqual(ReplacementApplyPreflight(includeDisabled: true).blockers(in: library).count, 1)
    }

    /// Pending deletions never reach the payload, so an incomplete one must not block the apply
    /// that is removing it.
    func testPendingDeletionsAreExempt() {
        XCTAssertTrue(
            ReplacementApplyPreflight().blockers(in: [row("", "", pendingDeletion: true)]).isEmpty
        )
    }

    func testValidLibraryHasNoBlockers() {
        XCTAssertTrue(ReplacementApplyPreflight().blockers(in: [row("omw", "on my way"), row("ty", "thank you")]).isEmpty)
    }

    func testBlockerOrderFollowsTheLibrary() {
        let library = [row("omw", ""), row("", ""), row("ty", "thanks")]
        let ids = ReplacementApplyPreflight().blockers(in: library).map(\.replacementID)
        XCTAssertEqual(ids, [library[0].id, library[1].id])
    }

    func testExplanationCountsRowsAndCapsTheList() {
        let library = [row("a", ""), row("b", ""), row("c", ""), row("d", "")]
        let preflight = ReplacementApplyPreflight()
        let explanation = preflight.explanation(for: preflight.blockers(in: library), limit: 3)

        XCTAssertEqual(explanation.summary, "Nothing was written — 4 replacements can't be applied")
        XCTAssertTrue(explanation.detail.contains("…and 1 more."), explanation.detail)
        XCTAssertTrue(explanation.body.contains("Fix the rows above, then Apply again."))
    }

    func testExplanationUsesSingularForOneRow() {
        let preflight = ReplacementApplyPreflight()
        let explanation = preflight.explanation(for: preflight.blockers(in: [row("", "")]))
        XCTAssertTrue(explanation.summary.hasSuffix("1 replacement can't be applied"), explanation.summary)
    }

    /// Three rows sharing a shortcut produce three identical messages; the user should see one.
    func testExplanationDeduplicatesIdenticalMessages() {
        let preflight = ReplacementApplyPreflight()
        let blockers = preflight.blockers(in: [row("omw", "a"), row("omw", "b"), row("omw", "c")])
        let explanation = preflight.explanation(for: blockers)
        XCTAssertEqual(explanation.detail.components(separatedBy: "•").count - 1, 1, explanation.detail)
    }
}

final class ReplacementFailureExplainerTests: XCTestCase {
    private func explain(_ message: String, _ op: ReplacementFailureExplainer.Operation = .applying)
        -> ReplacementFailureExplanation
    {
        ReplacementFailureExplainer.explain(
            ReplacementImportExportError.invalidInput(message), during: op
        )
    }

    func testStripsSubprocessChromeAndErrorPrefix() {
        XCTAssertEqual(
            ReplacementFailureExplainer.distill(
                "json_to_apple_sqlite.py failed (exit 1): error: item 2: phrase is empty"
            ),
            "item 2: phrase is empty"
        )
    }

    func testDistillPrefersTheErrorLineOverATraceback() {
        let raw = """
        Traceback (most recent call last):
          File "json_to_apple_sqlite.py", line 12, in <module>
            main()
        error: database is locked
        """
        XCTAssertEqual(ReplacementFailureExplainer.distill(raw), "database is locked")
    }

    func testLockedDatabaseBecomesAnActionableMessage() {
        let e = explain("json_to_apple_sqlite.py failed (exit 1): error: database is locked")
        XCTAssertEqual(e.summary, "Nothing was written — the database is in use")
        XCTAssertTrue(e.fix?.contains("Quit System Settings") == true)
    }

    func testReadonlyDatabasePointsAtFullDiskAccess() {
        let e = explain("error: attempt to write a readonly database")
        XCTAssertTrue(e.fix?.contains("Full Disk Access") == true, e.fix ?? "nil")
    }

    func testMissingDatabaseExplainsMacOSHasNotCreatedItYet() {
        let e = explain("error: database not found: /Users/x/Library/KeyboardServices/TextReplacements.db", .importing)
        XCTAssertTrue(e.summary.hasPrefix("Import failed"), e.summary)
        XCTAssertTrue(e.detail.contains("has no Text Replacements database yet"), e.detail)
    }

    /// The writer's delete-verification messages are already clear — keep their wording, add a fix.
    func testWriterOwnedWordingIsPreserved() {
        let e = explain("error: refusing to delete 'omw': it changed since the plan was computed (edited in System Settings, or synced from another device). Re-import and retry.")
        XCTAssertTrue(e.detail.contains("refusing to delete"), e.detail)
        XCTAssertEqual(e.fix, "Import again to pick up the current state, then Apply.")
    }

    func testBridgeErrorsGetTheirOwnGuidance() {
        let e = ReplacementFailureExplainer.explain(
            PythonBridge.BridgeError.pythonNotFound, during: .importing
        )
        XCTAssertEqual(e.summary, "Import failed — python3 is missing")
        XCTAssertTrue(e.fix?.contains("xcode-select --install") == true)
    }

    func testUnknownFailuresPassTheMessageThroughRatherThanGuessing() {
        let e = explain("json_to_apple_sqlite.py failed (exit 3): error: something nobody anticipated")
        XCTAssertEqual(e.detail, "something nobody anticipated")
        XCTAssertTrue(e.summary.contains("something nobody anticipated"), e.summary)
        XCTAssertTrue(e.fix?.contains("Copy Details") == true)
    }

    func testSilentFailureStillSaysSomething() {
        let e = explain("json_to_apple_sqlite.py failed (exit 1): ")
        XCTAssertTrue(e.detail.contains("exited without saying why"), e.detail)
    }

    func testRawDetailIsAlwaysKeptForCopying() {
        let raw = "json_to_apple_sqlite.py failed (exit 1): error: database is locked"
        XCTAssertEqual(explain(raw).rawDetail, raw)
    }

    func testOperationChangesTheOutcomeClause() {
        XCTAssertTrue(explain("error: database is locked", .planning).summary.hasPrefix("Couldn't build the preview"))
    }
}
