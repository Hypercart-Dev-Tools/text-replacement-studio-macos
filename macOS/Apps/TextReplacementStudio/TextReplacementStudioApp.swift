import SwiftUI
import TextReplacementCore

@main
struct TextReplacementStudioApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Apple plist...") {
                    // Wire to import flow.
                }
                Button("Export Apple plist...") {
                    // Wire to export flow.
                }
            }
        }
    }
}
