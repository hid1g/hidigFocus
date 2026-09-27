import XCTest
@testable import hidigFocus

final class PlannerRegressionTests: XCTestCase {
    func testImportRestoresNestedHierarchyInAnyOrderWithoutReplacingLocalEdits() throws {
        let projects = Data(#"[{"id":"p","name":"Project"}]"#.utf8)
        let rows: [[String: Any]] = [
            ["id":"leaf", "projectId":"p", "title":"Leaf", "parentId":"child", "status":2],
            ["id":"child", "projectId":"p", "title":"Child", "parentId":"root", "status":0],
            ["id":"root", "projectId":"p", "title":"Root", "childIds":["child"], "status":0]
        ]
        let snapshot = try TickTickCLIService().importSnapshot(projects: projects, rows: rows)
        var state = PersistedAppState()
        _ = TaskEngine.importTickTick(folders: [], lists: snapshot.lists, records: snapshot.records, into: &state)
        let root = try XCTUnwrap(state.managedTasks.first { $0.sourceID == "root" })
        let child = try XCTUnwrap(state.managedTasks.first { $0.sourceID == "child" })
        let leaf = try XCTUnwrap(state.managedTasks.first { $0.sourceID == "leaf" })
        XCTAssertEqual(child.parentTaskID, root.id)
        XCTAssertEqual(leaf.parentTaskID, child.id)
        XCTAssertEqual(leaf.status, .completed)
        let index = try XCTUnwrap(state.managedTasks.firstIndex { $0.id == child.id })
        state.managedTasks[index].title = "Local title"
        _ = TaskEngine.importTickTick(folders: [], lists: snapshot.lists, records: snapshot.records.reversed(), into: &state)
        XCTAssertEqual(state.managedTasks[index].title, "Local title")
        XCTAssertEqual(state.managedTasks.count, 3)
        let tree = PlannerTaskTree.rows(state.managedTasks)
        XCTAssertEqual(tree.map(\.id), [root.id,child.id,leaf.id])
        XCTAssertEqual(tree.map(\.depth), [0,1,2])
        XCTAssertEqual(PlannerTaskTree.rows(state.managedTasks, collapsed: [root.id]).map(\.id), [root.id])
        XCTAssertEqual(PlannerTaskTree.rows([leaf]).map(\.id), [leaf.id])
    }

    func testHierarchyResolvesMissingParentsLaterAndRejectsCycles() throws {
        var state = PersistedAppState()
        let child = TickTickImportRecord(sourceID: "child", projectSourceID: "p", title: "Child", parentSourceID: "root")
        let root = TickTickImportRecord(sourceID: "root", projectSourceID: "p", title: "Root", childSourceIDs: ["child"])
        _ = TaskEngine.importTickTick(folders: [], lists: [], records: [child], into: &state)
        XCTAssertNil(state.managedTasks[0].parentTaskID)
        _ = TaskEngine.importTickTick(folders: [], lists: [], records: [root], into: &state)
        XCTAssertEqual(state.managedTasks[0].parentTaskID, state.managedTasks[1].id)
        var cycle = PersistedAppState()
        var cyclicRoot = root; cyclicRoot.parentSourceID = "child"
        _ = TaskEngine.importTickTick(folders: [], lists: [], records: [child, cyclicRoot], into: &cycle)
        XCTAssertTrue(cycle.managedTasks.allSatisfy { $0.parentTaskID == nil })
    }

    func testAbandonedSourceParentKeepsItsStatus() throws {
        let snapshot = try TickTickCLIService().importSnapshot(projects: Data("[]".utf8), rows: [
            ["id":"parent", "projectId":"p", "title":"Parent", "status":-1],
            ["id":"child", "projectId":"p", "title":"Child", "status":2, "parentId":"parent"]
        ])
        var state = PersistedAppState()
        _ = TaskEngine.importTickTick(folders: [], lists: [], records: snapshot.records, into: &state)
        XCTAssertEqual(state.managedTasks[0].status, .wontDo)
        XCTAssertEqual(state.managedTasks[1].parentTaskID, state.managedTasks[0].id)
    }

    func testHierarchyUpgradeDoesNotReopenLocallyCompletedTasks() {
        var state = PersistedAppState()
        var remote = TickTickImportRecord(sourceID: "child", projectSourceID: "p", title: "Child", isCompleted: false)
        _ = TaskEngine.importTickTick(folders: [], lists: [], records: [remote], into: &state)
        state.managedTasks[0].status = .completed
        remote.isAbandoned = false
        remote.parentSourceID = "parent"
        let parent = TickTickImportRecord(sourceID: "parent", projectSourceID: "p", title: "Parent")
        _ = TaskEngine.importTickTick(folders: [], lists: [], records: [remote,parent], into: &state)
        XCTAssertEqual(state.managedTasks[0].status, .completed)
        XCTAssertEqual(state.managedTasks[0].parentTaskID, state.managedTasks[1].id)
    }

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

    func testDraggingChangesPlannedIntervalAndUnscheduledClearsPlan() throws {
        var state = PersistedAppState()
        let id = try XCTUnwrap(TaskEngine.addTask(title: "Task", listID: TaskList.inboxID, to: &state))
        let date = Date(timeIntervalSince1970: 10000)
        TaskEngine.schedule(id, at: date, durationMinutes: 90, in: &state)
        XCTAssertEqual(state.managedTasks[0].plannedEndDate, date.addingTimeInterval(5400))
        XCTAssertNil(state.managedTasks[0].dueDate)
        TaskEngine.schedule(id, at: nil, in: &state)
        XCTAssertNil(state.managedTasks[0].startDate)
        XCTAssertNil(state.managedTasks[0].dueDate)
    }
}
