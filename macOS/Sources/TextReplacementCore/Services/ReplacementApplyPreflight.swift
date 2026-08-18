import Foundation

/// One reason Apply cannot run, tied to the row that caused it.
///
/// Distinct from `ReplacementValidationIssue` on purpose: that type is the editor's inline hint
/// vocabulary (warnings included, phrased as rules — "Shortcut cannot be empty."). This one is the
/// *gate* vocabulary — errors only, phrased as an instruction naming the offending row, because it
/// is read at the moment an action was refused rather than while typing.
public struct ReplacementApplyBlocker: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case blank             // neither shortcut nor phrase — an added row never filled in
        case emptyShortcut
        case emptyPhrase
        case duplicateShortcut
    }

    public var id: UUID
    public var replacementID: Replacement.ID?
    public var kind: Kind
    public var message: String

    public init(
        id: UUID = UUID(),
        replacementID: Replacement.ID?,
        kind: Kind,
        message: String
    ) {
        self.id = id
        self.replacementID = replacementID
        self.kind = kind
        self.message = message
    }
}

/// Answers "would Apply be rejected, and why?" *before* the write is attempted.
///
/// The Python writer already enforces these three rules (`replacements_common.preflight`), but it
/// can only report them as a subprocess that exited 1 — the user gets "Apply failed" for something
/// the app knew about the whole time. Checking here turns that into a named row and a fix.
///
/// The rules mirror `replacements_common.check` exactly, including which rows are *exempt*:
/// pending deletions never reach the payload (the codec strips them), and disabled rows are dropped
/// by the writer's own preflight unless `includeDisabled`. Linting either group would block applies
/// that succeed today.
public struct ReplacementApplyPreflight: Sendable {
    public var includeDisabled: Bool

    public init(includeDisabled: Bool = false) {
        self.includeDisabled = includeDisabled
    }

    /// Every reason Apply would be refused, in library order. Empty means the payload is valid.
    public func blockers(in replacements: [Replacement]) -> [ReplacementApplyBlocker] {
        let candidates = replacements.filter {
            !$0.isPendingDeletion && (includeDisabled || $0.enabled)
        }

        // Shortcuts claimed by more than one row. Computed up front so the per-row pass below can
        // stay in library order — grouping order is not deterministic, and an error list that
        // reshuffles between runs is a bad thing to hand someone who is fixing rows one at a time.
        var counts: [String: Int] = [:]
        for row in candidates where !row.normalizedShortcut.isEmpty {
            counts[row.normalizedShortcut, default: 0] += 1
        }

        var blockers: [ReplacementApplyBlocker] = []
        for row in candidates {
            let name = Self.label(for: row)
            let hasShortcut = !row.normalizedShortcut.isEmpty
            // Python compares the phrase untrimmed (`str(phrase) == ""`), so a phrase of pure
            // spaces is legal there. Match that — rejecting it here would block a valid apply.
            let hasPhrase = !row.phrase.isEmpty

            switch (hasShortcut, hasPhrase) {
            case (false, false):
                // The common case by far: File ▸ New Replacement, then Apply without typing.
                // Reported as one blocker rather than two, because it is one thing to fix.
                blockers.append(.init(
                    replacementID: row.id,
                    kind: .blank,
                    message: "\(name) is empty — give it a shortcut and a phrase, or delete the row."
                ))
            case (false, true):
                blockers.append(.init(
                    replacementID: row.id,
                    kind: .emptyShortcut,
                    message: "\(name) has no shortcut — type the abbreviation that should expand it, or delete the row."
                ))
            case (true, false):
                blockers.append(.init(
                    replacementID: row.id,
                    kind: .emptyPhrase,
                    message: "\(name) has no phrase — type the text it should expand to, or delete the row."
                ))
            case (true, true):
                break
            }

            if let count = counts[row.normalizedShortcut], count > 1 {
                blockers.append(.init(
                    replacementID: row.id,
                    kind: .duplicateShortcut,
                    message: "\(count) replacements share the shortcut \(name) — macOS keeps only one, so rename or remove the extras."
                ))
            }
        }
        return blockers
    }

    /// A user-facing explanation for a non-empty blocker list.
    public func explanation(for blockers: [ReplacementApplyBlocker], limit: Int = 3) -> ReplacementFailureExplanation {
        let rows = Set(blockers.compactMap(\.replacementID)).count
        let noun = rows == 1 ? "replacement" : "replacements"
        // Deduplicated: a shortcut used three times produces three identical duplicate messages.
        var seen = Set<String>()
        let unique = blockers.map(\.message).filter { seen.insert($0).inserted }
        let shown = unique.prefix(limit).map { "• \($0)" }.joined(separator: "\n")
        let remaining = unique.count - min(limit, unique.count)
        let more = remaining > 0 ? "\n• …and \(remaining) more." : ""

        return ReplacementFailureExplanation(
            summary: "Nothing was written — \(rows) \(noun) can't be applied",
            detail: shown + more,
            fix: "macOS rejects the whole batch if any row is incomplete. Fix the rows above, then Apply again.",
            rawDetail: unique.joined(separator: "\n")
        )
    }

    /// How a row is named in a message. Prefers the shortcut, falls back to the start of the phrase,
    /// and only says "a blank replacement" when there is genuinely nothing to quote.
    static func label(for replacement: Replacement) -> String {
        let shortcut = replacement.normalizedShortcut
        if !shortcut.isEmpty { return "“\(shortcut)”" }

        let phrase = replacement.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if !phrase.isEmpty {
            let head = phrase.prefix(24)
            let ellipsis = phrase.count > 24 ? "…" : ""
            return "The replacement starting “\(head)\(ellipsis)”"
        }
        return "A blank replacement"
    }
}
