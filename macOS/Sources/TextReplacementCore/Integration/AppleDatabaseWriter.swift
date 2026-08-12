import Foundation

/// Writes the live macOS Text Replacements DB by shelling out to the hardened
/// `json_to_apple_sqlite.py` (dry-run plan by default; `--apply` backs up then writes inside
/// BEGIN IMMEDIATE, with the tombstone / Z_PK / Z_ENT fixes from the Codex + Agy review).
public struct AppleDatabaseWriter: Sendable {
    public enum Strategy: String, Sendable, CaseIterable {
        case merge   // add/update only
        case replace // also soft-delete shortcuts missing from the list
    }

    public struct Outcome: Sendable {
        public let applied: Bool   // false = dry-run plan only
        public let strategy: Strategy
        public let output: String  // the writer's stdout (the plan, or the apply summary)
        public let stderr: String
    }

    private let bridge: PythonBridge
    private let codec: any CanonicalReplacementCoding
    private let backupDirectory: URL

    public init(
        bridge: PythonBridge,
        codec: any CanonicalReplacementCoding = CanonicalReplacementCodec(),
        backupDirectory: URL? = nil
    ) {
        self.bridge = bridge
        self.codec = codec
        self.backupDirectory = backupDirectory ?? Self.defaultBackupDirectory()
    }

    public init() throws {
        try self.init(bridge: PythonBridge())
    }

    /// Backups go to ~/Library/Application Support (always user-writable). The Python writer's own
    /// default is CWD-relative, which is a read-only path (`/`) when launched as a .app bundle.
    static func defaultBackupDirectory() -> URL {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )) ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("TextReplacementStudio", isDirectory: true)
            .appendingPathComponent("db-backups", isDirectory: true)
    }

    /// Dry-run: returns the writer's plan (add/update/delete/skip) without touching the DB.
    ///
    /// `deletes` carries targeted removals. They are honoured under **either** strategy — that is
    /// the whole point: Merge previously had no way to express "remove this one row", so a delete
    /// either did nothing or required the blunt Replace sweep (GH-2 gotcha 1).
    public func plan(
        _ replacements: [Replacement],
        strategy: Strategy = .merge,
        includeDisabled: Bool = false,
        deletes: [ReplacementDeleteTarget] = []
    ) throws -> Outcome {
        try run(replacements, strategy: strategy, includeDisabled: includeDisabled, deletes: deletes, apply: false)
    }

    /// Apply for real. The Python writer makes a timestamped backup before writing.
    public func apply(
        _ replacements: [Replacement],
        strategy: Strategy = .merge,
        includeDisabled: Bool = false,
        deletes: [ReplacementDeleteTarget] = []
    ) throws -> Outcome {
        try run(replacements, strategy: strategy, includeDisabled: includeDisabled, deletes: deletes, apply: true)
    }

    private func run(
        _ replacements: [Replacement],
        strategy: Strategy,
        includeDisabled: Bool,
        deletes: [ReplacementDeleteTarget],
        apply: Bool
    ) throws -> Outcome {
        let inURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fkr-apply-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: inURL) }
        try codec.encode(replacements, deletes: deletes).write(to: inURL)

        var arguments = [
            inURL.path,
            "--db", bridge.databasePath.path,
            "--strategy", strategy.rawValue,
            "--backup-dir", backupDirectory.path,
        ]
        if includeDisabled { arguments.append("--include-disabled") }
        if apply { arguments.append("--apply") }

        let result = try bridge.run("json_to_apple_sqlite.py", arguments)
        guard result.ok else {
            throw ReplacementImportExportError.invalidInput(
                "json_to_apple_sqlite.py failed (exit \(result.exitCode)): " +
                (result.stderr.isEmpty ? result.stdout : result.stderr)
            )
        }
        return Outcome(applied: apply, strategy: strategy, output: result.stdout, stderr: result.stderr)
    }
}
