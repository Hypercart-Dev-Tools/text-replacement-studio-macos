import SwiftUI
import TextReplacementCore

/// Middle column: an in-column search field, the filtered list of replacements as
/// custom rows, and a footer with counts and an add button.
struct ReplacementListView: View {
    let model: StudioModel
    @Binding var searchText: String
    let selectedFilter: ReplacementFilter
    @Binding var selectedReplacementID: Replacement.ID?
    let onAdd: () -> Void
    let onDelete: (Replacement.ID) -> Void
    let onRestore: (Replacement.ID) -> Void

    @FocusState private var searchFocused: Bool
    /// Whether the row list itself holds focus. ⌫ is gated on this so the key cannot delete a
    /// replacement while the cursor is in the search field or an editor (GH-2, Phase 3).
    @FocusState private var listFocused: Bool

    private var rows: [Replacement] { model.filtered(selectedFilter, search: searchText) }
    private var disabledCount: Int { rows.filter { !$0.enabled && !$0.isPendingDeletion }.count }
    private var pendingDeleteCount: Int { rows.filter(\.isPendingDeletion).count }

    private var sortOrderBinding: Binding<ReplacementSortOrder> {
        Binding(get: { model.sortOrder }, set: { model.sortOrder = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField
            content
            footer
        }
        .background(Theme.window)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.text3)
            TextField("Search replacements", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.text3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            } else {
                Text("⌘F").font(Theme.monoSmall).foregroundStyle(Theme.text3)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(Theme.elevated, in: RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .strokeBorder(Theme.separator2, lineWidth: 1)
        )
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, Theme.Space.s)
        .background(
            Button("") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
        )
    }

    // MARK: List

    @ViewBuilder private var content: some View {
        if rows.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { r in
                            ReplacementRow(
                                replacement: r,
                                isSelected: selectedReplacementID == r.id,
                                isEnabled: enabledBinding(for: r),
                                onSelect: { selectedReplacementID = r.id }
                            )
                            .id(r.id)
                            .contextMenu {
                                if r.isPendingDeletion {
                                    Button("Restore") { onRestore(r.id) }
                                } else {
                                    Button("Delete", role: .destructive) { onDelete(r.id) }
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                }
                .focusable()
                .focused($listFocused)
                .focusEffectDisabled()
                .onTapGesture { listFocused = true }
                // Scoped to list focus on purpose: unscoped, this would fire mid-word in the
                // phrase editor or the search field.
                .onDeleteCommand {
                    guard listFocused, let id = selectedReplacementID,
                          let row = model.replacement(id) else { return }
                    row.isPendingDeletion ? onRestore(id) : onDelete(id)
                }
                .onChange(of: rows.map(\.id)) {
                    guard let id = selectedReplacementID else { return }
                    withAnimation(Theme.spring) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: model.replacements.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(Theme.text3)
            Text(model.replacements.isEmpty ? "No replacements yet" : "No matches")
                .font(Theme.bodyMed)
                .foregroundStyle(Theme.text2)
            if model.replacements.isEmpty {
                Text("Import from macOS, or add one.")
                    .font(Theme.body)
                    .foregroundStyle(Theme.text3)
                Button(action: onAdd) {
                    Label("New Replacement", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, Theme.Space.xs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Theme.separator).frame(height: 1)
            HStack(spacing: Theme.Space.s) {
                Text("\(rows.count) replacement\(rows.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text2)
                if pendingDeleteCount > 0 {
                    Circle().fill(Theme.diffRemove).frame(width: 3, height: 3)
                    Text("\(pendingDeleteCount) to delete")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.diffRemove)
                }
                if disabledCount > 0 {
                    Circle().fill(Theme.text3).frame(width: 3, height: 3)
                    Text("\(disabledCount) disabled")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.text2)
                }
                Spacer()
                Menu {
                    Picker("Sort", selection: sortOrderBinding) {
                        ForEach(ReplacementSortOrder.allCases, id: \.self) { order in
                            Text(order.label).tag(order)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.system(size: 11, weight: .medium))
                        if model.sortOrder != .manual {
                            Text(model.sortOrder.label)
                                .font(.system(size: 11))
                        }
                    }
                    .foregroundStyle(Theme.text2)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(Theme.hover, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Sort: \(model.sortOrder.label)")
                .accessibilityLabel("Sort replacements, currently \(model.sortOrder.label)")
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.text2)
                        .frame(width: 24, height: 24)
                        .background(Theme.hover, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("New Replacement (⌘N)")
                .accessibilityLabel("New replacement")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
    }

    // MARK: Actions

    private func enabledBinding(for r: Replacement) -> Binding<Bool> {
        Binding(
            get: { model.index(of: r.id).map { model.replacements[$0].enabled } ?? r.enabled },
            set: { _ in model.toggleEnabled(r.id) }
        )
    }
}
