import SwiftUI
import AppKit
import TextReplacementCore

@main
struct TextReplacementStudioApp: App {
    init() {
        // SwiftPM's generated bundle has no Info.plist icon key, so set the Dock /
        // ⌘-Tab icon at launch from the bundled artwork. Keep AppIcon.png's
        // optical margin intact: macOS does not normalize full-bleed art.
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                NewReplacementCommand()
            }
            CommandGroup(replacing: .appInfo) {
                AboutCommand()
            }
        }
    }
}

/// App ▸ About Text Replacement Studio. Standard panel plus the sponsor/copyright/license
/// lines, which `NSHumanReadableCopyright` in Info.plist doesn't have room for on its own.
private struct AboutCommand: View {
    var body: some View {
        Button("About Text Replacement Studio") {
            NSApplication.shared.orderFrontStandardAboutPanel(options: [
                .credits: NSAttributedString(
                    string: """
                    Text Replacement Studio | Sponsored by MacNerd.xyz
                    © Copyright 2026 Neochrome, Inc.
                    GPL v2 License | Use as-is
                    """,
                    attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]
                )
            ])
        }
    }
}

/// File ▸ New Replacement (⌘N). Reads the action published by the focused window's
/// ContentView so the menu and the in-window buttons share one path.
private struct NewReplacementCommand: View {
    @FocusedValue(\.newReplacement) private var add

    var body: some View {
        Button("New Replacement") { add?() }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(add == nil)
    }
}
