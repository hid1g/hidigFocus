import AppKit
import Foundation

struct AppStateRepository {
    private let fileManager = FileManager.default

    var applicationSupportDirectory: URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("hidigFocus", isDirectory: true)
    }

    private var stateURL: URL {
        applicationSupportDirectory.appendingPathComponent("state.json")
    }

    func load() throws -> PersistedAppState {
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return PersistedAppState()
        }
        let data = try Data(contentsOf: stateURL)
        return try JSONDecoder.hidigFocus.decode(PersistedAppState.self, from: data)
    }

    func save(_ state: PersistedAppState) throws {
        try fileManager.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.hidigFocus.encode(state)
        try data.write(to: stateURL, options: .atomic)
    }
}

final class JournalRepository {
    private let fileManager = FileManager.default
    private let directoryURL: URL

    init(applicationSupportDirectory: URL) {
        directoryURL = applicationSupportDirectory.appendingPathComponent("Journal", isDirectory: true)
    }

    func entries() throws -> [JournalEntry] {
        try ensureDirectory()
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        let files = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        return try files
            .filter { $0.pathExtension.lowercased() == "md" }
            .compactMap { url in
                let values = try url.resourceValues(forKeys: keys)
                guard values.isRegularFile == true else { return nil }
                return JournalEntry(
                    fileURL: url,
                    title: url.deletingPathExtension().lastPathComponent,
                    modifiedAt: values.contentModificationDate ?? .distantPast
                )
            }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func createTodayEntry() throws -> JournalEntry {
        try ensureDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "yyyy-MM-dd"
        let baseName = formatter.string(from: Date())
        var candidate = directoryURL.appendingPathComponent(baseName).appendingPathExtension("md")
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directoryURL.appendingPathComponent("\(baseName)-\(suffix)").appendingPathExtension("md")
            suffix += 1
        }
        try "".write(to: candidate, atomically: true, encoding: .utf8)
        return JournalEntry(fileURL: candidate, title: candidate.deletingPathExtension().lastPathComponent, modifiedAt: Date())
    }

    func read(_ entry: JournalEntry) throws -> String {
        try String(contentsOf: entry.fileURL, encoding: .utf8)
    }

    func write(_ content: String, to entry: JournalEntry) throws {
        try content.write(to: entry.fileURL, atomically: true, encoding: .utf8)
    }

    func rename(_ entry: JournalEntry, to rawTitle: String) throws -> JournalEntry {
        let invalid = CharacterSet(charactersIn: "/:")
        let title = rawTitle
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw AppError.invalidJournalTitle }
        let destination = directoryURL.appendingPathComponent(title).appendingPathExtension("md")
        if destination.standardizedFileURL == entry.fileURL.standardizedFileURL { return entry }
        guard !fileManager.fileExists(atPath: destination.path) else { throw AppError.journalTitleExists }
        try fileManager.moveItem(at: entry.fileURL, to: destination)
        return JournalEntry(fileURL: destination, title: title, modifiedAt: Date())
    }

    func revealDirectory() throws {
        try ensureDirectory()
        NSWorkspace.shared.activateFileViewerSelecting([directoryURL])
    }

    private func ensureDirectory() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}

private extension JSONEncoder {
    static var hidigFocus: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var hidigFocus: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
