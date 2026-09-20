import AppKit
import CSQLite
import Foundation

struct AppStateRepository {
    private let fileManager = FileManager.default
    private let directoryOverride: URL?

    init(applicationSupportDirectory: URL? = nil) {
        directoryOverride = applicationSupportDirectory
    }

    var applicationSupportDirectory: URL {
        if let directoryOverride { return directoryOverride }
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return root.appendingPathComponent("hidigFocus", isDirectory: true)
    }

    private var stateURL: URL {
        applicationSupportDirectory.appendingPathComponent("state.json")
    }

    private var databaseURL: URL {
        applicationSupportDirectory.appendingPathComponent("tasks.sqlite3")
    }

    func load() throws -> PersistedAppState {
        try fileManager.createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
        let database = try openDatabase()
        defer { sqlite3_close(database) }
        try migrate(database)
        if let data = try readSnapshot(database) {
            return try JSONDecoder.hidigFocus.decode(PersistedAppState.self, from: data)
        }
        if fileManager.fileExists(atPath: stateURL.path) {
            let data = try Data(contentsOf: stateURL)
            let state = try JSONDecoder.hidigFocus.decode(PersistedAppState.self, from: data)
            try writeSnapshot(data, database: database)
            return state
        }
        return PersistedAppState()
    }

    func save(_ state: PersistedAppState) throws {
        try fileManager.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder.hidigFocus.encode(state)
        let database = try openDatabase()
        defer { sqlite3_close(database) }
        try migrate(database)
        try writeSnapshot(data, database: database)
    }

    @discardableResult
    func createBackup(label: String = "before-task-import") throws -> URL? {
        let source = fileManager.fileExists(atPath: databaseURL.path) ? databaseURL : stateURL
        guard fileManager.fileExists(atPath: source.path) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let destination = applicationSupportDirectory.appendingPathComponent("\(source.deletingPathExtension().lastPathComponent)-\(label)-\(formatter.string(from: Date())).\(source.pathExtension)")
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    private func openDatabase() throws -> OpaquePointer {
        var database: OpaquePointer?
        let status = sqlite3_open_v2(databaseURL.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw PersistenceError.sqlite("Не удалось открыть локальную базу данных.")
        }
        return database
    }

    private func migrate(_ database: OpaquePointer) throws {
        try execute("CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)", database: database)
        try execute("CREATE TABLE IF NOT EXISTS state_snapshot (id INTEGER PRIMARY KEY CHECK (id = 1), schema_version INTEGER NOT NULL, payload BLOB NOT NULL, updated_at TEXT NOT NULL)", database: database)
        try execute("INSERT OR IGNORE INTO schema_migrations(version, applied_at) VALUES (1, datetime('now'))", database: database)
    }

    private func readSnapshot(_ database: OpaquePointer) throws -> Data? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "SELECT payload FROM state_snapshot WHERE id = 1", -1, &statement, nil) == SQLITE_OK else {
            throw PersistenceError.sqlite(message(database))
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard let bytes = sqlite3_column_blob(statement, 0), count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }

    private func writeSnapshot(_ data: Data, database: OpaquePointer) throws {
        try execute("BEGIN IMMEDIATE", database: database)
        do {
            var statement: OpaquePointer?
            let sql = "INSERT INTO state_snapshot(id, schema_version, payload, updated_at) VALUES (1, 2, ?, datetime('now')) ON CONFLICT(id) DO UPDATE SET schema_version=excluded.schema_version, payload=excluded.payload, updated_at=excluded.updated_at"
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw PersistenceError.sqlite(message(database)) }
            defer { sqlite3_finalize(statement) }
            let status = data.withUnsafeBytes { rawBuffer in
                sqlite3_bind_blob(statement, 1, rawBuffer.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            }
            guard status == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw PersistenceError.sqlite(message(database)) }
            try execute("COMMIT", database: database)
        } catch {
            try? execute("ROLLBACK", database: database)
            throw error
        }
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw PersistenceError.sqlite(message(database)) }
    }

    private func message(_ database: OpaquePointer) -> String {
        sqlite3_errmsg(database).map(String.init(cString:)) ?? "Неизвестная ошибка SQLite."
    }
}

private enum PersistenceError: LocalizedError {
    case sqlite(String)
    var errorDescription: String? {
        if case .sqlite(let message) = self { return message }
        return nil
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
