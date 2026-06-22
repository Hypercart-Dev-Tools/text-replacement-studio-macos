import Foundation

public struct AppleDatabaseImporter: ReplacementImporter {
    public let source: ReplacementImportSource = .appleDatabase

    public init() {}

    public func importReplacements(request: ReplacementImportRequest) async throws -> ReplacementImportResult {
        throw ReplacementImportExportError.invalidInput(
            "AppleDatabaseImporter is a placeholder. Implement read-only import from ~/Library/KeyboardServices/TextReplacements.db behind this interface."
        )
    }
}
