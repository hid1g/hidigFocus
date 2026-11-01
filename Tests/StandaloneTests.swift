import XCTest
@testable import hidigFocus

final class StandaloneTests: XCTestCase {
    @MainActor func testStoredPlannerTasksControlGroupsWithoutAnAccountOrFreshSync() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = AppStateRepository(applicationSupportDirectory: dir)
        let day = PlannerCalendar.current.startOfDay(for: Date())
        let imported = ManagedTask(sourceID: "external-task", sourceName: "TickTick", title: "Импорт",
                                   startDate: day, isAllDay: true)
        let local = ManagedTask(title: "Локальная", startDate: day, isAllDay: true)
        var state = PersistedAppState()
        state.managedTasks = [imported, local]
        let group = BlockGroup(name: "По задаче", resources: [], requiresAllTodayTasks: false,
                               requiredTaskIDs: ["external-task"])
        state.groups = [group]
        state.lastSuccessfulSync = Date.distantPast
        try repository.save(state)
        let persistedTasks = try repository.load().managedTasks
        let store = AppStore(repository: repository, startServices: false)
        XCTAssertEqual(store.connectionState, .notRequested)
        XCTAssertEqual(store.state.managedTasks, persistedTasks)
        XCTAssertEqual(Set(store.todayTasks.map(\.id)), ["external-task", local.id.uuidString])
        XCTAssertFalse(store.groupIsUnlocked(group))
        XCTAssertEqual(store.remainingTaskCount(for: group), 1)
        store.integration.connectionState = .failed("Нет авторизации")
        store.setManagedTaskCompleted(imported.id, completed: true)
        XCTAssertTrue(store.groupIsUnlocked(group))
        XCTAssertEqual(store.remainingTaskCount(for: group), 0)
        store.flushPendingWrites()
        XCTAssertEqual(try repository.load().managedTasks.first?.status, .completed)
    }

    @MainActor func testLegacyCacheDoesNotOverrideLocallyMovedOrDeletedTasks() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = AppStateRepository(applicationSupportDirectory: dir)
        let today = PlannerCalendar.current.startOfDay(for: Date())
        var state = PersistedAppState()
        state.managedTasks = [ManagedTask(sourceID: "moved", sourceName: "TickTick", title: "Завтра",
                                         startDate: today.addingTimeInterval(86400), isAllDay: true),
                              ManagedTask(sourceID: "deleted", sourceName: "TickTick", title: "Удалена",
                                         startDate: today, isAllDay: true, status: .trashed)]
        state.cachedTasks = ["moved", "deleted", "legacy"].map {
            TickTickTask(id: $0, projectID: "old", projectName: "Old", title: $0,
                         dueDate: today, status: 0)
        }
        try repository.save(state)
        let persistedTasks = try repository.load().managedTasks
        let store = AppStore(repository: repository, startServices: false)
        XCTAssertEqual(store.todayTasks.map(\.id), ["legacy"])
        let empty = BlockGroup(name: "Не открывать без задач", resources: [], requiresAllTodayTasks: false,
                               requiredTaskIDs: ["missing"])
        XCTAssertFalse(store.groupIsUnlocked(empty))
        XCTAssertEqual(store.state.managedTasks, persistedTasks)
        store.flushPendingWrites()
    }

    func testAdditiveImportPreservesExistingTasksListsAndHierarchyAndAvoidsDuplicates() throws {
        let list = TaskList(name: "Моё название", sortOrder: 9, sourceID: "project")
        let parent = ManagedTask(sourceID: "parent", sourceName: "TickTick", listID: list.id,
                                 title: "Моя правка", startDate: Date(), status: .completed)
        var child = ManagedTask(sourceID: "child", sourceName: "TickTick", listID: list.id,
                                title: "Своя подзадача", status: .trashed)
        child.parentTaskID = parent.id
        var state = PersistedAppState()
        state.taskLists.append(list)
        state.managedTasks = [parent, child]
        let existing = state.managedTasks
        let existingLists = state.taskLists
        let records = [TickTickImportRecord(sourceID: "parent", projectSourceID: "project", title: "Из источника"),
                       TickTickImportRecord(sourceID: "child", projectSourceID: "project", title: "Изменённая",
                                            parentSourceID: nil),
                       TickTickImportRecord(sourceID: "new", projectSourceID: "project", title: "Новая",
                                            parentSourceID: "parent")]
        let changedList = TaskList(name: "Переименован в TickTick", sortOrder: 1, sourceID: "project")
        let report = TaskEngine.importTickTick(folders: [], lists: [changedList], records: records,
                                               into: &state, completeSnapshot: true, preserveExisting: true)
        XCTAssertEqual(Array(state.managedTasks.prefix(2)), existing)
        XCTAssertEqual(state.taskLists, existingLists)
        XCTAssertEqual(report.imported, 1)
        XCTAssertEqual(report.updated, 0)
        XCTAssertEqual(report.skipped, 2)
        XCTAssertEqual(state.managedTasks.last?.parentTaskID, parent.id)
        let after = state.managedTasks
        _ = TaskEngine.importTickTick(folders: [], lists: [changedList], records: records,
                                      into: &state, preserveExisting: true)
        XCTAssertEqual(state.managedTasks, after)
    }

    @MainActor func testQuickLocalTaskUsesPlannerAndLegacyLocalTasksRemainAvailable() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = AppStateRepository(applicationSupportDirectory: dir)
        var state = PersistedAppState()
        let legacy = FocusTask(title: "Старая")
        state.localTasks = [legacy]
        try repository.save(state)
        let store = AppStore(repository: repository, startServices: false)
        store.addLocalTask(named: "Новая")
        XCTAssertEqual(store.state.localTasks, [legacy])
        XCTAssertEqual(store.state.managedTasks.last?.title, "Новая")
        XCTAssertEqual(store.todayTasks.count, 2)
        store.flushPendingWrites()
    }
}
