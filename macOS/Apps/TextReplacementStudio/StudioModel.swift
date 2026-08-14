import Foundation
import Observation
import SwiftUI
import TextReplacementCore

/// App state + the actions that bridge to the hardened Python scripts. The blocking subprocess
/// work runs off the main actor (Task.detached) so the UI stays responsive; results are applied
/// back on the main actor.
@MainActor
@Observable
final class StudioModel {
    var replacements: [Replacement] = []
    /// Snapshot of the live macOS DB taken at the last import/apply. Edits are diffed against
    /// this for the Preview Plan sheet and the "recently changed" filter.
    var importedBaseline: [Replacement] = []
    var statusText: String = "Import your replacements from macOS to begin."
    var isBusy = false
    /// Set after a successful Apply; shown in the sidebar footer.
    var lastAppliedAt: Date?
    /// Whether a real import has happened. Distinct from `!replacements.isEmpty` on purpose:
    /// deleting your last replacement leaves a legitimately empty library that must still be
    /// appliable, and the old `replacements.isEmpty` guard made that impossible (GH-2 gotcha 9).
    var hasImported = false
    /// Transient feedback shown as a bottom overlay capsule.
    var toast: ToastMessage?
    /// Push strategy — Merge (add/update) or Replace (add/update/remove).
    var strategy: AppleDatabaseWriter.Strategy = .merge
    /// How the middle list is ordered — default preserves import/insertion order.
    var sortOrder: ReplacementSortOrder = .manual

    /// Survives `createdAt` / `updatedAt` across launches. The import JSON has no timestamp
    /// fields, so without this every launch would re-stamp the library and "Recently Changed"
    /// would always read zero.
    private let timestamps = ReplacementTimestampStore()
    /// Debounce handle for the sidecar write — typing in the phrase editor fires per keystroke.
    private var timestampSaveTask: Task<Void, Never>?

    // MARK: - macOS bridge

    func importFromMacOS() async {
        isBusy = true
        statusText = "Importing from the live macOS database…"
        do {
            let imported = try await Task.detached(priority: .userInitiated) {
                try await AppleDatabaseImporter().importReplacements(
                    request: ReplacementImportRequest(source: .appleDatabase)
                ).imported
            }.value
            // Restore each row's remembered edit history before it reaches the UI.
            let stamped = await timestamps.reconcile(imported)
            replacements = stamped
            importedBaseline = stamped
            hasImported = true
            statusText = "Imported \(stamped.count) replacements from the live macOS database."
            showToast(.init(text: "Imported \(stamped.count) replacements", style: .success))
        } catch {
            statusText = "Import failed: \(error.localizedDescription)"
            showToast(.init(text: "Import failed", style: .error, action: .retryImport))
        }
        isBusy = false
    }

    func pushToMacOS(strategy: AppleDatabaseWriter.Strategy, write: Bool) async {
        guard hasImported else {
            statusText = "Nothing to push — import first."
            return
        }
        isBusy = true
        statusText = write ? "Applying to the live macOS database…" : "Computing dry-run plan…"
        let items = replacements
        let targets = deleteTargets
        do {
            let outcome = try await Task.detached(priority: .userInitiated) {
                let writer = try AppleDatabaseWriter()
                return write
                    ? try writer.apply(items, strategy: strategy, deletes: targets)
                    : try writer.plan(items, strategy: strategy, deletes: targets)
            }.value
            let header = outcome.applied
                ? "Applied to macOS (strategy=\(strategy.rawValue)). Quit/reopen System Settings & affected apps to see changes."
                : "Dry-run plan (strategy=\(strategy.rawValue)) — nothing written:"
            statusText = header + "\n" + outcome.output
            if write {
                lastAppliedAt = Date()
                // The staged rows are gone from the database now, so drop them from the library
                // too. This is the one moment rows really leave the array (GH-2 gotchas 4, 11).
                let survivors = items.filter { !$0.isPendingDeletion }
                replacements = survivors
                importedBaseline = survivors      // edits are now the on-disk truth
                // Re-baseline the sidecar's fingerprints against what we just wrote, so a later
                // launch doesn't read our own apply as an edit made outside the app.
                await timestamps.reconcile(survivors)
                showToast(.init(text: "Applied to macOS — quit & reopen apps to see changes",
                                style: .success))
            }
        } catch {
            statusText = (write ? "Apply failed: " : "Plan failed: ") + error.localizedDescription
            if write { showToast(.init(text: "Apply failed", style: .error, action: .retryApply)) }
        }
        isBusy = false
    }

    // MARK: - Editing

    func index(of id: Replacement.ID?) -> Int? {
        guard let id else { return nil }
        return replacements.firstIndex { $0.id == id }
    }

    /// Read a row by id. Views resolve through this rather than holding an array position.
    func replacement(_ id: Replacement.ID?) -> Replacement? {
        guard let i = index(of: id) else { return nil }
        return replacements[i]
    }

    func toggleEnabled(_ id: Replacement.ID) {
        guard let i = index(of: id) else { return }
        replacements[i].enabled.toggle()
        touch(id)
    }

    /// Stamp a row as edited now and schedule the debounced sidecar write. Every mutation
    /// path goes through here so "Recently Changed" can't silently miss one.
    ///
    /// Resolved by id, never by array position. The previous `touch(_ index: Int)` overload was
    /// removed rather than kept alongside this one: its `indices.contains` bounds check prevented
    /// the crash and thereby *guaranteed* the quieter bug — after a row is removed, a stale index
    /// addresses a different row and the write lands on the neighbour (GH-2 gotcha 3).
    func touch(_ id: Replacement.ID) {
        guard let i = index(of: id) else { return }
        replacements[i].updatedAt = Date()
        scheduleTimestampSave()
    }

    // MARK: - Deletion (staged; nothing leaves the library until Apply)

    /// Stage a row for removal, or discard it outright if it was never on disk.
    ///
    /// A row the database has never seen has nothing to delete *from* — staging it would emit a
    /// delete target the writer would then refuse as "no active row with that shortcut". So a
    /// never-applied row is simply dropped (GH-2 gotcha 11).
    func deleteReplacement(_ id: Replacement.ID) {
        guard let i = index(of: id) else { return }
        let isOnDisk = importedBaseline.contains { $0.id == replacements[i].id }
        if isOnDisk {
            replacements[i].isPendingDeletion = true
            touch(id)
        } else {
            replacements.remove(at: i)
            scheduleTimestampSave()
        }
    }

    /// Un-stage a pending deletion. Cheap because the row never left the array — which is exactly
    /// why deletion is modelled as a flag and not a removal.
    func restoreReplacement(_ id: Replacement.ID) {
        guard let i = index(of: id), replacements[i].isPendingDeletion else { return }
        replacements[i].isPendingDeletion = false
        touch(id)
    }

    var pendingDeletions: [Replacement] { replacements.filter(\.isPendingDeletion) }

    /// Everything Apply must remove, from the two sources that can produce a removal.
    ///
    /// The second source is the subtle one: the writer keys by shortcut and discards our ids, so a
    /// *rename* it isn't told about reads as an unrelated add and silently leaves the old row
    /// behind. Emitting the before-shortcut turns a rename into delete-old + add-new
    /// (GH-2 gotchas 10, 15).
    var deleteTargets: [ReplacementDeleteTarget] {
        let baselineByID = Dictionary(uniqueKeysWithValues: importedBaseline.map { ($0.id, $0) })
        var targets: [String: ReplacementDeleteTarget] = [:]

        for row in replacements {
            guard let original = baselineByID[row.id] else { continue }
            if row.isPendingDeletion {
                targets[original.normalizedShortcut] = .init(
                    shortcut: original.normalizedShortcut, fingerprint: original.nativeFingerprint
                )
            } else if original.normalizedShortcut != row.normalizedShortcut {
                targets[original.normalizedShortcut] = .init(
                    shortcut: original.normalizedShortcut, fingerprint: original.nativeFingerprint
                )
            }
        }

        // A shortcut that has been re-used by a surviving row is not a deletion — the writer would
        // reject the payload as self-contradictory (present in both items and deletes).
        let liveShortcuts = Set(
            replacements.filter { !$0.isPendingDeletion }.map(\.normalizedShortcut)
        )
        return targets.values
            .filter { !liveShortcuts.contains($0.shortcut) }
            .sorted { $0.shortcut < $1.shortcut }
    }

    /// Coalesce the sidecar write — the phrase editor's binding fires on every keystroke.
    private func scheduleTimestampSave() {
        timestampSaveTask?.cancel()
        timestampSaveTask = Task {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            await timestamps.record(replacements)
        }
    }

    /// Create a blank replacement at the top of the library and return its id so the
    /// caller can select it and drop the cursor into the shortcut field.
    @discardableResult
    func addReplacement(groupName: String? = nil) -> Replacement.ID {
        let new = Replacement(shortcut: "", phrase: "", enabled: true, groupName: groupName)
        replacements.insert(new, at: 0)
        // Not persisted yet — a row with no shortcut isn't a replacement. The first keystroke
        // in the shortcut field goes through `touch` and records it.
        return new.id
    }

    /// Validation issues (empty/whitespace/duplicate) for one row — reuses the core
    /// `DefaultReplacementLinter` so the editor's inline hints match what Apply enforces.
    func issues(for id: Replacement.ID?) -> [ReplacementValidationIssue] {
        guard let id else { return [] }
        return DefaultReplacementLinter().validate(replacements).filter { $0.replacementID == id }
    }

    private func showToast(_ toast: ToastMessage) {
        withAnimation(Theme.spring) { self.toast = toast }
    }

    // MARK: - Derived collections

    /// Distinct groups present in the library, with counts, sorted by size then name.
    var groups: [GroupSummary] {
        var counts: [String: Int] = [:]
        for r in replacements {
            guard let g = r.groupName, !g.isEmpty else { continue }
            counts[g, default: 0] += 1
        }
        return counts
            .map { GroupSummary(name: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    func count(for filter: ReplacementFilter) -> Int { filteredUnsorted(filter).count }

    /// Rows for the middle list: the active filter narrowed by the search query, sorted by
    /// `sortOrder`. Search matching and shortcut-first ranking are `matchingSearch` — see there.
    func filtered(_ filter: ReplacementFilter, search: String) -> [Replacement] {
        filteredUnsorted(filter).sorted(order: sortOrder).matchingSearch(search)
    }

    private func filteredUnsorted(_ filter: ReplacementFilter) -> [Replacement] {
        switch filter {
        case .all:
            return replacements
        case .disabled:
            return replacements.filter { !$0.enabled }
        case .ungrouped:
            return replacements.filter { ($0.groupName ?? "").isEmpty }
        case .recentlyChanged:
            let now = Date()
            return replacements.filter { $0.isRecentlyChanged(now: now) }
        case .duplicates:
            let dupes = duplicateShortcuts
            return replacements.filter { dupes.contains($0.normalizedShortcut.lowercased()) }
        case .group(let name):
            return replacements.filter { $0.groupName == name }
        }
    }

    private var duplicateShortcuts: Set<String> {
        var seen: [String: Int] = [:]
        for r in replacements {
            seen[r.normalizedShortcut.lowercased(), default: 0] += 1
        }
        return Set(seen.filter { $0.value > 1 }.keys)
    }

    // MARK: - Preview diff (current edits vs. the imported baseline)

    /// What Apply would change, diffed against the last import.
    ///
    /// Pending deletions are the tricky part. They stay in `replacements`, so they are NOT missing
    /// from the id set — dropping the old `strategy == .replace` gate alone would have let them
    /// fall silently into `updates` and shown the user the wrong plan. They have to be pulled out
    /// explicitly, before the add/update bucketing runs (GH-2 gotcha 14).
    func planDiff(strategy: AppleDatabaseWriter.Strategy) -> PlanDiff {
        let baselineByID = Dictionary(uniqueKeysWithValues: importedBaseline.map { ($0.id, $0) })
        let surviving = replacements.filter { !$0.isPendingDeletion }
        let survivingIDs = Set(surviving.map(\.id))

        var adds: [Replacement] = []
        var updates: [ReplacementUpdate] = []
        var unchanged = 0
        for r in surviving {
            if let original = baselineByID[r.id] {
                if original.contentEquals(r) { unchanged += 1 }
                else { updates.append(.init(before: original, after: r)) }
            } else {
                adds.append(r)
            }
        }

        // Staged deletions count under BOTH strategies — that is what makes Merge able to remove a
        // single row. Replace additionally sweeps anything the baseline had and we no longer do.
        var removes = replacements.filter(\.isPendingDeletion).compactMap { baselineByID[$0.id] }
        if strategy == .replace {
            let alreadyRemoved = Set(removes.map(\.id))
            removes += importedBaseline.filter {
                !survivingIDs.contains($0.id) && !alreadyRemoved.contains($0.id)
            }
        }
        return PlanDiff(adds: adds, updates: updates, removes: removes, unchanged: unchanged)
    }
}

// MARK: - Supporting value types

struct GroupSummary: Identifiable, Hashable {
    var name: String
    var count: Int
    var id: String { name }
    var color: Color { Theme.groupColor(name) }
}

struct ToastMessage: Identifiable, Equatable {
    enum Style { case success, error, info }
    enum Action: Equatable { case retryApply, retryImport }
    let id = UUID()
    var text: String
    var style: Style
    var action: Action?

    init(text: String, style: Style, action: Action? = nil) {
        self.text = text
        self.style = style
        self.action = action
    }
}

struct ReplacementUpdate: Identifiable {
    var before: Replacement
    var after: Replacement
    var id: UUID { after.id }
}

struct PlanDiff {
    var adds: [Replacement]
    var updates: [ReplacementUpdate]
    var removes: [Replacement]
    var unchanged: Int
    var total: Int { adds.count + updates.count + removes.count }
    var isEmpty: Bool { total == 0 }
}

extension Replacement {
    /// Equality on user-meaningful fields, ignoring `createdAt` / `updatedAt`.
    func contentEquals(_ other: Replacement) -> Bool {
        shortcut == other.shortcut
            && phrase == other.phrase
            && enabled == other.enabled
            && (groupName ?? "") == (other.groupName ?? "")
            && (notes ?? "") == (other.notes ?? "")
    }
}
