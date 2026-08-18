import SwiftUI
import TextReplacementCore

/// Exposes ContentView's "add" action to the menu bar so File ▸ New Replacement (⌘N)
/// drives the same code path as the in-window affordances.
struct NewReplacementKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var newReplacement: (() -> Void)? {
        get { self[NewReplacementKey.self] }
        set { self[NewReplacementKey.self] = newValue }
    }
}

/// Exposes ContentView's "apply" action to the menu bar so File ▸ Apply to macOS (⌘S)
/// drives the same confirmation path as the toolbar button. Published as nil while the
/// action isn't available, which is what greys the menu item out.
/// Exposes the list's delete/restore action to the menu bar so Edit ▸ Delete Replacement (⌘⌫)
/// drives the same code path as the footer button and the ⌫ key.
struct DeleteReplacementKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var deleteReplacement: (() -> Void)? {
        get { self[DeleteReplacementKey.self] }
        set { self[DeleteReplacementKey.self] = newValue }
    }
}

struct ApplyToMacOSKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var applyToMacOS: (() -> Void)? {
        get { self[ApplyToMacOSKey.self] }
        set { self[ApplyToMacOSKey.self] = newValue }
    }
}

struct ContentView: View {
    @State private var model = StudioModel()
    @State private var searchText = ""
    @State private var selectedFilter: ReplacementFilter = .all
    @State private var selectedReplacementID: Replacement.ID?
    @State private var showPreview = false
    @State private var confirmApply = false

    private var strategyBinding: Binding<AppleDatabaseWriter.Strategy> {
        Binding(get: { model.strategy }, set: { model.strategy = $0 })
    }

    /// Whether Apply is currently available — shared by the toolbar button and the
    /// File ▸ Apply to macOS menu item so the two can't disagree.
    /// Deliberately keyed on `hasImported`, not `!replacements.isEmpty`: deleting your last
    /// replacement leaves an empty library that still needs applying (GH-2 gotcha 9).
    private var canApply: Bool { !model.isBusy && model.hasImported }

    private var pendingRemovals: [Replacement] {
        model.planDiff(strategy: model.strategy).removes
    }

    private var applyButtonTitle: String {
        let count = pendingRemovals.count
        return count > 0 ? "Delete \(count) & Apply" : "Apply (\(model.strategy.rawValue))"
    }

    /// Names the shortcuts about to be removed. A bare count is not a confirmation — deletion is
    /// the one action here with no undo once it reaches the database.
    private var applyConfirmationMessage: String {
        let base = "A timestamped backup is written first. Afterward you may need to quit and reopen System Settings and affected apps for changes to show."
        let removes = pendingRemovals
        guard !removes.isEmpty else { return base }
        let names = removes.prefix(8).map(\.shortcut).joined(separator: ", ")
        let more = removes.count > 8 ? " and \(removes.count - 8) more" : ""
        let noun = removes.count == 1 ? "replacement" : "replacements"
        return "This will DELETE \(removes.count) \(noun) from macOS: \(names)\(more).\n\n" + base
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model, selectedFilter: $selectedFilter)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
        } content: {
            ReplacementListView(
                model: model,
                searchText: $searchText,
                selectedFilter: selectedFilter,
                selectedReplacementID: $selectedReplacementID,
                onAdd: newReplacement,
                onDelete: { model.deleteReplacement($0) },
                onRestore: { model.restoreReplacement($0) }
            )
            .navigationSplitViewColumnWidth(min: 340, ideal: 392, max: 520)
        } detail: {
            ReplacementDetailEditor(model: model, replacementID: selectedReplacementID)
                .navigationSplitViewColumnWidth(min: 380, ideal: 520)
        }
        .navigationSplitViewStyle(.balanced)
        .navigationTitle("Text Replacements")
        .navigationSubtitle("\(model.replacements.count) replacement\(model.replacements.count == 1 ? "" : "s")")
        .frame(minWidth: 820, minHeight: 520)
        .tint(Theme.accent)
        .toolbar { toolbarContent }
        .focusedValue(\.newReplacement, newReplacement)
        .focusedValue(\.deleteReplacement, selectedReplacementID == nil ? nil : {
            guard let id = selectedReplacementID, let row = model.replacement(id) else { return }
            row.isPendingDeletion ? model.restoreReplacement(id) : model.deleteReplacement(id)
        })
        .focusedValue(\.applyToMacOS, canApply ? requestApply : nil)
        .overlay(alignment: .bottom) { toastOverlay }
        .task {
            if model.replacements.isEmpty { await model.importFromMacOS() }
            if selectedReplacementID == nil { selectedReplacementID = model.replacements.first?.id }
        }
        .task(id: model.toast?.id) { await autoDismissToast() }
        .sheet(isPresented: $showPreview) {
            PreviewPlanSheet(
                model: model,
                strategy: model.strategy,
                onApply: { showPreview = false; requestApply() },
                onCancel: { showPreview = false }
            )
        }
        .confirmationDialog(
            "Write to your live macOS Text Replacements database?",
            isPresented: $confirmApply,
            titleVisibility: .visible
        ) {
            Button(applyButtonTitle, role: .destructive) {
                Task { await model.pushToMacOS(strategy: model.strategy, write: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(applyConfirmationMessage)
        }
    }

    // MARK: Toolbar — Import · Merge/Replace · Preview · Apply

    @ToolbarContentBuilder private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if model.isBusy {
                ProgressView().controlSize(.small)
            }

            Button {
                Task { await model.importFromMacOS() }
            } label: {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            .disabled(model.isBusy)
            .help("Re-read the live macOS Text Replacements database.")

            Picker("Strategy", selection: strategyBinding) {
                Text("Merge").tag(AppleDatabaseWriter.Strategy.merge)
                Text("Replace").tag(AppleDatabaseWriter.Strategy.replace)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Merge adds & updates; Replace also removes shortcuts no longer present.")

            Button("Preview Plan") { showPreview = true }
                .disabled(!model.hasImported)
                .help("See what Apply would change — writes nothing.")

            Button("Apply to macOS…") { requestApply() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canApply)
                .help("Write your edits to the live macOS database (backup made first).")
        }
    }

    // MARK: Toast

    @ViewBuilder private var toastOverlay: some View {
        if let toast = model.toast {
            ToastView(
                toast: toast,
                onAction: { action in
                    withAnimation(Theme.spring) { model.toast = nil }
                    switch action {
                    case .retryApply:  requestApply()
                    case .retryImport: Task { await model.importFromMacOS() }
                    case .reveal(let id): reveal(id)
                    }
                },
                onDismiss: { withAnimation(Theme.spring) { model.toast = nil } }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func autoDismissToast() async {
        guard let toast = model.toast, toast.style != .error else { return }
        try? await Task.sleep(for: .seconds(4))
        if model.toast?.id == toast.id {
            withAnimation(Theme.spring) { model.toast = nil }
        }
    }

    // MARK: Apply

    /// Ask to apply. Incomplete rows are reported here rather than after the confirmation, so the
    /// user is never walked through a destructive "write to your live database?" dialog for a batch
    /// macOS was always going to reject.
    private func requestApply() {
        guard !model.reportApplyBlockers() else { return }
        confirmApply = true
    }

    /// Select the row a failure named and make sure it is actually on screen — the active filter
    /// or search may be hiding it, which would make "Show Me" appear to do nothing.
    private func reveal(_ id: Replacement.ID) {
        searchText = ""
        if model.filtered(selectedFilter, search: "").contains(where: { $0.id == id }) == false {
            selectedFilter = .all
        }
        selectedReplacementID = id
    }

    // MARK: New replacement

    /// Add a blank replacement and select it for editing. Clears the search and makes
    /// sure the new row is visible: if a Group is filtered, the row joins that group;
    /// otherwise the view falls back to All (so it isn't hidden by Disabled/Duplicates/etc.).
    private func newReplacement() {
        searchText = ""
        let group: String?
        if case let .group(name) = selectedFilter {
            group = name
        } else {
            group = nil
            if selectedFilter != .all { selectedFilter = .all }
        }
        selectedReplacementID = model.addReplacement(groupName: group)
    }
}
