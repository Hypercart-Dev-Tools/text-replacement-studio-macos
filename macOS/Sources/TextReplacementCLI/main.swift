import ArgumentParser
import Foundation
import TextReplacementCore

@main
struct TRStudioCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "trstudio",
        abstract: "Manage macOS text replacements with a better workflow.",
        version: TextReplacementCore.version,
        subcommands: [
            List.self,
            Add.self,
            Import.self,
            Export.self,
            Lint.self,
            Backup.self
        ],
        defaultSubcommand: List.self
    )
}

struct List: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List local text replacements."
    )

    func run() async throws {
        print("List is not implemented yet. Wire this to ReplacementStore.fetchAll().")
    }
}

struct Add: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a text replacement."
    )

    @Argument(help: "Shortcut, such as ';sig'.")
    var shortcut: String

    @Argument(help: "Expanded phrase.")
    var phrase: String

    func run() async throws {
        let replacement = Replacement(shortcut: shortcut, phrase: phrase)
        print("Prepared replacement: \(replacement.shortcut) -> \(replacement.phrase)")
        print("Add is not implemented yet. Wire this to ReplacementStore.save(_:).")
    }
}

struct Import: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import replacements from a supported source."
    )

    @Option(help: "Import source: apple-plist, apple-database, csv, or json.")
    var source: String = ReplacementImportSource.applePlist.rawValue

    @Option(help: "Input file path.")
    var input: String?

    func run() async throws {
        print("Import is not implemented yet. Source: \(source), input: \(input ?? "<none>")")
    }
}

struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export replacements to a supported format."
    )

    @Option(help: "Export format: apple-plist, csv, json, or markdown.")
    var format: String = ReplacementExportFormat.applePlist.rawValue

    @Option(help: "Output file path.")
    var output: String?

    @Flag(help: "Include disabled entries in export.")
    var includeDisabled = false

    func run() async throws {
        print("Export is not implemented yet. Format: \(format), output: \(output ?? "<stdout>"), includeDisabled: \(includeDisabled)")
    }
}

struct Lint: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Validate replacements for duplicates and common issues."
    )

    func run() async throws {
        print("Lint is not implemented yet. Wire this to DefaultReplacementLinter.")
    }
}

struct Backup: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "backup",
        abstract: "Create a snapshot backup of the local replacement database."
    )

    @Option(help: "Backup label.")
    var label: String = "Manual backup"

    func run() async throws {
        print("Backup is not implemented yet. Label: \(label)")
    }
}
