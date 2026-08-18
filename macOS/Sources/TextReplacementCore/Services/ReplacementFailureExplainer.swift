import Foundation

/// A failure, in the three parts a person actually needs: what didn't happen, why, and what to do.
///
/// `rawDetail` keeps the original technical text so it can be copied into a bug report without
/// putting `json_to_apple_sqlite.py failed (exit 1)` in front of someone who just wanted to save.
public struct ReplacementFailureExplanation: Sendable, Equatable {
    /// One short line naming the outcome, e.g. "Nothing was written — macOS blocked access".
    public var summary: String
    /// What specifically went wrong.
    public var detail: String
    /// The next action to take, when there is one worth naming.
    public var fix: String?
    /// The underlying message, unedited.
    public var rawDetail: String?

    public init(summary: String, detail: String, fix: String? = nil, rawDetail: String? = nil) {
        self.summary = summary
        self.detail = detail
        self.fix = fix
        self.rawDetail = rawDetail
    }

    /// Detail and fix as one block, for surfaces that show a single body of text.
    public var body: String {
        guard let fix, !fix.isEmpty else { return detail }
        return detail + "\n" + fix
    }
}

/// Turns the errors this app can actually produce into `ReplacementFailureExplanation`s.
///
/// Two kinds arrive here. Bridge errors and the Python writer's own `ValueError`/`RuntimeError`
/// messages are already written in plain English — those are passed through, stripped of the
/// subprocess chrome, and given a fix line. SQLite and OS-level messages are not ("attempt to write
/// a readonly database" means "grant Full Disk Access"), so those are matched and rewritten.
public enum ReplacementFailureExplainer {
    public enum Operation: Sendable {
        case importing
        case planning
        case applying

        /// What did *not* happen. Stated first because it is the user's first question, and because
        /// "nothing was written" is the reassurance a failed write most needs to lead with.
        var outcome: String {
            switch self {
            case .importing: return "Import failed"
            case .planning:  return "Couldn't build the preview"
            case .applying:  return "Nothing was written"
            }
        }
    }

    public static func explain(_ error: Error, during operation: Operation) -> ReplacementFailureExplanation {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let message = distill(raw)

        if let known = match(message, operation: operation, raw: raw) {
            return known
        }

        // Unrecognized. Pass the message through rather than inventing a cause — an honest
        // "here is what the writer said" beats a confident wrong guess.
        let detail = message.isEmpty
            ? "The helper that talks to macOS exited without saying why."
            : message
        return ReplacementFailureExplanation(
            summary: "\(operation.outcome) — \(firstClause(detail))",
            detail: detail,
            fix: "If this keeps happening, use Copy Details and file it with the message above.",
            rawDetail: raw
        )
    }

    // MARK: - Known causes

    private struct Cause {
        let needles: [String]
        let detail: String
        let fix: String?
        /// Overrides the headline clause when the distilled message would read badly.
        let headline: String
    }

    private static let causes: [Cause] = [
        Cause(
            needles: ["database is locked", "database is busy"],
            detail: "Another process is holding the macOS Text Replacements database open.",
            fix: "Quit System Settings, wait a moment, and try again.",
            headline: "the database is in use"
        ),
        Cause(
            needles: [
                "attempt to write a readonly database", "readonly database",
                "unable to open database file", "operation not permitted", "permission denied",
            ],
            detail: "macOS blocked access to the Text Replacements database.",
            fix: "Grant this app Full Disk Access in System Settings ▸ Privacy & Security ▸ Full Disk Access, then quit and reopen the app.",
            headline: "macOS blocked access"
        ),
        Cause(
            needles: ["database not found", "no such file or directory"],
            detail: "This Mac has no Text Replacements database yet — macOS only creates it once you save your first replacement.",
            fix: "Add one replacement in System Settings ▸ Keyboard ▸ Text Replacements, then Import here.",
            headline: "macOS hasn't created the database yet"
        ),
        Cause(
            needles: ["table not found", "missing expected columns", "cannot infer required column"],
            detail: "The Text Replacements database isn't in the shape this app expects, usually because it has never held a replacement.",
            fix: "Add one replacement in System Settings ▸ Keyboard ▸ Text Replacements, then Import here.",
            headline: "the database is missing its layout"
        ),
        Cause(
            needles: ["disk image is malformed", "disk i/o error", "file is not a database"],
            detail: "The Text Replacements database is damaged, so it was left untouched.",
            fix: "Earlier backups are in ~/Library/Application Support/TextReplacementStudio/db-backups.",
            headline: "the database is damaged"
        ),
        Cause(
            needles: ["changed since the plan was computed", "no active row with that shortcut"],
            detail: "", // the writer's own sentence is clearer than anything generic — kept below
            fix: "Import again to pick up the current state, then Apply.",
            headline: "your replacements changed in macOS"
        ),
        Cause(
            needles: ["active rows share this shortcut", "resolve the duplicate first"],
            detail: "",
            fix: "Remove the duplicate in System Settings ▸ Keyboard ▸ Text Replacements, then Import again.",
            headline: "a shortcut is duplicated in macOS"
        ),
        Cause(
            needles: ["present in both items and deletes"],
            detail: "A shortcut is set to be kept and removed in the same batch, so the whole batch was refused.",
            fix: "Import again to resync, then re-apply your changes.",
            headline: "the plan contradicts itself"
        ),
        Cause(
            needles: ["shortcut is empty", "phrase is empty", "duplicate shortcut"],
            detail: "", // the writer names the offending item; keep its wording
            fix: "Fix the flagged replacements, then Apply again.",
            headline: "a replacement is incomplete"
        ),
        Cause(
            needles: ["no zwasdeleted column", "soft-delete only"],
            detail: "This Mac's database has no way to mark a row deleted, and this app will not hard-delete rows out of Apple's table.",
            fix: "Remove the replacement in System Settings ▸ Keyboard ▸ Text Replacements instead, then Import here.",
            headline: "deletion isn't supported on this database"
        ),
        Cause(
            needles: ["python 3 isn’t available", "python 3 isn't available", "failed to launch python"],
            detail: "This app needs python3 to read and write the macOS Text Replacements database, and none was found.",
            fix: "Run “xcode-select --install” in Terminal, or set the FKR_PYTHON environment variable to a python3 executable.",
            headline: "python3 is missing"
        ),
        Cause(
            needles: ["scripts/ directory", "script not found in scripts/"],
            detail: "The helper scripts that talk to macOS are missing from the app.",
            fix: "Reinstall the app, or set FKR_SCRIPTS_DIR to this repo's scripts/ folder.",
            headline: "the app install is incomplete"
        ),
    ]

    private static func match(_ message: String, operation: Operation, raw: String) -> ReplacementFailureExplanation? {
        let haystack = message.lowercased()
        guard let cause = causes.first(where: { $0.needles.contains(where: haystack.contains) }) else {
            return nil
        }
        // An empty `detail` means the underlying message says it better than a generic rewrite would.
        let detail = cause.detail.isEmpty ? message : cause.detail
        return ReplacementFailureExplanation(
            summary: "\(operation.outcome) — \(cause.headline)",
            detail: detail,
            fix: cause.fix,
            rawDetail: raw
        )
    }

    // MARK: - Message cleanup

    /// Strips the subprocess chrome so the user reads the cause, not the plumbing.
    ///
    /// `"json_to_apple_sqlite.py failed (exit 1): error: item 2: phrase is empty"`
    /// becomes `"item 2: phrase is empty"`.
    static func distill(_ raw: String) -> String {
        var text = raw
        if let marker = text.range(of: "failed (exit "),
           let close = text.range(of: "): ", range: marker.upperBound..<text.endIndex) {
            text = String(text[close.upperBound...])
        }

        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // The writer's own failures are the `error: …` line; a traceback above it is noise.
        if let reported = lines.last(where: { $0.lowercased().hasPrefix("error: ") }) {
            return String(reported.dropFirst("error: ".count)).trimmingCharacters(in: .whitespaces)
        }
        // A stack trace with no `error:` line — the last line is the exception.
        if lines.count > 3, let last = lines.last {
            return last
        }
        return lines.joined(separator: " ")
    }

    /// The first sentence of a detail, lowercased for use inside a headline.
    private static func firstClause(_ detail: String) -> String {
        let sentence = detail.split(separator: ".").first.map(String.init) ?? detail
        let clipped = sentence.count > 72 ? String(sentence.prefix(72)) + "…" : sentence
        guard let first = clipped.first, first.isUppercase, !clipped.hasPrefix("FKR") else { return clipped }
        return clipped.prefix(1).lowercased() + clipped.dropFirst()
    }
}
