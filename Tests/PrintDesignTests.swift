import XCTest
import AppKit
import CryptoKit
import CSQLite
@testable import hidigFocus

final class PrintDesignTests: XCTestCase {
    func testApprovedTokenCatalogIsBundledAndDrivesNativePaperRoles() throws {
        let tokens = try XCTUnwrap(PrintTokens.catalog)
        for dark in [false, true] {
            let colors = try XCTUnwrap(tokens.color[dark ? "dark" : "light"])
            let native = SidebarColorPreference.paper.theme(isDark: dark)
            XCTAssertEqual(native.canvas, colors["canvas"])
            XCTAssertEqual(native.surface, colors["surface"])
            XCTAssertEqual(native.surfaceRaised, colors["surfaceRaised"])
            XCTAssertEqual(native.text, colors["text"])
            XCTAssertEqual(native.accent, colors["accent"])
        }
        XCTAssertEqual(PrintTokens.inputHeight, 38)
        XCTAssertEqual(PrintTokens.buttonHeight, 32)
        XCTAssertEqual(PrintDesign.hover, 0.12)
        XCTAssertEqual(PrintDesign.state, 0.18)
        XCTAssertEqual(PrintDesign.panel, 0.24)
    }

    func testAcceptanceFixtureHasExactlyTenThousandTasksAndThreeHundredSeries() {
        let fixture = PlannerFixtures.make(count: 10_000, seriesCount: 300)
        XCTAssertEqual(fixture.managedTasks.count, 10_000)
        XCTAssertEqual(fixture.managedTasks.filter { $0.repeatRule != nil }.count, 300)
        XCTAssertEqual(Set(fixture.managedTasks.map(\.id)).count, 10_000)
    }

    private func withDefaults(_ action: (UserDefaults) throws -> Void) throws {
        let suite = "hidigFocus.print.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try action(defaults)
    }
    func testAppearanceUpgradeChangesOnlyAllowedKeysAndKeepsOriginalBackup() throws {
        try withDefaults { defaults in
            let protected: [String: Any] = ["calendarHourHeight": 120.0, "planner.timeZone": "Europe/Moscow", "planner.firstWeekday": 1, "navigationWidth": 233.0, HidigSettingsKeys.appearance: "dark", HidigSettingsKeys.textSize: "large"]
            protected.forEach { defaults.set($0.value, forKey: $0.key) }
            defaults.set("georgia", forKey: HidigSettingsKeys.font)
            defaults.set("graphite", forKey: HidigSettingsKeys.sidebarColor)
            defaults.set("blue", forKey: HidigSettingsKeys.appIcon)
            PrintDesign.applyFirstLaunch(defaults: defaults)
            XCTAssertEqual(defaults.string(forKey: HidigSettingsKeys.font), "golos")
            XCTAssertEqual(defaults.string(forKey: HidigSettingsKeys.sidebarColor), "paper")
            XCTAssertEqual(defaults.string(forKey: HidigSettingsKeys.appIcon), "doors")
            for (key, value) in protected { XCTAssertEqual(defaults.object(forKey: key) as? NSObject, value as? NSObject, key) }
            let backup = try XCTUnwrap(defaults.dictionary(forKey: PrintDesign.previousKey))
            XCTAssertEqual(backup[HidigSettingsKeys.font] as? String, "georgia")
            defaults.set("onest", forKey: HidigSettingsKeys.font)
            PrintDesign.applyFirstLaunch(defaults: defaults)
            XCTAssertEqual(defaults.string(forKey: HidigSettingsKeys.font), "onest")
            XCTAssertEqual(defaults.dictionary(forKey: PrintDesign.previousKey)?[HidigSettingsKeys.font] as? String, "georgia")
        }
    }
    func testPartiallyAppliedAppearanceMigrationNeverReplacesOriginalBackup() throws {
        try withDefaults { defaults in
            defaults.set([HidigSettingsKeys.font: "avenir"], forKey: PrintDesign.previousKey)
            defaults.set("golos", forKey: HidigSettingsKeys.font)
            PrintDesign.applyFirstLaunch(defaults: defaults)
            XCTAssertEqual(defaults.dictionary(forKey: PrintDesign.previousKey)?[HidigSettingsKeys.font] as? String, "avenir")
            XCTAssertEqual(defaults.integer(forKey: PrintDesign.migrationKey), PrintDesign.version)
        }
    }
    func testAllBundledFontsRegisterAndResolveWithoutSystemFallback() throws {
        for font in [HidigFontPreference.golos, .onest, .manrope, .inter] {
            XCTAssertNotNil(HidigFontRegistry.name(for: font), font.rawValue)
        }
    }
    func testPrintIconResourcesAreIndependentSquareAlphaImages() throws {
        for name in ["doors", "medallion"] {
            let url = try XCTUnwrap(HidigResources.bundle.url(forResource: name, withExtension: "png", subdirectory: "PrintIcons"))
            let rep = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
            XCTAssertEqual(rep.pixelsWide, rep.pixelsHigh)
            XCTAssertGreaterThanOrEqual(rep.pixelsWide, 1024)
            XCTAssertTrue(rep.hasAlpha)
        }
    }
    func testWriterFailureIsNotMistakenForSuccessfulFlushAndCanRetry() throws {
        enum Fault: Error { case disk }
        var fails = true
        let coordinator = SaveCoordinator(write: { _ in if fails { throw Fault.disk } })
        coordinator.enqueue(PersistedAppState(), revision: 1) { _, _ in }
        XCTAssertNotNil(coordinator.flushFailure())
        fails = false
        coordinator.enqueue(PersistedAppState(), revision: 1) { _, _ in }
        XCTAssertNil(coordinator.flushFailure())
    }
    func testEmptyPersistedSnapshotDoesNotBecomeNewUserData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        try repository.save(PersistedAppState())
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("tasks.sqlite3").path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "UPDATE state_snapshot SET payload = X''", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        XCTAssertThrowsError(try repository.load())
    }
    func testFutureSchemaIsNotSilentlyLoadedAndRewritten() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        var state = PersistedAppState(); state.schemaVersion = 999
        try repository.save(state)
        XCTAssertThrowsError(try repository.load())
    }
    @MainActor func testAttachmentDirectoryUsesInjectedRepository() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "hidigFocus.attachments.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false, plannerDefaults: defaults)
        defer { store.flushPendingWrites() }
        XCTAssertEqual(store.attachmentDirectoryURL, directory.appendingPathComponent("Attachments", isDirectory: true))
    }
    func testActualSnapshotRoundTripPreservesEveryTaskAndStateSection() throws {
        guard let path = ProcessInfo.processInfo.environment["HIDIGFOCUS_PRESERVATION_FIXTURE"] else { throw XCTSkip("Private snapshot fixture is supplied explicitly") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: directory)
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        let before = try repository.load()
        try repository.save(before)
        let after = try repository.load()
        XCTAssertEqual(before.managedTasks.map(\.id), after.managedTasks.map(\.id))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let hashBefore = SHA256.hash(data: try canonical(encoder.encode(before)))
        let hashAfter = SHA256.hash(data: try canonical(encoder.encode(after)))
        XCTAssertEqual(Data(hashBefore), Data(hashAfter), "All persisted fields must survive the visual upgrade")
    }
    private func canonical(_ data: Data) throws -> Data {
        func normalized(_ value: Any, key: String = "") -> Any {
            if let object = value as? [String: Any] { return object.mapValues { child in child }.reduce(into: [String: Any]()) { result, pair in result[pair.key] = normalized(pair.value, key: pair.key) } }
            if let array = value as? [Any] {
                if key == "pendingGroupRules", array.count.isMultiple(of: 2) {
                    var result: [String: Any] = [:]
                    for i in stride(from: 0, to: array.count, by: 2) { if let id = array[i] as? String { result[id] = normalized(array[i+1]) } }
                    return result
                }
                let values = array.map { normalized($0) }
                if ["weekdays", "checkInDayKeys", "requiredTaskIDs", "selectedCalendarIDs"].contains(key) {
                    return values.sorted { String(describing: $0) < String(describing: $1) }
                }
                return values
            }
            return value
        }
        return try JSONSerialization.data(withJSONObject: normalized(JSONSerialization.jsonObject(with: data)), options: [.sortedKeys])
    }

}

extension PrintDesignTests {
    func testOnlineBackupIncludesCommittedWALPagesAndRemainsIndependent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        var state = PersistedAppState(); state.managedTasks = [ManagedTask(title: "До изменения")]
        try repository.save(state)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(directory.appendingPathComponent("tasks.sqlite3").path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(sqlite3_exec(db, "PRAGMA journal_mode=WAL", nil, nil, nil), SQLITE_OK)
        state.managedTasks[0].title = "Записано в WAL"
        try repository.save(state)
        let backup = try XCTUnwrap(repository.createBackup(label: "test-wal"))
        let restored = directory.appendingPathComponent("restored", isDirectory: true)
        try FileManager.default.createDirectory(at: restored, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: backup, to: restored.appendingPathComponent("tasks.sqlite3"))
        XCTAssertEqual(try AppStateRepository(applicationSupportDirectory: restored).load().managedTasks[0].title, "Записано в WAL")
        let second = try XCTUnwrap(repository.createBackup(label: "test-wal"))
        XCTAssertNotEqual(backup, second)
    }
    @MainActor func testNativeStoreLaunchOnPrivateCopyPreservesAllDataAndFiles() throws {
        guard let path = ProcessInfo.processInfo.environment["HIDIGFOCUS_PRESERVATION_FIXTURE"] else { throw XCTSkip("Private snapshot fixture is supplied explicitly") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: directory)
        let suite = "hidigFocus.upgrade.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        func files() throws -> [String: Data] {
            var hashes: [String: Data] = [:]
            for name in ["Journal", "Attachments"] {
                let root = directory.appendingPathComponent(name)
                if let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) {
                    for case let file as URL in enumerator where (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                        hashes[file.path.replacingOccurrences(of: directory.path, with: "")] = Data(SHA256.hash(data: try Data(contentsOf: file)))
                    }
                }
            }
            return hashes
        }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        func rawSnapshot() throws -> Data {
            var db: OpaquePointer?; var statement: OpaquePointer?
            guard sqlite3_open_v2(directory.appendingPathComponent("tasks.sqlite3").path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
            defer { sqlite3_close(db) }
            guard sqlite3_prepare_v2(db, "SELECT payload FROM state_snapshot WHERE id=1", -1, &statement, nil) == SQLITE_OK else { throw CocoaError(.fileReadUnknown) }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement, 0) else { throw CocoaError(.fileReadUnknown) }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 0)))
        }
        let rawBefore = try rawSnapshot()
        let before = try repository.load(); var expected = before
        expected.advanceProtectionDays()
        let beforeFiles = try files()
        let store = AppStore(repository: repository, startServices: false, plannerDefaults: defaults)
        XCTAssertNil(store.prepareForTermination())
        let after = try repository.load()
        if let path = ProcessInfo.processInfo.environment["HIDIGFOCUS_PRESERVATION_RAW_DIR"] {
            let root = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try rawBefore.write(to: root.appendingPathComponent("before.json"))
            try rawSnapshot().write(to: root.appendingPathComponent("after.json"))
        }
        XCTAssertTrue(before.managedTasks == after.managedTasks, "Task records must stay identical after native startup")
        XCTAssertTrue(beforeFiles == (try files()), "Journal and attachment bytes must remain identical")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let expectedHash = Data(SHA256.hash(data: try canonical(encoder.encode(expected))))
        let actualHash = Data(SHA256.hash(data: try canonical(encoder.encode(after))))
        XCTAssertEqual(expectedHash, actualHash, "Only the existing calendar-day protection maintenance is permitted")
        if let path = ProcessInfo.processInfo.environment["HIDIGFOCUS_PRESERVATION_REPORT"] {
            let report: [String: Any] = ["tasksBefore": before.managedTasks.count, "tasksAfter": after.managedTasks.count, "changedTaskRecords": before.managedTasks == after.managedTasks ? 0 : -1, "stateMatchesExpected": expectedHash == actualHash, "journalAndAttachmentFilesUnchanged": beforeFiles == (try files()), "checkedFiles": beforeFiles.count, "allowedMaintenance": ["disciplineStreak", "disciplineLastCountedDayKey"], "productionAppInstalled": false]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
        }
    }

}

extension PrintDesignTests {
    @MainActor func testUnreadableSnapshotStaysReadOnlyAndCannotBeReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "hidigFocus.corruption.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var db: OpaquePointer?
        let url = directory.appendingPathComponent("tasks.sqlite3")
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(db, "CREATE TABLE state_snapshot(id INTEGER PRIMARY KEY, schema_version INTEGER, payload BLOB, updated_at TEXT); INSERT INTO state_snapshot VALUES(1,3,X'7B',NULL)", nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let before = try Data(contentsOf: url)
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false, plannerDefaults: defaults)
        XCTAssertTrue(store.dataIsReadOnly)
        _ = store.addManagedTask(named: "Must never overwrite the corrupted snapshot")
        store.flushPendingWrites()
        // Repository may add its migration table; compare the original payload itself.
        XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "SELECT hex(payload) FROM state_snapshot WHERE id=1", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 0)), "7B")
        XCTAssertFalse(before.isEmpty)
    }
}

extension PrintDesignTests {
    func testLegacyJSONUpgradePersistsFlattenedTasksAcrossRestartAndKeepsOriginalBackup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var state = PersistedAppState(); state.schemaVersion = 2
        let child = ManagedTask(title: "Legacy child")
        var parent = ManagedTask(title: "Legacy parent"); parent.subtasks = [child]
        state.managedTasks = [parent]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let original = try encoder.encode(state)
        try original.write(to: directory.appendingPathComponent("state.json"))
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        let first = try repository.load(); let second = try repository.load()
        XCTAssertEqual(first.schemaVersion, 3); XCTAssertEqual(second.schemaVersion, 3)
        XCTAssertEqual(first.managedTasks.count, 2); XCTAssertEqual(first.managedTasks, second.managedTasks)
        XCTAssertEqual(second.managedTasks.first { $0.id == child.id }?.parentTaskID, parent.id)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("state-before-sqlite-") })
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("state.json")), original)
    }
}

extension PrintDesignTests {
    @MainActor func testJournalReadFailureKeepsCurrentDraftAndWriteDestination() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "hidigFocus.journal-read.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false, plannerDefaults: defaults)
        store.createJournalEntry()
        let original = try XCTUnwrap(store.selectedJournalEntry)
        store.updateJournalDraft("Current draft")
        store.flushPendingWrites()
        let missing = JournalEntry(fileURL: directory.appendingPathComponent("Journal/missing.md"), title: "Missing", modifiedAt: Date())
        store.selectJournalEntry(missing)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.selectedJournalEntry, original)
        XCTAssertEqual(store.journalDraft, "Current draft")
        store.updateJournalDraft("Current draft after failed navigation")
        store.flushPendingWrites()
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.fileURL.path))
        XCTAssertEqual(try String(contentsOf: original.fileURL, encoding: .utf8), "Current draft after failed navigation")
    }

    @MainActor func testFocusWindowContextDoesNotPublishOrModifyTaskState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "hidigFocus.focus-context.tests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false, plannerDefaults: defaults)
        let original = store.state.managedTasks
        var changes = 0
        let token = store.objectWillChange.sink { changes += 1 }
        let mainWindow = store.focusPresentation; let compactWindow = store.focusPresentation
        mainWindow.selectedTask = UUID(); mainWindow.phase = .shortBreak; mainWindow.stopwatch = true
        XCTAssertEqual(compactWindow.selectedTask, mainWindow.selectedTask)
        XCTAssertEqual(compactWindow.phase, .shortBreak); XCTAssertTrue(compactWindow.stopwatch)
        XCTAssertEqual(changes, 0); XCTAssertEqual(original, store.state.managedTasks)
        withExtendedLifetime(token) {}
        store.flushPendingWrites()
    }
}
