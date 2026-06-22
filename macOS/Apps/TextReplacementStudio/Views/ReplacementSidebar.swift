import SwiftUI
import TextReplacementCore

struct ReplacementSidebar: View {
    @Binding var selectedFilter: ReplacementFilter

    var body: some View {
        List(selection: $selectedFilter) {
            Text("All").tag(ReplacementFilter.all)
            Text("Recently Changed").tag(ReplacementFilter.recentlyChanged)
            Text("Duplicates").tag(ReplacementFilter.duplicates)
            Text("Disabled").tag(ReplacementFilter.disabled)
            Text("Ungrouped").tag(ReplacementFilter.ungrouped)
        }
        .navigationTitle("Library")
    }
}
