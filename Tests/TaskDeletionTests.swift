import XCTest
@testable import hidigFocus

final class TaskDeletionTests: XCTestCase {
    @MainActor private func waitForCalendar(_ store: AppStore) async throws {
        for _ in 0..<200 where store.planner.preparingCalendar {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(store.planner.preparingCalendar)
    }

    @MainActor func testRecurringDeletionWaitsForChoiceAndCancelKeepsTasks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Серия", startDate: Date(), repeatRule: TaskRepeatRule(frequency: .daily))))
        let before = store.state.managedTasks
        store.requestTaskDeletion([id])
        XCTAssertEqual(store.pendingTaskDeletion, [id])
        XCTAssertEqual(store.state.managedTasks, before)
        store.pendingTaskDeletion = []
        store.confirmTaskDeletion(entireSeries: true)
        XCTAssertEqual(store.state.managedTasks, before)
        store.flushPendingWrites()
    }

    @MainActor func testDeletingOnlyFirstOccurrencePreservesFutureAndSupportsUndo() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        let day = PlannerCalendar.current.startOfDay(for: Date())
        let tomorrow = try XCTUnwrap(PlannerCalendar.current.date(byAdding: .day, value: 1, to: day))
        store.planner.anchor = day
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Серия", startDate: day, repeatRule: TaskRepeatRule(frequency: .daily))))
        try await waitForCalendar(store)
        store.requestTaskDeletion([id])
        store.confirmTaskDeletion(entireSeries: false)
        try await waitForCalendar(store)
        XCTAssertEqual(store.task(id: id)?.status, .active)
        XCTAssertTrue(store.calendarTasks(on: day).isEmpty)
        XCTAssertEqual(store.calendarTasks(on: tomorrow).map(\.status), [.active])
        XCTAssertEqual(store.state.managedTasks.filter { $0.status == .trashed }.count, 1)
        store.undoTaskAction()
        try await waitForCalendar(store)
        XCTAssertEqual(store.calendarTasks(on: day).map(\.id), [id])
        XCTAssertEqual(store.calendarTasks(on: tomorrow).map(\.status), [.active])
        store.flushPendingWrites()
    }

    @MainActor func testDeletingSeriesFromVirtualOccurrenceTrashesSavedMembersAndStopsProjection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        let day = PlannerCalendar.current.startOfDay(for: Date())
        let tomorrow = try XCTUnwrap(PlannerCalendar.current.date(byAdding: .day, value: 1, to: day))
        store.planner.anchor = day
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Серия", startDate: day, repeatRule: TaskRepeatRule(frequency: .daily))))
        let other = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Другая", startDate: day)))
        try await waitForCalendar(store)
        store.setManagedTaskCompleted(id, completed: true)
        try await waitForCalendar(store)
        let occurrence = try XCTUnwrap(store.calendarTasks(on: tomorrow).first)
        XCTAssertEqual(occurrence.seriesRootID, id)
        store.requestTaskDeletion([occurrence.id])
        XCTAssertEqual(store.pendingTaskDeletion, [occurrence.id])
        store.confirmTaskDeletion(entireSeries: true)
        try await waitForCalendar(store)
        XCTAssertEqual(store.task(id: id)?.status, .trashed)
        XCTAssertTrue(store.state.managedTasks.filter { $0.seriesRootID == id }.allSatisfy { $0.status == .trashed })
        XCTAssertTrue(store.calendarTasks(on: tomorrow).isEmpty)
        XCTAssertEqual(store.task(id: other)?.status, .active)
        store.undoTaskAction()
        try await waitForCalendar(store)
        XCTAssertEqual(store.calendarTasks(on: tomorrow).map(\.status), [.active])
        store.flushPendingWrites()
    }

    @MainActor func testOrdinaryTaskDeletesWithoutScopeChoice() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Обычная")))
        store.requestTaskDeletion([id])
        XCTAssertTrue(store.pendingTaskDeletion.isEmpty)
        XCTAssertEqual(store.task(id: id)?.status, .trashed)
        store.flushPendingWrites()
    }
}
