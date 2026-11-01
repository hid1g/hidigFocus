import XCTest
@testable import hidigFocus

final class TaskHierarchyTests: XCTestCase {
    func testParentIncludesCompletedAndAbandonedChildrenWithoutGrandchildrenOrTrash() {
        let parent = ManagedTask(title: "Родитель")
        let active = ManagedTask(parentTaskID: parent.id, title: "Активная")
        let completed = ManagedTask(parentTaskID: parent.id, title: "Завершённая", status: .completed)
        let abandoned = ManagedTask(parentTaskID: parent.id, title: "Отменённая", status: .wontDo)
        let trash = ManagedTask(parentTaskID: parent.id, title: "Удалённая", status: .trashed)
        let nested = ManagedTask(parentTaskID: active.id, title: "Вложенная")
        let tasks = [parent, active, completed, abandoned, trash, nested]
        XCTAssertEqual(Set(TaskHierarchy.children(of: parent.id, in: tasks).map(\.id)), Set([active.id, completed.id, abandoned.id]))
        XCTAssertEqual(TaskHierarchy.children(of: active.id, in: tasks).map(\.id), [nested.id])
        XCTAssertEqual(tasks.first { $0.id == nested.parentTaskID }?.id, active.id)
    }

    func testImportedOrderWinsAndLocalChildrenUseManualOrder() {
        var parent = ManagedTask(title: "Родитель")
        parent.tickTickBaseline = TickTickImportRecord(sourceID: "parent", projectSourceID: "list", title: parent.title, childSourceIDs: ["b", "a", "b"])
        let a = ManagedTask(sourceID: "a", parentTaskID: parent.id, title: "A", sortOrder: 1)
        let b = ManagedTask(sourceID: "b", parentTaskID: parent.id, title: "B", sortOrder: 9)
        let localFirst = ManagedTask(parentTaskID: parent.id, title: "Локальная первая", sortOrder: 2)
        let localLast = ManagedTask(parentTaskID: parent.id, title: "Локальная последняя", sortOrder: 3)
        XCTAssertEqual(TaskHierarchy.children(of: parent.id, in: [localLast, a, parent, localFirst, b]).map(\.id), [b.id, a.id, localFirst.id, localLast.id])
    }

    func testHierarchySurvivesPersistenceAndCompletionChanges() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        let parent = ManagedTask(title: "Родитель")
        let child = ManagedTask(parentTaskID: parent.id, title: "Подзадача")
        var state = PersistedAppState()
        state.managedTasks = [parent, child]
        TaskEngine.setCompleted(child.id, completed: true, in: &state)
        try repository.save(state)
        let loaded = try repository.load()
        let children = TaskHierarchy.children(of: parent.id, in: loaded.managedTasks)
        XCTAssertEqual(children.map(\.id), [child.id])
        XCTAssertEqual(children.first?.status, .completed)
        XCTAssertEqual(children.first?.parentTaskID, parent.id)
    }
}
