import Foundation
import Testing
@testable import TextReplacementCore

/// True end-to-end coverage of the macOS integration: Swift → canonical JSON →
/// `json_to_apple_sqlite.py` (apply) → SQLite → `native_to_json.py` (import) → Swift.
///
/// SAFETY: every run operates on a *temporary copy* of the database — never the user's
/// live `~/Library/KeyboardServices/TextReplacements.db`. The whole suite is gated by
/// `BridgeTestSupport.canRun`, so it auto-skips when python3, the repo `scripts/`, or a
/// source database aren't available (e.g. headless CI). Point it at a fixture explicitly
/// with `FKR_TEST_DB=/path/to/TextReplacements.db`.
struct AppleDatabaseBridgeE2ETests {

    @Test(.enabled(if: BridgeTestSupport.canRun,
                   "Needs python3 + repo scripts/ + a source DB (set FKR_TEST_DB to override)."))
    func applyThenReimportRoundTripsANewReplacement() async throws {
        let env = try BridgeTestSupport.makeSandbox()
        defer { env.cleanup() }

        let importer = AppleDatabaseImporter(bridge: env.bridge)
        let before = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported

        // A shortcut unlikely to already exist, so this is unambiguously an add.
        let shortcut = "zz_e2e_\(Int.random(in: 100_000...999_999))"
        let phrase = "end-to-end round-trip \(UUID().uuidString.prefix(8))"
        let writer = AppleDatabaseWriter(bridge: env.bridge, backupDirectory: env.backupDir)

        let outcome = try writer.apply(before + [Replacement(shortcut: shortcut, phrase: String(phrase))],
                                       strategy: .merge)
        #expect(outcome.applied)

        let after = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported
        #expect(after.contains { $0.shortcut == shortcut && $0.phrase == String(phrase) })
        #expect(after.count >= before.count)   // merge adds/updates, never removes
    }

    @Test(.enabled(if: BridgeTestSupport.canRun,
                   "Needs python3 + repo scripts/ + a source DB (set FKR_TEST_DB to override)."))
    func planIsADryRunAndDoesNotMutate() async throws {
        let env = try BridgeTestSupport.makeSandbox()
        defer { env.cleanup() }

        let importer = AppleDatabaseImporter(bridge: env.bridge)
        let before = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported

        let writer = AppleDatabaseWriter(bridge: env.bridge, backupDirectory: env.backupDir)
        let plan = try writer.plan(before + [Replacement(shortcut: "zz_plan_only", phrase: "should not persist")],
                                   strategy: .merge)
        #expect(!plan.applied)                 // dry-run

        let after = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported
        #expect(after.count == before.count)   // nothing written
        #expect(!after.contains { $0.shortcut == "zz_plan_only" })
    }

    /// Applying content that hasn't changed must not re-stamp `ZTIMESTAMP`.
    ///
    /// The writer used to UPDATE every desired shortcut unconditionally — including the
    /// ones its own dry-run plan reported as `skip` — which flattened the whole library's
    /// timestamps to "now" on every apply and re-flagged every row for CloudKit upload.
    /// That is how a real user's per-row history (dating back to 2013) was lost.
    @Test(.enabled(if: BridgeTestSupport.canRun,
                   "Needs python3 + repo scripts/ + a source DB (set FKR_TEST_DB to override)."))
    func applyingUnchangedContentPreservesRowTimestamps() async throws {
        let env = try BridgeTestSupport.makeSandbox()
        defer { env.cleanup() }

        let importer = AppleDatabaseImporter(bridge: env.bridge)
        let before = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported
        try #require(!before.isEmpty, "source DB has no replacements to test against")

        let timestampsBefore = try BridgeTestSupport.timestamps(in: env.databasePath)
        try #require(!timestampsBefore.isEmpty)

        // Push the library straight back, byte-identical: every row is a no-op.
        let writer = AppleDatabaseWriter(bridge: env.bridge, backupDirectory: env.backupDir)
        let outcome = try writer.apply(before, strategy: .merge)
        #expect(outcome.applied)

        let timestampsAfter = try BridgeTestSupport.timestamps(in: env.databasePath)
        #expect(timestampsAfter == timestampsBefore)
    }

    /// The complement: a row that really did change *should* be re-stamped, so the fix
    /// above can't be satisfied by simply never writing timestamps at all.
    @Test(.enabled(if: BridgeTestSupport.canRun,
                   "Needs python3 + repo scripts/ + a source DB (set FKR_TEST_DB to override)."))
    func applyingAnEditedRowDoesRestampOnlyThatRow() async throws {
        let env = try BridgeTestSupport.makeSandbox()
        defer { env.cleanup() }

        let importer = AppleDatabaseImporter(bridge: env.bridge)
        var library = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported
        try #require(library.count >= 2, "need at least two rows to tell touched from untouched")

        let timestampsBefore = try BridgeTestSupport.timestamps(in: env.databasePath)
        let edited = library[0].shortcut
        library[0].phrase += " · edited \(UUID().uuidString.prefix(6))"

        let writer = AppleDatabaseWriter(bridge: env.bridge, backupDirectory: env.backupDir)
        let outcome = try writer.apply(library, strategy: .merge)
        #expect(outcome.applied)

        let timestampsAfter = try BridgeTestSupport.timestamps(in: env.databasePath)
        #expect(timestampsAfter[edited] != timestampsBefore[edited])   // the edit is stamped
        for (shortcut, stamp) in timestampsBefore where shortcut != edited {
            #expect(timestampsAfter[shortcut] == stamp)                // everyone else untouched
        }
    }
}

    /// The core promise of the feature: a single row is removed, under **Merge** — the strategy
    /// that previously could not express a deletion at all.
    @Test(.enabled(if: BridgeTestSupport.canRun,
                   "Needs python3 + repo scripts/ + a source DB (set FKR_TEST_DB to override)."))
    func targetedDeleteRemovesExactlyOneRowUnderMerge() async throws {
        let env = try BridgeTestSupport.makeSandbox()
        defer { env.cleanup() }

        let importer = AppleDatabaseImporter(bridge: env.bridge)
        let writer = AppleDatabaseWriter(bridge: env.bridge, backupDirectory: env.backupDir)

        // Seed a row we own, so the test never depends on the contents of the source DB.
        let shortcut = "zz_del_\(Int.random(in: 100_000...999_999))"
        let before = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported
        let seeded = before + [Replacement(shortcut: shortcut, phrase: "delete me")]
        #expect(try writer.apply(seeded, strategy: .merge).applied)

        let withRow = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported
        let doomed = try #require(withRow.first { $0.shortcut == shortcut })
        let othersBefore = withRow.count - 1

        let target = ReplacementDeleteTarget(
            shortcut: doomed.normalizedShortcut, fingerprint: doomed.nativeFingerprint
        )
        let survivors = withRow.filter { $0.shortcut != shortcut }
        #expect(try writer.apply(survivors, strategy: .merge, deletes: [target]).applied)

        let after = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported
        #expect(!after.contains { $0.shortcut == shortcut })   // the target is gone
        #expect(after.count == othersBefore)                    // and nothing else went with it
    }

    /// Optimistic concurrency: if the row changed after the plan was computed, the delete must
    /// abort rather than remove something the user never saw in the confirmation.
    @Test(.enabled(if: BridgeTestSupport.canRun,
                   "Needs python3 + repo scripts/ + a source DB (set FKR_TEST_DB to override)."))
    func targetedDeleteAbortsWhenTheRowChangedSinceThePlan() async throws {
        let env = try BridgeTestSupport.makeSandbox()
        defer { env.cleanup() }

        let importer = AppleDatabaseImporter(bridge: env.bridge)
        let writer = AppleDatabaseWriter(bridge: env.bridge, backupDirectory: env.backupDir)

        let shortcut = "zz_stale_\(Int.random(in: 100_000...999_999))"
        let before = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported
        #expect(try writer.apply(before + [Replacement(shortcut: shortcut, phrase: "original")],
                                 strategy: .merge).applied)
        let withRow = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported

        // A fingerprint for a phrase that is NOT what is on disk — i.e. the row moved under us.
        let stale = ReplacementDeleteTarget(
            shortcut: shortcut,
            fingerprint: Replacement(shortcut: shortcut, phrase: "something else").nativeFingerprint
        )
        let survivors = withRow.filter { $0.shortcut != shortcut }

        #expect(throws: (any Error).self) {
            try writer.apply(survivors, strategy: .merge, deletes: [stale])
        }

        // And the abort must be total — the row is still there.
        let after = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported
        #expect(after.contains { $0.shortcut == shortcut })
        #expect(after.count == withRow.count)
    }

    /// A target that no longer exists aborts too, rather than silently succeeding as a no-op.
    @Test(.enabled(if: BridgeTestSupport.canRun,
                   "Needs python3 + repo scripts/ + a source DB (set FKR_TEST_DB to override)."))
    func targetedDeleteAbortsWhenTheTargetIsMissing() async throws {
        let env = try BridgeTestSupport.makeSandbox()
        defer { env.cleanup() }

        let importer = AppleDatabaseImporter(bridge: env.bridge)
        let writer = AppleDatabaseWriter(bridge: env.bridge, backupDirectory: env.backupDir)
        let library = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported

        let ghost = ReplacementDeleteTarget(
            shortcut: "zz_ghost_\(Int.random(in: 100_000...999_999))", fingerprint: "deadbeef"
        )
        #expect(throws: (any Error).self) {
            try writer.apply(library, strategy: .merge, deletes: [ghost])
        }

        let after = try await importer.importReplacements(request: .init(source: .appleDatabase)).imported
        #expect(after.count == library.count)
    }

// MARK: - Gating + sandbox

enum BridgeTestSupport {
    /// A working DB copy + a bridge pointed at it, plus a temp backup dir. Disposable.
    struct Sandbox {
        let root: URL
        let bridge: PythonBridge
        let backupDir: URL
        /// The throwaway DB copy this sandbox targets — for assertions on columns the
        /// canonical JSON doesn't carry (ZTIMESTAMP, ZNEEDSSAVETOCLOUD).
        var databasePath: URL { bridge.databasePath }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
    }

    enum BridgeTestError: Error { case sqliteFailed(status: Int32, stderr: String) }

    static let sqlite3Path = "/usr/bin/sqlite3"

    /// Shortcut → raw `ZTIMESTAMP`, read straight from SQLite. The canonical JSON has no
    /// timestamp fields, so the bridge round-trip can't see this column at all.
    static func timestamps(in database: URL) throws -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: sqlite3Path)
        process.arguments = [
            database.path,
            """
            SELECT ZSHORTCUT || char(9) || COALESCE(ZTIMESTAMP, '') FROM ZTEXTREPLACEMENTENTRY
            WHERE COALESCE(ZWASDELETED, 0) = 0 AND ZSHORTCUT IS NOT NULL;
            """,
        ]
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BridgeTestError.sqliteFailed(
                status: process.terminationStatus,
                stderr: String(decoding: errData, as: UTF8.self)
            )
        }

        var result: [String: String] = [:]
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            result[String(parts[0])] = String(parts[1])
        }
        return result
    }

    /// Source database to copy from: explicit `FKR_TEST_DB`, else the live DB if present.
    static var sourceDatabase: URL? {
        let fm = FileManager.default
        if let p = ProcessInfo.processInfo.environment["FKR_TEST_DB"], !p.isEmpty {
            let url = URL(fileURLWithPath: (p as NSString).expandingTildeInPath)
            return fm.fileExists(atPath: url.path) ? url : nil
        }
        let live = PythonBridge.defaultDatabasePath()
        return fm.fileExists(atPath: live.path) ? live : nil
    }

    static var scriptsDirectory: URL? { try? PythonBridge.resolveScriptsDirectory() }

    static var python3Available: Bool {
        let fm = FileManager.default
        if let p = ProcessInfo.processInfo.environment["FKR_PYTHON"], fm.isExecutableFile(atPath: p) { return true }
        return ["/usr/bin/python3", "/opt/homebrew/bin/python3", "/usr/local/bin/python3"]
            .contains { fm.isExecutableFile(atPath: $0) }
    }

    static let canRun: Bool = sourceDatabase != nil && scriptsDirectory != nil && python3Available
        && FileManager.default.isExecutableFile(atPath: sqlite3Path)

    /// Copy the source DB (and any WAL/SHM sidecars) into a throwaway dir and build a
    /// bridge that targets the copy.
    static func makeSandbox() throws -> Sandbox {
        let fm = FileManager.default
        let src = try #require(sourceDatabase)
        let root = fm.temporaryDirectory.appendingPathComponent("fkr-e2e-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)

        let dbCopy = root.appendingPathComponent("TextReplacements.db")
        try fm.copyItem(at: src, to: dbCopy)
        for suffix in ["-wal", "-shm"] {                       // keep the SQLite WAL set together
            let sidecar = URL(fileURLWithPath: src.path + suffix)
            if fm.fileExists(atPath: sidecar.path) {
                try? fm.copyItem(at: sidecar, to: URL(fileURLWithPath: dbCopy.path + suffix))
            }
        }

        let backupDir = root.appendingPathComponent("backups")
        let bridge = try PythonBridge(databasePath: dbCopy)
        return Sandbox(root: root, bridge: bridge, backupDir: backupDir)
    }
}
