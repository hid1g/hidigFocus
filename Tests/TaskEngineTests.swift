import XCTest
@testable import hidigFocus

final class TaskEngineTests: XCTestCase {
    func testCreateEditCompleteRestoreTrashAndDeleteTask() throws {
        var state = PersistedAppState()
        let id = try XCTUnwrap(TaskEngine.addTask(title: "Задача", listID: TaskList.inboxID, to: &state))
        var task = try XCTUnwrap(state.managedTasks.first)
        task.title = "Изменённая задача"
        TaskEngine.updateTask(task, in: &state)
        XCTAssertEqual(state.managedTasks.first?.title, "Изменённая задача")

        let completedAt = Date(timeIntervalSince1970: 1_800_000_000)
        TaskEngine.setCompleted(id, completed: true, in: &state, now: completedAt)
        XCTAssertEqual(state.managedTasks.first?.status, .completed)
        XCTAssertEqual(state.managedTasks.first?.completedAt, completedAt)
        TaskEngine.setCompleted(id, completed: false, in: &state)
        XCTAssertEqual(state.managedTasks.first?.status, .active)
        XCTAssertNil(state.managedTasks.first?.completedAt)

        TaskEngine.trash(id, in: &state)
        XCTAssertEqual(state.managedTasks.first?.status, .trashed)
        TaskEngine.restoreFromTrash(id, in: &state)
        XCTAssertEqual(state.managedTasks.first?.status, .active)
        TaskEngine.permanentlyDelete(id, in: &state)
        XCTAssertTrue(state.managedTasks.isEmpty)
    }

    func testFolderListTaskHierarchy() throws {
        var state = PersistedAppState()
        let folder = TaskFolder(name: "Работа", sourceID: "folder-1")
        let list = TaskList(folderID: folder.id, name: "Проект", sourceID: "list-1")
        state.taskFolders.append(folder)
        state.taskLists.append(list)
        let taskID = try XCTUnwrap(TaskEngine.addTask(title: "Результат", listID: list.id, to: &state))
        XCTAssertEqual(state.taskLists.first(where: { $0.id == list.id })?.folderID, folder.id)
        XCTAssertEqual(state.managedTasks.first(where: { $0.id == taskID })?.listID, list.id)
    }

    func testDuplicateDetachesImportedTaskAndResetsProgress() throws {
        var state = PersistedAppState()
        let id = try XCTUnwrap(TaskEngine.addTask(title: "Повторить", listID: TaskList.inboxID, to: &state))
        state.managedTasks[0].sourceID = "ticktick-123"
        state.managedTasks[0].googleEventID = "google-123"
        state.managedTasks[0].status = .completed
        state.managedTasks[0].completedPomodoros = 3
        state.managedTasks[0].checklist = [TaskChecklistItem(title: "Шаг", isCompleted: true)]

        let duplicateID = try XCTUnwrap(TaskEngine.duplicate(id, in: &state))
        let duplicate = try XCTUnwrap(state.managedTasks.first { $0.id == duplicateID })
        XCTAssertEqual(state.managedTasks.count, 2)
        XCTAssertEqual(duplicate.title, "Повторить")
        XCTAssertNil(duplicate.sourceID)
        XCTAssertNil(duplicate.googleEventID)
        XCTAssertEqual(duplicate.status, .active)
        XCTAssertEqual(duplicate.completedPomodoros, 0)
        XCTAssertFalse(try XCTUnwrap(duplicate.checklist.first).isCompleted)
        XCTAssertNotEqual(duplicate.checklist.first?.id, state.managedTasks[0].checklist.first?.id)
        XCTAssertEqual(state.managedTasks[0].sourceID, "ticktick-123")
    }

    func testPersistenceRoundTripAndLegacyMigration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        var state = PersistedAppState()
        _ = TaskEngine.addTask(title: "Сохраняется", listID: TaskList.inboxID, to: &state)
        try repository.save(state)
        let restored = try repository.load()
        XCTAssertEqual(restored.schemaVersion, 2)
        XCTAssertEqual(restored.managedTasks.map(\.title), ["Сохраняется"])

        let legacy = try JSONDecoder().decode(PersistedAppState.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.schemaVersion, 2)
        XCTAssertEqual(legacy.taskLists.first?.id, TaskList.inboxID)
    }

    func testRecurringTaskCalculation() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 13, hour: 10)))
        let rule = TaskRepeatRule(frequency: .weekly, interval: 2)
        let next = try XCTUnwrap(TaskEngine.nextOccurrence(after: start, for: rule, calendar: calendar))
        XCTAssertEqual(calendar.dateComponents([.day], from: start, to: next).day, 14)
    }

    func testCalendarDropRoundsToQuarterHourInUserTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 14)))
        let result = TaskEngine.calendarDropDate(
            on: day,
            yOffset: 3.62 * 64,
            hourHeight: 64,
            calendar: calendar
        )
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: result)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 14)
        XCTAssertEqual(components.hour, 10)
        XCTAssertEqual(components.minute, 30)
    }

    func testEisenhowerQuadrantsRoundTripToPriorityAndImportance() throws {
        var state = PersistedAppState()
        let id = try XCTUnwrap(TaskEngine.addTask(title: "Матрица", listID: TaskList.inboxID, to: &state))
        for quadrant in EisenhowerQuadrant.allCases {
            TaskEngine.setQuadrant(id, quadrant: quadrant, in: &state)
            XCTAssertEqual(state.managedTasks.first?.quadrant, quadrant)
        }
    }

    func testPomodoroStartPauseResumeFinishAndPersistence() throws {
        var state = PersistedAppState()
        let taskID = try XCTUnwrap(TaskEngine.addTask(title: "Фокус", listID: TaskList.inboxID, to: &state))
        let start = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(TaskEngine.startPomodoro(taskID: taskID, in: &state, now: start))
        TaskEngine.pausePomodoro(in: &state, now: start.addingTimeInterval(60))
        TaskEngine.resumePomodoro(in: &state, now: start.addingTimeInterval(90))
        let session = try XCTUnwrap(TaskEngine.finishPomodoro(in: &state, now: start.addingTimeInterval(150)))
        XCTAssertEqual(session.durationSeconds, 120)
        XCTAssertTrue(session.wasCompleted)
        XCTAssertEqual(state.managedTasks.first?.completedPomodoros, 1)
        XCTAssertNil(state.activePomodoro)
    }

    func testTickTickImportIsIdempotentAndKeepsCompletionChronology() throws {
        var state = PersistedAppState()
        let list = TaskList(name: "TickTick список", sourceID: "project-1")
        let newer = Date(timeIntervalSince1970: 2_000)
        let older = Date(timeIntervalSince1970: 1_000)
        let records = [
            TickTickImportRecord(sourceID: "active", projectSourceID: "project-1", title: "Активная"),
            TickTickImportRecord(sourceID: "old", projectSourceID: "project-1", title: "Старая", completedAt: older),
            TickTickImportRecord(sourceID: "new", projectSourceID: "project-1", title: "Новая", completedAt: newer)
        ]
        let first = TaskEngine.importTickTick(folders: [], lists: [list], records: records, into: &state)
        let second = TaskEngine.importTickTick(folders: [], lists: [list], records: records, into: &state)
        XCTAssertEqual(first.imported, 3)
        XCTAssertEqual(second.imported, 0)
        XCTAssertEqual(second.skipped, 3)
        XCTAssertEqual(state.managedTasks.count, 3)
        XCTAssertEqual(TaskEngine.completedTasks(in: state).map(\.sourceID), ["new", "old"])
    }

    func testTickTickReimportReconcilesCompletedAndReopenedStatuses() throws {
        var state = PersistedAppState()
        let list = TaskList(name: "TickTick список", sourceID: "project-1")
        let completedAt = Date(timeIntervalSince1970: 3_000)
        let active = TickTickImportRecord(sourceID: "task-1", projectSourceID: "project-1", title: "Задача")
        _ = TaskEngine.importTickTick(folders: [], lists: [list], records: [active], into: &state)

        var completed = active
        completed.completedAt = completedAt
        let completionReport = TaskEngine.importTickTick(
            folders: [], lists: [list], records: [completed], into: &state,
            now: Date(timeIntervalSince1970: 4_000)
        )
        XCTAssertEqual(completionReport.updated, 1)
        XCTAssertEqual(completionReport.skipped, 0)
        XCTAssertEqual(state.managedTasks.first?.status, .completed)
        XCTAssertEqual(state.managedTasks.first?.completedAt, completedAt)

        let reopenReport = TaskEngine.importTickTick(
            folders: [], lists: [list], records: [active], into: &state,
            now: Date(timeIntervalSince1970: 5_000)
        )
        XCTAssertEqual(reopenReport.updated, 1)
        XCTAssertEqual(state.managedTasks.first?.status, .active)
        XCTAssertNil(state.managedTasks.first?.completedAt)
    }
}
