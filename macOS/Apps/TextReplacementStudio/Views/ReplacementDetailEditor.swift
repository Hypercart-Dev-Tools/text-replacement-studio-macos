import AppKit
import SwiftUI
import TextReplacementCore

/// Right column: the content-first inspector for the selected replacement —
/// shortcut key-cap, enable toggle, the expanded phrase in a roomy well, then
/// Group and Notes rows. Edits write straight back into the model.
struct ReplacementDetailEditor: View {
    let model: StudioModel
    let replacementID: Replacement.ID?

    private static let noneTag = "\u{0}none"   // sentinel for "Ungrouped" in the picker

    @FocusState private var shortcutFocused: Bool
    @State private var copied = false

    var body: some View {
        if let id = replacementID, let row = model.replacement(id) {
            let issues = model.issues(for: id)
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if row.isPendingDeletion { pendingDeletionBanner(id) }
                        Group {
                            header(id, issues: issues.filter { $0.code.hasPrefix("shortcut") })
                            Spacer().frame(height: 26)
                            phraseSection(id, issues: issues.filter { $0.code.hasPrefix("phrase") })
                            Spacer().frame(height: 18)
                            groupRow(id)
                            notesRow(id)
                        }
                        .disabled(row.isPendingDeletion)

                        if !row.isPendingDeletion { deleteRow(id) }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 26)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.window)
                .onChange(of: replacementID) { focusIfBlank(); copied = false }
                .onAppear { focusIfBlank() }

                undoDeletesBlankRow(id, row)
            }
        } else {
            emptyState
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied = true
    }

    /// Drop the cursor into the shortcut field when a freshly-added (blank) row is shown.
    private func focusIfBlank() {
        guard let row = model.replacement(replacementID), row.shortcut.isEmpty else { return }
        shortcutFocused = true
    }

    /// Shown in place of editing when a row is staged for removal. This banner is the reason
    /// deletion is a flag rather than a removal: the row is still here, so there is somewhere to
    /// put Restore without building an undo stack (GH-2 gotcha 16).
    private func pendingDeletionBanner(_ id: Replacement.ID) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 12))
                .foregroundStyle(Theme.diffRemove)
            VStack(alignment: .leading, spacing: 2) {
                Text("Staged for deletion").font(Theme.bodyMed).foregroundStyle(Theme.text)
                Text("Removed from macOS on the next Apply. Nothing has been deleted yet.")
                    .font(.system(size: 11)).foregroundStyle(Theme.text2)
            }
            Spacer()
            Button("Restore") { model.restoreReplacement(id) }
                .buttonStyle(.bordered)
        }
        .padding(12)
        .background(Theme.diffRemove.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.diffRemove.opacity(0.45), lineWidth: 1)
        )
        .padding(.bottom, 20)
    }

    // MARK: Header — shortcut + enabled

    private func header(_ id: Replacement.ID, issues: [ReplacementValidationIssue]) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 9) {
                caption("SHORTCUT")
                TextField("shortcut", text: stringBinding(id, \.shortcut))
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, design: .monospaced).weight(.medium))
                    .foregroundStyle(Theme.text)
                    .focused($shortcutFocused)
                    .frame(minWidth: 60)
                    .fixedSize()
                    .padding(.horizontal, 15)
                    .frame(height: 40)
                    .background(Theme.keycapBG, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(borderColor(issues, base: Theme.keycapBorder), lineWidth: 1)
                    )
                hintList(issues)
            }
            Spacer()
            HStack(spacing: 10) {
                Text("Enabled").font(Theme.bodyMed).foregroundStyle(Theme.text2)
                StudioToggle(isOn: boolBinding(id, \.enabled), controlSize: .regular)
            }
            .padding(.top, 27)
        }
    }

    // MARK: Phrase

    private func phraseSection(_ id: Replacement.ID, issues: [ReplacementValidationIssue]) -> some View {
        let phrase = model.replacement(id)?.phrase ?? ""
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                caption("EXPANDED PHRASE")
                Spacer()
                Text("\(phrase.count) character\(phrase.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.text3)
                    .monospacedDigit()
                Button {
                    copyToClipboard(phrase)
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                        .foregroundStyle(copied ? Theme.accent : Theme.text3)
                }
                .buttonStyle(.plain)
                .help("Copy expanded phrase")
                .task(id: copied) {
                    guard copied else { return }
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            TextEditor(text: stringBinding(id, \.phrase))
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .padding(14)
                .frame(minHeight: 220, maxHeight: .infinity)
                .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(borderColor(issues, base: Theme.separator2), lineWidth: 1)
                )
            hintList(issues)
        }
    }

    // MARK: Validation hints

    /// Inline issue rows shown under a field. Errors read red, warnings amber.
    @ViewBuilder private func hintList(_ issues: [ReplacementValidationIssue]) -> some View {
        if !issues.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(issues) { issue in
                    Label {
                        Text(issue.message).font(.system(size: 11))
                    } icon: {
                        Image(systemName: issue.severity == .error
                              ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                    }
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(issue.severity == .error ? Theme.diffRemove : Color.orange)
                }
            }
            .padding(.top, 2)
        }
    }

    private func borderColor(_ issues: [ReplacementValidationIssue], base: Color) -> Color {
        issues.contains { $0.severity == .error } ? Theme.diffRemove : base
    }

    // MARK: Group

    private func groupRow(_ id: Replacement.ID) -> some View {
        HStack {
            Text("Group").font(Theme.bodyMed).foregroundStyle(Theme.text2)
            Spacer()
            Picker("Group", selection: groupBinding(id)) {
                Text("Ungrouped").tag(Self.noneTag)
                Divider()
                ForEach(model.groups) { g in
                    HStack(spacing: 7) {
                        Circle().fill(g.color).frame(width: 8, height: 8)
                        Text(g.name)
                    }
                    .tag(g.name)
                }
                // Allow keeping a group that has only this (new) member.
                let current = model.replacement(id)?.groupName ?? ""
                if !current.isEmpty, !model.groups.contains(where: { $0.name == current }) {
                    Text(current).tag(current)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .tint(Theme.text)
        }
        .padding(.vertical, 11)
        .overlay(Rectangle().fill(Theme.separator).frame(height: 1), alignment: .top)
    }

    // MARK: Delete

    /// The visible, always-present way to remove a replacement. The first cut of this feature
    /// shipped with only a right-click context menu, which is effectively invisible — a delete
    /// nobody can find is a delete that does not exist.
    private func deleteRow(_ id: Replacement.ID) -> some View {
        HStack {
            Button(role: .destructive) {
                model.deleteReplacement(id)
            } label: {
                Label("Delete Replacement", systemImage: "trash")
                    .foregroundStyle(Theme.diffRemove)
            }
            .buttonStyle(.bordered)
            .help("Stage this replacement for deletion (⌘⌫). Nothing is removed until you Apply.")
            Spacer()
            Text("Removed from macOS on Apply")
                .font(.system(size: 11))
                .foregroundStyle(Theme.text3)
        }
        .padding(.top, 22)
    }

    /// ⌘Z on a row whose shortcut and phrase are *both* still empty deletes it outright, instead of
    /// doing nothing. There is no text to undo at that point anyway (standard Undo is already inert
    /// for an untouched field), so this repurposes the no-op keystroke as a way to back out of
    /// "+ Add" without hunting for the trash icon. Disabled the moment either field has content, so
    /// normal per-field text undo takes over as soon as there's something to undo.
    private func undoDeletesBlankRow(_ id: Replacement.ID, _ row: Replacement) -> some View {
        Button("", action: { model.deleteReplacement(id) })
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!(row.shortcut.isEmpty && row.phrase.isEmpty))
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    // MARK: Notes

    private func notesRow(_ id: Replacement.ID) -> some View {
        HStack(alignment: .top, spacing: 20) {
            Text("Notes").font(Theme.bodyMed).foregroundStyle(Theme.text2)
            Spacer()
            TextField("Add a note…", text: optionalBinding(id, \.notes), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
                .lineLimit(1...6)
                .frame(maxWidth: 300, alignment: .trailing)
        }
        .padding(.vertical, 11)
        .overlay(Rectangle().fill(Theme.separator).frame(height: 1), alignment: .top)
    }

    // MARK: Bits

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.text2)
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "character.cursor.ibeam")
                .font(.system(size: 30))
                .foregroundStyle(Theme.text3)
            Text("No replacement selected")
                .font(Theme.display).foregroundStyle(Theme.text2)
            Text("Select a replacement to edit it, then Apply to macOS.")
                .font(Theme.body).foregroundStyle(Theme.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.window)
    }

    // MARK: Bindings
    //
    // Every binding resolves its row by **id**, at get and at set. These used to capture an `Int`
    // index (while the comment here claimed otherwise). That is safe only while the array never
    // shrinks: once a row can be removed, a stale index silently addresses the neighbour and the
    // write lands on the wrong replacement — no crash, no error (GH-2 gotcha 3).

    private func write(_ id: Replacement.ID, _ mutate: (inout Replacement) -> Void) {
        guard let i = model.index(of: id) else { return }
        mutate(&model.replacements[i])
        model.touch(id)
    }

    private func read<T>(_ id: Replacement.ID, _ fallback: T, _ get: (Replacement) -> T) -> T {
        guard let i = model.index(of: id) else { return fallback }
        return get(model.replacements[i])
    }

    private func stringBinding(_ id: Replacement.ID, _ keyPath: WritableKeyPath<Replacement, String>) -> Binding<String> {
        Binding(
            get: { MainActor.assumeIsolated { read(id, "") { $0[keyPath: keyPath] } } },
            set: { value in MainActor.assumeIsolated { write(id) { $0[keyPath: keyPath] = value } } }
        )
    }

    private func boolBinding(_ id: Replacement.ID, _ keyPath: WritableKeyPath<Replacement, Bool>) -> Binding<Bool> {
        Binding(
            get: { MainActor.assumeIsolated { read(id, false) { $0[keyPath: keyPath] } } },
            set: { value in MainActor.assumeIsolated { write(id) { $0[keyPath: keyPath] = value } } }
        )
    }

    private func optionalBinding(_ id: Replacement.ID, _ keyPath: WritableKeyPath<Replacement, String?>) -> Binding<String> {
        Binding(
            get: { MainActor.assumeIsolated { read(id, "") { $0[keyPath: keyPath] ?? "" } } },
            set: { value in MainActor.assumeIsolated {
                write(id) { $0[keyPath: keyPath] = value.isEmpty ? nil : value }
            } }
        )
    }

    /// String-keyed binding for the Group picker; the sentinel maps to `nil`.
    private func groupBinding(_ id: Replacement.ID) -> Binding<String> {
        Binding(
            get: { MainActor.assumeIsolated {
                let g = read(id, "") { $0.groupName ?? "" }
                return g.isEmpty ? Self.noneTag : g
            } },
            set: { value in MainActor.assumeIsolated {
                write(id) { $0.groupName = (value == Self.noneTag) ? nil : value }
            } }
        )
    }
}
