import SwiftUI

struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        TextField("Search shortcuts or phrases", text: $text)
            .textFieldStyle(.roundedBorder)
    }
}
