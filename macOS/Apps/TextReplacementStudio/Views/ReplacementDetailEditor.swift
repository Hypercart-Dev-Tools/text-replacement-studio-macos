import SwiftUI
import TextReplacementCore

struct ReplacementDetailEditor: View {
    let replacementID: Replacement.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if replacementID == nil {
                ContentUnavailableView(
                    "No Replacement Selected",
                    systemImage: "textformat",
                    description: Text("Select a replacement or create a new one.")
                )
            } else {
                Text("Replacement Details")
                    .font(.title2)
                    .bold()

                TextField("Shortcut", text: .constant(""))
                TextEditor(text: .constant(""))
                    .frame(minHeight: 120)
                TextField("Group", text: .constant(""))
                TextField("Notes", text: .constant(""))

                Spacer()
            }
        }
        .padding()
    }
}
