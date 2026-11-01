import Combine
import XCTest
@testable import hidigFocus

final class PlannerProjectionCacheTests: XCTestCase {
    @MainActor private func withStore(_ body: (AppStore) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "projection-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false, plannerDefaults: defaults)
        defer { store.flushPendingWrites() }
        try body(store)
    }

    @MainActor func testBoardCachedGroupingMatchesReferenceAcrossScopesFiltersAndSorts() throws {
        try withStore { store in
            store.addTaskList(named: "Project")
            let project = try XCTUnwrap(store.taskLists.first { $0.name == "Project" })
            for i in 0..<24 {
                var task = ManagedTask(listID: i % 2 == 0 ? project.id : TaskList.inboxID, title: "Task \(24-i)")
                task.priority = i % 3 == 0 ? .high : .none
                task.status = [.active, .completed, .wontDo, .trashed][i % 4]
                task.sortOrder = Int64(i % 5)
                task.kanbanStage = i % 2 == 0 ? .planned : .inProgress
                _ = store.createPlannerTask(task)
            }
            store.taskSidebarSelection = .all
            for sort in PlannerSort.allCases {
                store.planner.sort = sort
                for scope in ["active", "archive", "trash"] {
                    for allProjects in [false, true] {
                        for search in ["", "Task 2"] {
                            var filter = PlannerFilter(); filter.showCompleted = false
                            filter.priority = search.isEmpty ? nil : .high
                            store.planner.filter = filter
                            let source = !allProjects && scope == "active" ? store.visibleManagedTasks : store.kanbanManagedTasks
                            let expected = filter.sorted(source.filter {
                                let belongs = scope == "trash" ? $0.status == .trashed : (scope == "archive" ? $0.status == .completed || $0.status == .wontDo : $0.status == .active)
                                return belongs && filter.matches($0, search: search, includeTrash: scope == "trash", includeCompleted: scope == "archive")
                            }, by: sort)
                            let result = store.plannerKanbanSnapshot(search: search, scope: scope, allProjects: allProjects)
                            XCTAssertEqual(result.tasks, expected)
                            for id in Set(expected.map(\.listID)) { XCTAssertEqual(result.byProject[id], expected.filter { $0.listID == id }) }
                            for stage in TaskKanbanStage.allCases { XCTAssertEqual(result.byStage[stage] ?? [], expected.filter { $0.effectiveKanbanStage == stage }) }
                            let count = store.taskProjectionPreparationCount
                            XCTAssertEqual(store.plannerKanbanSnapshot(search: search, scope: scope, allProjects: allProjects).tasks, expected)
                            XCTAssertEqual(store.taskProjectionPreparationCount, count)
                        }
                    }
                }
            }
        }
    }

    @MainActor func testListFreshAfterEditUndoDeleteRestoreAndCollapsedTree() throws {
        try withStore { store in
            store.taskSidebarSelection = .all
            let parentID = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Parent")))
            var child = ManagedTask(title: "Child"); child.parentTaskID = parentID
            let childID = try XCTUnwrap(store.createPlannerTask(child))
            let initial = store.plannerListSnapshot(search: "", collapsed: [])
            XCTAssertEqual(initial.rows.map(\.id), [parentID, childID])
            XCTAssertEqual(initial.rows.map(\.depth), [0, 1])
            XCTAssertEqual(store.plannerListSnapshot(search: "", collapsed: [parentID]).rows.map(\.id), [parentID])
            var updated = try XCTUnwrap(store.task(id: childID)); updated.title = "Edited"
            store.updateManagedTask(updated)
            XCTAssertEqual(store.plannerListSnapshot(search: "Edited", collapsed: []).tasks.map(\.id), [childID])
            store.undoTaskAction()
            XCTAssertTrue(store.plannerListSnapshot(search: "Edited", collapsed: []).tasks.isEmpty)
            store.trashManagedTask(childID)
            XCTAssertFalse(store.plannerListSnapshot(search: "", collapsed: []).tasks.contains { $0.id == childID })
            store.restoreManagedTask(childID)
            XCTAssertTrue(store.plannerListSnapshot(search: "", collapsed: []).tasks.contains { $0.id == childID })
        }
    }

    @MainActor func testJournalSavingAndHeartbeatNeverPublishToTaskStore() throws {
        try withStore { store in
            var publications = 0, journalPublications = 0, savePublications = 0, integrationPublications = 0
            let tokens = [store.objectWillChange.sink { publications += 1 },
                          store.journal.objectWillChange.sink { journalPublications += 1 },
                          store.saving.objectWillChange.sink { savePublications += 1 },
                          store.integration.objectWillChange.sink { integrationPublications += 1 }]
            _ = store.plannerListSnapshot(search: "", collapsed: [])
            let count = store.taskProjectionPreparationCount
            store.updateJournalDraft("Local journal draft")
            store.journalTitleDraft = "Draft title"
            store.saving.taskSaveState = .saving
            store.integration.browserExtensionLastContact = Date()
            store.integration.safariExtensionLastContact = Date()
            store.integration.connectionState = .checking
            store.integration.isSynchronizing = true
            XCTAssertEqual(publications, 0)
            XCTAssertGreaterThan(journalPublications, 0)
            XCTAssertGreaterThan(savePublications, 0)
            XCTAssertGreaterThan(integrationPublications, 0)
            XCTAssertEqual(store.journalDraft, "Local journal draft")
            XCTAssertTrue(store.browserExtensionIsConnected)
            XCTAssertTrue(store.safariExtensionIsConnected)
            _ = store.plannerListSnapshot(search: "", collapsed: [])
            XCTAssertEqual(store.taskProjectionPreparationCount, count)
            withExtendedLifetime(tokens) {}
        }
    }

    func testExactDeadlineCalendarAndDayInvalidateCachedSections() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let first = calendar.startOfDay(for: day)
        let due = first.addingTimeInterval(3600)
        var task = ManagedTask(title: "Due", dueDate: due)
        task.isAllDay = false
        let cache = PlannerProjectionCache()
        var key = PlannerProjectionKey(revision: 1, selection: .all, filter: PlannerFilter(), sort: .date,
            search: "", calendar: calendar, day: first, kind: "list")
        func prepare() -> PlannerTaskSnapshot { PlannerTaskSnapshot(tasks: [task], rows: PlannerTaskTree.rows([task])) }
        _ = cache.value(for: key, now: due.addingTimeInterval(-1), prepare: prepare)
        _ = cache.value(for: key, now: due, prepare: prepare)
        XCTAssertEqual(cache.preparationCount, 1)
        _ = cache.value(for: key, now: due.addingTimeInterval(0.01), prepare: prepare)
        XCTAssertEqual(cache.preparationCount, 2)
        key.calendar.firstWeekday = 2
        _ = cache.value(for: key, now: due.addingTimeInterval(1), prepare: prepare)
        XCTAssertEqual(cache.preparationCount, 3)
        key.day = calendar.date(byAdding: .day, value: 1, to: first)!
        _ = cache.value(for: key, now: key.day, prepare: prepare)
        XCTAssertEqual(cache.preparationCount, 4)
    }

    func testCalendarIndexDoesNotReuseDifferentCalendarContext() {
        let index = PlannerCalendarIndex()
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        index.replaceTasks([ManagedTask(title: "Task", startDate: day)])
        _ = index.day(day, calendar: calendar)
        XCTAssertNotNil(index.cachedDay(day, calendar: calendar))
        calendar.firstWeekday = 2
        XCTAssertNil(index.cachedDay(day, calendar: calendar))
        _ = index.day(day, calendar: calendar)
        XCTAssertEqual(index.generation, 2)
    }
    func testDaySnapshotPreservesIntervalsPlacementsAndAllDayPartitions() {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let day = calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))!
        let first = calendar.date(bySettingHour: 9, minute: 15, second: 0, of: day)!
        let second = calendar.date(bySettingHour: 9, minute: 30, second: 0, of: day)!
        let task = ManagedTask(title: "Overlap", startDate: first, durationMinutes: 60)
        let allDay = ManagedTask(title: "All day", startDate: day, isAllDay: true)
        let event = GoogleCalendarEventSnapshot(id: "remote", calendarID: "calendar", title: "Remote", description: "",
            startDate: second, endDate: second.addingTimeInterval(1800), isAllDay: false,
            timeZoneID: calendar.timeZone.identifier, updatedAt: day)
        let snapshot = PlannerDaySnapshot(tasks: [allDay, task], events: [event], day: day, calendar: calendar)
        XCTAssertEqual(snapshot.tasks.map(\.id), [allDay.id, task.id])
        XCTAssertEqual(snapshot.allDayTasks.map(\.id), [allDay.id])
        XCTAssertEqual(snapshot.timedTasks.map(\.id), [task.id])
        let expected = [PlannerInterval(id: task.id.uuidString, start: 555, end: 615), PlannerInterval(id: event.identity, start: 570, end: 600)]
        XCTAssertEqual(snapshot.intervals[task.id.uuidString], expected[0])
        XCTAssertEqual(snapshot.intervals[event.identity], expected[1])
        XCTAssertEqual(snapshot.placements, PlannerLayout.placements(expected))
    }


    @MainActor func testCorruptLoadEditsRefreshQueriesWithoutOverwritingDatabase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "corrupt-cache-tests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let database = directory.appendingPathComponent("tasks.sqlite3")
        let original = Data("This is deliberately not a SQLite database".utf8)
        try original.write(to: database)
        defer { try? FileManager.default.removeItem(at: directory); defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false, plannerDefaults: defaults)
        XCTAssertNotNil(store.errorMessage)
        store.taskSidebarSelection = .all
        XCTAssertTrue(store.plannerListSnapshot(search: "", collapsed: []).tasks.isEmpty)
        XCTAssertTrue(store.plannerKanbanSnapshot(search: "", scope: "active", allProjects: true).tasks.isEmpty)
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Unsaved recovery edit")))
        XCTAssertEqual(store.plannerListSnapshot(search: "", collapsed: []).tasks.map(\.id), [id])
        XCTAssertEqual(store.plannerKanbanSnapshot(search: "", scope: "active", allProjects: true).tasks.map(\.id), [id])
        XCTAssertEqual(store.visibleCount(selection: .all), 1)
        var changed = try XCTUnwrap(store.task(id: id)); changed.title = "Changed recovery edit"
        store.updateManagedTask(changed)
        XCTAssertEqual(store.plannerListSnapshot(search: "Changed", collapsed: []).tasks.first?.title, changed.title)
        store.trashManagedTask(id)
        XCTAssertTrue(store.plannerKanbanSnapshot(search: "", scope: "active", allProjects: true).tasks.isEmpty)
        store.flushPendingWrites()
        XCTAssertEqual(try Data(contentsOf: database), original)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.taskSaveState, .idle)
    }

}
