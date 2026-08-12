import SwiftUI
import TextReplacementCore

/// One replacement in the middle list: key-cap · phrase · group tag · enable toggle.
/// A lightweight `HStack` (not a `Table` cell) so selection can paint a soft tinted
/// fill and the toggle stays inline.
struct ReplacementRow: View {
    let replacement: Replacement
    let isSelected: Bool
    @Binding var isEnabled: Bool
    let onSelect: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 11) {
            KeyCap(text: replacement.shortcut)

            Text(replacement.phrase)
                .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                .foregroundStyle(phraseColor)
                .strikethrough(replacement.isPendingDeletion, color: Theme.diffRemove)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if replacement.isPendingDeletion {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.diffRemove)
                    .help("Staged for deletion on the next Apply")
            } else if let group = replacement.groupName, !group.isEmpty {
                GroupTag(name: group)
            }

            // A staged row is on its way out; toggling Enabled on it would be meaningless.
            StudioToggle(isOn: $isEnabled, controlSize: .mini)
                .disabled(replacement.isPendingDeletion)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(rowBackground)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
        .opacity(replacement.isPendingDeletion ? 0.55 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            replacement.isPendingDeletion
                ? "\(replacement.shortcut), \(replacement.phrase), staged for deletion"
                : "\(replacement.shortcut), \(replacement.phrase)"
        )
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var phraseColor: Color {
        if replacement.isPendingDeletion { return Theme.text3 }
        return replacement.enabled ? Theme.text : Theme.text3
    }

    @ViewBuilder private var rowBackground: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
        if isSelected {
            shape.fill(Theme.accentSoft)
        } else if hovering {
            shape.fill(Theme.hover)
        } else {
            shape.fill(.clear)
        }
    }
}
