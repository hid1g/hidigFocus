import XCTest
@testable import hidigFocus

final class PlannerRegressionTests: XCTestCase {
    func testRemoteMoveClearedDatesAndLocalEditsReconcileWithoutDuplicates() throws {
        var state = PersistedAppState()
        let a = TaskList(name: "A", sourceID: "a")
        let b = TaskList(name: "B", sourceID: "b")
        var remote = TickTickImportRecord(sourceID: "1", projectSourceID: "a", title: "Original",
            startDate: Date(timeIntervalSince1970: 1000), dueDate: Date(timeIntervalSince1970: 2000))
        _ = TaskEngine.importTickTick(folders: [], lists: [a, b], records: [remote], into: &state)
        let id = try XCTUnwrap(state.managedTasks.first?.id)
        state.managedTasks[0].description = "Local description"
        remote.projectSourceID = "b"
        remote.title = "Moved"
        remote.startDate = nil
        remote.dueDate = nil
        remote.durationMinutes = 240
        let report = TaskEngine.importTickTick(folders: [], lists: [a, b], records: [remote], into: &state)
        XCTAssertEqual(report.updated, 1)
        XCTAssertEqual(state.managedTasks.count, 1)
        XCTAssertEqual(state.managedTasks[0].id, id)
        XCTAssertEqual(state.managedTasks[0].listID, b.id)
        XCTAssertEqual(state.managedTasks[0].title, "Moved")
        XCTAssertEqual(state.managedTasks[0].description, "Local description")
        XCTAssertNil(state.managedTasks[0].startDate)
        XCTAssertNil(state.managedTasks[0].dueDate)
        XCTAssertEqual(state.managedTasks[0].durationMinutes, 240)
        let again = TaskEngine.importTickTick(folders: [], lists: [a, b], records: [remote], into: &state)
        XCTAssertEqual(again.updated, 0)
    }

    func testEditingDescriptionDoesNotOverwriteConcurrentSyncOrCompletion() throws {
        var state = PersistedAppState()
        _ = TaskEngine.addTask(title: "Original", listID: TaskList.inboxID, to: &state)
        let original = try XCTUnwrap(state.managedTasks.first)
        var draft = original
        draft.description = "Typed text"
        state.managedTasks[0].title = "Synced title"
        state.managedTasks[0].status = .completed
        TaskEngine.applyEdits(from: original, to: draft, in: &state)
        XCTAssertEqual(state.managedTasks[0].title, "Synced title")
        XCTAssertEqual(state.managedTasks[0].status, .completed)
        XCTAssertEqual(state.managedTasks[0].description, "Typed text")
    }

    func testRecurringActiveOccurrenceWinsAndDurationComesFromDates() throws {
        let service = TickTickCLIService()
        let rows: [[String: Any]] = [
            ["id": "repeat", "projectId": "p", "title": "Old", "status": 2,
             "completedTime": "2026-09-20T08:00:00+0000"],
            ["id": "repeat", "projectId": "p", "title": "Current", "status": 0,
             "startDate": "2026-09-21T11:00:00+0000", "dueDate": "2026-09-21T15:00:00+0000",
             "reminders": ["TRIGGER:PT0S"]]
        ]
        let projects = Data(#"[{"id":"p","name":"Project"}]"#.utf8)
        let first = try service.importSnapshot(projects: projects, rows: rows)
        let second = try service.importSnapshot(projects: projects, rows: rows.reversed())
        XCTAssertEqual(first.records, second.records)
        XCTAssertEqual(first.records.count, 1)
        XCTAssertFalse(try XCTUnwrap(first.records.first).completed)
        XCTAssertEqual(first.records.first?.durationMinutes, 240)
        XCTAssertEqual(first.records.first?.title, "Current")
    }

    func testOverlapsHaveSeparateLanesAndAdjacentEventsReuseSpace() {
        let result = PlannerLayout.placements([
            PlannerInterval(id: "long", start: 0, end: 240),
            PlannerInterval(id: "first", start: 0, end: 60),
            PlannerInterval(id: "second", start: 60, end: 120),
            PlannerInterval(id: "later", start: 240, end: 300)
        ])
        XCTAssertEqual(result["long"]?.laneCount, 2)
        XCTAssertNotEqual(result["long"]?.lane, result["first"]?.lane)
        XCTAssertEqual(result["first"]?.lane, result["second"]?.lane)
        XCTAssertEqual(result["later"]?.laneCount, 1)
    }

    func testQuarterHourTasksTouchingAtBoundaryKeepFullWidth() {
        let result = PlannerLayout.placements([
            PlannerInterval(id: "first", start: 20 * 60 + 45, end: 21 * 60),
            PlannerInterval(id: "second", start: 21 * 60, end: 21 * 60 + 15)
        ])
        XCTAssertEqual(result["first"]?.laneCount, 1)
        XCTAssertEqual(result["second"]?.laneCount, 1)
    }

    func testDraggingResetsOldDeadlineAndUnscheduledClearsDates() throws {
        var state = PersistedAppState()
        let id = try XCTUnwrap(TaskEngine.addTask(title: "Task", listID: TaskList.inboxID, to: &state))
        let date = Date(timeIntervalSince1970: 10000)
        TaskEngine.schedule(id, at: date, durationMinutes: 90, in: &state)
        XCTAssertEqual(state.managedTasks[0].dueDate, date.addingTimeInterval(5400))
        TaskEngine.schedule(id, at: nil, in: &state)
        XCTAssertNil(state.managedTasks[0].startDate)
        XCTAssertNil(state.managedTasks[0].dueDate)
    }
}
