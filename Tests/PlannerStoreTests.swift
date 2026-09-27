import XCTest
@testable import hidigFocus

final class PlannerStoreTests: XCTestCase {
    @MainActor func testRapidCalendarPreparationKeepsAnchorAndCompletesNearbyWindow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false, plannerDefaults: defaults)
        let calendar = PlannerCalendar.current
        let day = calendar.startOfDay(for: Date())
        store.planner.anchor = day
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Daily", startDate: day, repeatRule: TaskRepeatRule(frequency: .daily))))
        for distance in 0...20 {
            store.prepareCalendarIndex(around: calendar.date(byAdding: .day, value: distance, to: day)!)
        }
        for _ in 0..<100 where store.planner.preparingCalendar {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(store.planner.preparingCalendar)
        XCTAssertEqual(store.planner.anchor, day)
        let future = calendar.date(byAdding: .day, value: 20, to: day)!
        XCTAssertTrue(store.calendarTasks(on: future).contains { $0.seriesRootID == id })
        store.flushPendingWrites()
    }
    @MainActor func testCreateEditUndoRedoAndRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        let store = AppStore(repository: repository, startServices: false)
        let date = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970) + 3600)
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Одна операция", startDate: date, dueDate: date.addingTimeInterval(7200))))
        store.scheduleManagedTask(id, at: date.addingTimeInterval(900), durationMinutes: 45)
        XCTAssertEqual(store.task(id: id)?.dueDate, date.addingTimeInterval(7200))
        store.undoTaskAction(); XCTAssertEqual(store.task(id: id)?.startDate, date)
        store.undoTaskAction(); XCTAssertNil(store.task(id: id))
        store.redoTaskAction(); store.redoTaskAction()
        store.flushPendingWrites()
        XCTAssertEqual(try repository.load().managedTasks.first?.startDate, date.addingTimeInterval(900))
        XCTAssertEqual(try repository.load().managedTasks.first?.title, "Одна операция")
    }
    @MainActor func testEditingSingleRootOccurrencePreservesFutureSeries() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        let day = Calendar.current.startOfDay(for: Date())
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Серия", startDate: day, repeatRule: TaskRepeatRule(frequency: .daily))))
        let original = try XCTUnwrap(store.task(id: id)); var draft = original; draft.title = "Только сегодня"
        store.updateManagedTaskEdits(from: original, to: draft)
        XCTAssertEqual(store.task(id: id)?.title, "Серия")
        XCTAssertEqual(store.resolvedTask(id: id)?.title, "Только сегодня")
        let projection = RecurrenceProjection.tasks(store.state.managedTasks, from: day, to: day.addingTimeInterval(3 * 86400))
        XCTAssertEqual(projection.filter { $0.startDate == day }.count, 1)
        XCTAssertEqual(projection.filter { $0.startDate! > day }.map(\.title), ["Серия", "Серия"])
        store.flushPendingWrites()
    }
    @MainActor func testFutureOccurrenceEditSurvivesIndexInvalidation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        let day = Calendar.current.startOfDay(for: Date())
        _ = store.createPlannerTask(ManagedTask(title: "Повтор", startDate: day, repeatRule: TaskRepeatRule(frequency: .daily)))
        store.prepareCalendarIndex(force: true)
        for _ in 0..<100 { if !store.planner.preparingCalendar { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: day)!
        let occurrence = try XCTUnwrap(store.calendarTasks(on: tomorrow).first)
        store.selectedTaskID = occurrence.id
        _ = store.createPlannerTask(ManagedTask(title: "Другая задача"))
        store.selectedTaskID = occurrence.id
        var draft = occurrence; draft.description = "Локальная правка"
        store.updateManagedTaskEdits(from: occurrence, to: draft)
        XCTAssertEqual(store.task(id: occurrence.id)?.description, "Локальная правка")
        store.flushPendingWrites()
    }
    @MainActor func testFailedLoadNeverOverwritesCorruptDatabase() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("tasks.sqlite3")
        let bytes = Data("broken database".utf8); try bytes.write(to: file)
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        XCTAssertNotNil(store.errorMessage)
        _ = store.addManagedTask(named: "Не перезаписать")
        store.flushPendingWrites(); XCTAssertEqual(try Data(contentsOf: file), bytes)
    }
    @MainActor func testEnabledGroupChangesStayPendingUntilApply() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        let group = try XCTUnwrap(store.state.groups.first)
        store.setGroupEnabled(group.id, value: true)
        store.updateGroupName(group.id, name: "Новое правило")
        XCTAssertEqual(store.state.groups.first?.name, group.name)
        XCTAssertTrue(store.hasPendingGroupRule(group.id))
        store.applyGroupRule(group.id)
        XCTAssertEqual(store.state.groups.first?.name, "Новое правило")
        XCTAssertFalse(store.hasPendingGroupRule(group.id))
        store.flushPendingWrites()
    }
    @MainActor func testSubtaskMaterializesRecurringParent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Серия", startDate: Date(), repeatRule: TaskRepeatRule(frequency: .daily))))
        store.addSubtask(to: id, title: "Дочерняя")
        let child = try XCTUnwrap(store.state.managedTasks.first { $0.title == "Дочерняя" })
        let parent = try XCTUnwrap(store.task(id: try XCTUnwrap(child.parentTaskID)))
        XCTAssertEqual(parent.seriesRootID, id)
        store.flushPendingWrites()
    }

    @MainActor func testReadIndexesStayFreshAfterEditsUndoAndDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "hidigFocus.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false, plannerDefaults: defaults)
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Индекс")))
        XCTAssertEqual(store.visibleCount(selection: .all), 1)
        var task = try XCTUnwrap(store.task(id: id)); task.title = "Правка"
        store.bulkEdit([id]) { $0.title = task.title }
        XCTAssertEqual(store.task(id: id)?.title, "Правка")
        store.bulkComplete([id])
        XCTAssertEqual(store.visibleCount(selection: .all), 1)
        store.planner.filter.showCompleted = false
        XCTAssertEqual(store.visibleCount(selection: .all), 0)
        XCTAssertEqual(store.visibleCount(selection: .completed), 1)
        store.undoTaskAction()
        XCTAssertEqual(store.visibleCount(selection: .all), 1)
        store.bulkTrash([id])
        XCTAssertEqual(store.task(id: id)?.status, .trashed)
        XCTAssertEqual(store.visibleCount(selection: .trash), 1)
        store.planner.filter.showCompleted = true
        for selection in [TaskSidebarSelection.all, .today, .tomorrow, .nextSevenDays, .unscheduled, .inbox, .completed, .trash] {
            store.taskSidebarSelection = selection
            XCTAssertEqual(store.visibleCount(selection: selection), store.visibleManagedTasks.count)
        }
        store.flushPendingWrites()
    }

}
