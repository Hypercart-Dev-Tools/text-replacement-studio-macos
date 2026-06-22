import SwiftUI
import TextReplacementCore

struct ContentView: View {
    @State private var searchText = ""
    @State private var selectedFilter: ReplacementFilter = .all
    @State private var selectedReplacementID: Replacement.ID?

    var body: some View {
        NavigationSplitView {
            ReplacementSidebar(selectedFilter: $selectedFilter)
        } content: {
            VStack(spacing: 0) {
                SearchBar(text: $searchText)
                    .padding()

                ReplacementTable(
                    searchText: searchText,
                    selectedFilter: selectedFilter,
                    selectedReplacementID: $selectedReplacementID
                )
            }
        } detail: {
            ReplacementDetailEditor(replacementID: selectedReplacementID)
        }
        .navigationTitle("Text Replacement Studio")
    }
}
