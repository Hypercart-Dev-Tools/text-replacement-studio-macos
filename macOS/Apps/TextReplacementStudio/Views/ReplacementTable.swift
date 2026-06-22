import SwiftUI
import TextReplacementCore

struct ReplacementTable: View {
    let searchText: String
    let selectedFilter: ReplacementFilter
    @Binding var selectedReplacementID: Replacement.ID?

    @State private var replacements: [Replacement] = [
        Replacement(shortcut: ";sig", phrase: "Noel Saw\nNeochrome", groupName: "Personal"),
        Replacement(shortcut: ";omw", phrase: "On my way!", groupName: "Quick Replies")
    ]

    var filteredReplacements: [Replacement] {
        guard !searchText.isEmpty else {
            return replacements
        }

        return replacements.filter {
            $0.shortcut.localizedCaseInsensitiveContains(searchText)
                || $0.phrase.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Table(filteredReplacements, selection: $selectedReplacementID) {
            TableColumn("Shortcut", value: \.shortcut)
            TableColumn("Phrase", value: \.phrase)
            TableColumn("Group") { replacement in
                Text(replacement.groupName ?? "")
            }
            TableColumn("Enabled") { replacement in
                Image(systemName: replacement.enabled ? "checkmark.circle.fill" : "circle")
            }
        }
    }
}
