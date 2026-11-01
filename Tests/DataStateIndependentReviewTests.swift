import XCTest
@testable import hidigFocus

final class DataStateIndependentReviewTests: XCTestCase {
    @MainActor func testListDeletionRefreshesCachedBoardsListsMatrixAndSurvivesReload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "independent-state-review.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let repo = AppStateRepository(applicationSupportDirectory: directory)
        let store = AppStore(repository: repo, startServices: false, plannerDefaults: defaults)
        defer { store.flushPendingWrites() }
        store.addTaskFolder(named: "Folder")
        let folder = try XCTUnwrap(store.taskFolders.first { $0.name == "Folder" })
        store.addTaskList(named: "List", folderID: folder.id)
        let list = try XCTUnwrap(store.taskLists.first { $0.name == "List" })
        var task = ManagedTask(listID: list.id, title: "Preserve full record")
        task.notes = "Notes"; task.description = "Description"; task.tags = ["tag"]
        let id = try XCTUnwrap(store.createPlannerTask(task))
        store.taskSidebarSelection = .list(list.id)
        XCTAssertEqual(store.plannerListSnapshot(search: "", collapsed: []).tasks.map(\.id), [id])
        XCTAssertEqual(store.plannerKanbanSnapshot(search: "", scope: "active", allProjects: true).byProject[list.id]?.map(\.id), [id])
        store.removeTaskFolder(folder.id)
        XCTAssertNil(store.taskList(id: list.id)?.folderID)
        XCTAssertEqual(store.plannerListSnapshot(search: "", collapsed: []).tasks.map(\.id), [id])
        store.removeTaskList(list.id)
        XCTAssertEqual(store.taskSidebarSelection, .inbox)
        let result = store.plannerKanbanSnapshot(search: "", scope: "active", allProjects: true)
        XCTAssertNil(result.byProject[list.id])
        XCTAssertEqual(result.byProject[TaskList.inboxID]?.map(\.id), [id])
        XCTAssertEqual(store.plannerListSnapshot(search: "tag", collapsed: []).tasks.map(\.id), [id])
        store.taskSidebarSelection = .all
        store.setTaskQuadrant(id, .urgentImportant)
        XCTAssertEqual(store.matrixTasks(in: .urgentImportant).map(\.id), [id])
        store.setTaskQuadrant(id, .neither)
        XCTAssertTrue(store.matrixTasks(in: .urgentImportant).isEmpty)
        XCTAssertEqual(store.matrixTasks(in: .neither).map(\.id), [id])
        store.flushPendingWrites()
        let saved = try XCTUnwrap(repo.load().managedTasks.first { $0.id == id })
        XCTAssertEqual(saved.notes, "Notes"); XCTAssertEqual(saved.description, "Description"); XCTAssertEqual(saved.tags, ["tag"])
        XCTAssertEqual(saved.listID, TaskList.inboxID)
    }

    @MainActor func testDaySnapshotsRefreshTaskContentSearchPriorityAndPartitions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "independent-day-review.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false, plannerDefaults: defaults)
        defer { store.flushPendingWrites() }
        let day = PlannerCalendar.current.startOfDay(for: Date())
        let date = PlannerCalendar.current.date(bySettingHour: 10, minute: 30, second: 0, of: day)!
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Initial", startDate: date, durationMinutes: 60)))
        let first = store.plannerDaySnapshot(on: day, search: "")
        XCTAssertEqual(first.timedTasks.map(\.id), [id])
        XCTAssertEqual(first.intervals[id.uuidString]?.start, 630)
        var updated = try XCTUnwrap(store.task(id: id)); updated.title = "Changed"; updated.priority = .high
        store.updateManagedTask(updated)
        XCTAssertEqual(store.plannerDaySnapshot(on: day, search: "Changed").tasks.first?.title, "Changed")
        XCTAssertTrue(store.plannerDaySnapshot(on: day, search: "Initial").tasks.isEmpty)
        var filter = store.planner.filter; filter.priority = .low; store.planner.filter = filter
        XCTAssertTrue(store.plannerDaySnapshot(on: day, search: "").tasks.isEmpty)
        filter.priority = nil; store.planner.filter = filter
        store.scheduleManagedTask(id, at: day, allDay: true)
        let allDay = store.plannerDaySnapshot(on: day, search: "")
        XCTAssertEqual(allDay.allDayTasks.map(\.id), [id]); XCTAssertTrue(allDay.timedTasks.isEmpty)
        XCTAssertNil(allDay.intervals[id.uuidString])
        store.trashManagedTask(id)
        XCTAssertTrue(store.plannerDaySnapshot(on: day, search: "").tasks.isEmpty)
        store.restoreManagedTask(id)
        XCTAssertEqual(store.plannerDaySnapshot(on: day, search: "").allDayTasks.map(\.id), [id])
    }
}
