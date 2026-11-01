import XCTest
@testable import hidigFocus

final class PlannerStoreTests: XCTestCase {
    @MainActor func testMatrixOnlyShowsActiveTasksFromCurrentSection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        store.addTaskList(named: "Проект")
        let project = try XCTUnwrap(store.taskLists.first(where: { $0.name == "Проект" }))

        var projectTask = ManagedTask(listID: project.id, title: "Активная")
        projectTask.quadrant = .urgentImportant
        let projectTaskID = try XCTUnwrap(store.createPlannerTask(projectTask))

        var completedTask = ManagedTask(listID: project.id, title: "Выполненная")
        completedTask.quadrant = .urgentImportant
        let completedTaskID = try XCTUnwrap(store.createPlannerTask(completedTask))
        store.setManagedTaskCompleted(completedTaskID, completed: true)

        var inboxTask = ManagedTask(title: "Из другого списка")
        inboxTask.quadrant = .urgentImportant
        _ = store.createPlannerTask(inboxTask)

        store.planner.filter.showCompleted = true
        store.taskSidebarSelection = .list(project.id)

        XCTAssertEqual(store.matrixTasks(in: .urgentImportant).map(\.id), [projectTaskID])
        store.flushPendingWrites()
    }

    @MainActor func testKanbanMoveUpdatesStageCompletionAndUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Карточка")))

        store.moveManagedTask(id, toKanbanStage: .inProgress)
        XCTAssertEqual(store.task(id: id)?.effectiveKanbanStage, .inProgress)
        XCTAssertEqual(store.task(id: id)?.status, .active)

        store.moveManagedTask(id, toKanbanStage: .done)
        XCTAssertEqual(store.task(id: id)?.effectiveKanbanStage, .done)
        XCTAssertEqual(store.task(id: id)?.status, .completed)
        XCTAssertNotNil(store.task(id: id)?.completedAt)

        store.undoTaskAction()
        XCTAssertEqual(store.task(id: id)?.effectiveKanbanStage, .inProgress)
        XCTAssertEqual(store.task(id: id)?.status, .active)
    }

    @MainActor func testKanbanMoveBetweenProjectsUpdatesListAndUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        store.addTaskList(named: "Проект")
        let project = try XCTUnwrap(store.taskLists.first(where: { $0.name == "Проект" }))
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Карточка")))

        store.moveManagedTask(id, toList: project.id)

        XCTAssertEqual(store.task(id: id)?.listID, project.id)
        XCTAssertEqual(store.task(id: id)?.changeHistory.first?.summary, "Проект: Проект")
        store.undoTaskAction()
        XCTAssertEqual(store.task(id: id)?.listID, TaskList.inboxID)
    }

    @MainActor func testKanbanDoneUsesRecurringCompletionWorkflow() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        let start = PlannerCalendar.current.startOfDay(for: Date())
        let id = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Повтор",
            startDate: start, repeatRule: TaskRepeatRule(frequency: .daily))))

        store.moveManagedTask(id, toKanbanStage: .done)

        let completed = try XCTUnwrap(store.task(id: id))
        XCTAssertEqual(completed.status, .completed)
        let nextID = try XCTUnwrap(completed.nextOccurrenceID)
        XCTAssertEqual(store.task(id: nextID)?.status, .active)
        XCTAssertEqual(store.task(id: nextID)?.effectiveKanbanStage, .inProgress)
    }

    @MainActor func testTickTickDisconnectPreservesAllStoredTaskData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        var state = PersistedAppState()
        let imported = ManagedTask(sourceID: "ticktick-1", sourceName: "TickTick", title: "Импортирована")
        state.managedTasks = [imported]
        state.cachedTasks = [TickTickTask(id: "ticktick-1", projectID: "list", projectName: "Список", title: imported.title,
                                          dueDate: Date(), completedAt: nil, status: 0)]
        state.lastSuccessfulSync = Date()
        try repository.save(state)
        let persisted = try repository.load()
        let store = AppStore(repository: repository, startServices: false)

        store.finishTickTickDisconnect()

        XCTAssertEqual(store.connectionState, .signedOut)
        XCTAssertEqual(store.state.cachedTasks, persisted.cachedTasks)
        XCTAssertEqual(store.state.lastSuccessfulSync, persisted.lastSuccessfulSync)
        XCTAssertEqual(store.state.managedTasks.map(\.id), [imported.id])
        store.flushPendingWrites()
        let saved = try repository.load()
        XCTAssertEqual(saved.cachedTasks, persisted.cachedTasks)
        XCTAssertEqual(saved.managedTasks.map(\.id), [imported.id])
    }

    @MainActor func testCompletingShortImportedRecurrenceChangesOnlySelectedDay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "hidigFocus.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false, plannerDefaults: defaults)
        let day = PlannerCalendar.current.startOfDay(for: Date())
        let tomorrow = try XCTUnwrap(PlannerCalendar.current.date(byAdding: .day, value: 1, to: day))
        let rootID = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "15 минут", startDate: day.addingTimeInterval(-86400 + 9 * 3600), durationMinutes: 15, repeatRule: TaskRepeatRule(frequency: .daily, sourceRule: "RRULE:FREQ=DAILY"))))
        store.planner.anchor = day
        store.prepareCalendarIndex(force: true)
        for _ in 0..<200 where store.planner.preparingCalendar { try await Task.sleep(nanoseconds: 10_000_000) }
        let occurrence = try XCTUnwrap(store.calendarTasks(on: day).first)
        let nextID = try XCTUnwrap(store.calendarTasks(on: tomorrow).first?.id)
        store.setManagedTaskCompleted(occurrence.id, completed: true)
        for _ in 0..<200 where store.planner.preparingCalendar { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(store.calendarTasks(on: day).map(\.id), [occurrence.id])
        XCTAssertEqual(store.calendarTasks(on: day).first?.status, .completed)
        XCTAssertEqual(store.calendarTasks(on: tomorrow).map(\.id), [nextID])
        XCTAssertEqual(store.calendarTasks(on: tomorrow).first?.status, .active)
        XCTAssertEqual(store.task(id: rootID)?.status, .active)
        store.setManagedTaskCompleted(occurrence.id, completed: false)
        for _ in 0..<200 where store.planner.preparingCalendar { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(store.calendarTasks(on: day).first?.status, .active)
        XCTAssertEqual(store.calendarTasks(on: day).count, 1)
        store.flushPendingWrites()
    }

    @MainActor func testSkippingRecurringOccurrenceKeepsCardAndFutureDays() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "hidigFocus.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        let store = AppStore(repository: repository, startServices: false, plannerDefaults: defaults)
        let calendar = PlannerCalendar.current
        let day = calendar.startOfDay(for: Date())
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        let thirdDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: day))
        let rootID = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Прогулка", startDate: day.addingTimeInterval(21 * 3600), durationMinutes: 15, repeatRule: TaskRepeatRule(frequency: .daily, sourceRule: "RRULE:FREQ=DAILY"))))
        store.planner.anchor = day
        store.prepareCalendarIndex(force: true)
        for _ in 0..<200 where store.planner.preparingCalendar { try await Task.sleep(nanoseconds: 10_000_000) }
        store.setManagedTaskWontDo(rootID, skipped: true)
        for _ in 0..<200 where store.planner.preparingCalendar { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(store.task(id: rootID)?.status, .active)
        XCTAssertEqual(store.calendarTasks(on: day).map(\.status), [.wontDo])
        XCTAssertEqual(store.calendarTasks(on: tomorrow).map(\.status), [.active])

        let secondID = try XCTUnwrap(store.calendarTasks(on: tomorrow).first?.id)
        store.setManagedTaskWontDo(secondID, skipped: true)
        for _ in 0..<200 where store.planner.preparingCalendar { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(store.calendarTasks(on: tomorrow).map(\.id), [secondID])
        XCTAssertEqual(store.calendarTasks(on: tomorrow).map(\.status), [.wontDo])
        XCTAssertEqual(store.calendarTasks(on: thirdDay).map(\.status), [.active])

        store.setManagedTaskWontDo(secondID, skipped: false)
        for _ in 0..<200 where store.planner.preparingCalendar { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(store.calendarTasks(on: tomorrow).map(\.status), [.active])
        store.flushPendingWrites()
        XCTAssertEqual(try repository.load().managedTasks.first(where: { $0.id == secondID })?.status, .active)
    }

    @MainActor func testEditingCardKeepsRecurringBackgroundUntilReplacementIsReady() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "hidigFocus.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false, plannerDefaults: defaults)
        let calendar = PlannerCalendar.current
        let day = calendar.startOfDay(for: Date())
        let tomorrow = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: day))
        store.planner.anchor = day
        _ = store.createPlannerTask(ManagedTask(title: "Весь день", startDate: day, isAllDay: true, repeatRule: TaskRepeatRule(frequency: .daily)))
        _ = store.createPlannerTask(ManagedTask(title: "По времени", startDate: day.addingTimeInterval(3600), repeatRule: TaskRepeatRule(frequency: .daily)))
        let editedID = try XCTUnwrap(store.createPlannerTask(ManagedTask(title: "Карточка", startDate: tomorrow)))
        for _ in 0..<200 where store.planner.preparingCalendar { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(store.planner.preparingCalendar)
        let before = Set(store.calendarTasks(on: tomorrow).map(\.id))
        XCTAssertEqual(before.count, 3)
        for title in ["К", "Ка", "Карточка исправлена"] {
            store.bulkEdit([editedID]) { $0.title = title }
            XCTAssertEqual(Set(store.calendarTasks(on: tomorrow).map(\.id)), before, "Saving must not expose a calendar without projected recurrences")
            XCTAssertEqual(store.calendarTasks(on: tomorrow).filter(\.isAllDay).count, 1)
        }
        for _ in 0..<200 where store.planner.preparingCalendar {
            XCTAssertEqual(Set(store.calendarTasks(on: tomorrow).map(\.id)), before)
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(store.planner.preparingCalendar)
        XCTAssertEqual(store.calendarTasks(on: tomorrow).first { $0.id == editedID }?.title, "Карточка исправлена")
        store.scheduleManagedTask(editedID, at: day)
        for _ in 0..<200 where store.planner.preparingCalendar { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(store.planner.preparingCalendar)
        XCTAssertFalse(store.calendarTasks(on: tomorrow).contains { $0.id == editedID })
        XCTAssertTrue(store.calendarTasks(on: day).contains { $0.id == editedID })
        store.flushPendingWrites()
    }

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

    @MainActor func testRemovingTaskListMovesTasksToInboxAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        let store = AppStore(repository: repository, startServices: false)
        store.addTaskList(named: "Проект")
        let listID = try XCTUnwrap(store.taskLists.first(where: { $0.name == "Проект" })?.id)
        let taskID = try XCTUnwrap(store.createPlannerTask(ManagedTask(listID: listID, title: "Задача")))
        store.taskSidebarSelection = .list(listID)

        store.removeTaskList(listID)

        XCTAssertNil(store.taskLists.first(where: { $0.id == listID }))
        XCTAssertEqual(store.task(id: taskID)?.listID, TaskList.inboxID)
        XCTAssertEqual(store.taskSidebarSelection, .inbox)
        XCTAssertTrue(store.task(id: taskID)?.changeHistory.first?.summary.contains("Входящие") == true)
        store.flushPendingWrites()
        let saved = try repository.load()
        XCTAssertNil(saved.taskLists.first(where: { $0.id == listID }))
        XCTAssertEqual(saved.managedTasks.first(where: { $0.id == taskID })?.listID, TaskList.inboxID)
    }

    @MainActor func testRemovingTaskFolderKeepsListsAndTasks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        let store = AppStore(repository: repository, startServices: false)
        store.addTaskFolder(named: "Личное")
        let folderID = try XCTUnwrap(store.taskFolders.first(where: { $0.name == "Личное" })?.id)
        store.addTaskList(named: "Режим", folderID: folderID)
        let listID = try XCTUnwrap(store.taskLists.first(where: { $0.name == "Режим" })?.id)
        let taskID = try XCTUnwrap(store.createPlannerTask(ManagedTask(listID: listID, title: "Задача")))

        store.removeTaskFolder(folderID)

        XCTAssertNil(store.taskFolders.first(where: { $0.id == folderID }))
        XCTAssertNil(store.taskLists.first(where: { $0.id == listID })?.folderID)
        XCTAssertEqual(store.task(id: taskID)?.listID, listID)
        store.flushPendingWrites()
        let saved = try repository.load()
        XCTAssertNil(saved.taskFolders.first(where: { $0.id == folderID }))
        XCTAssertNil(saved.taskLists.first(where: { $0.id == listID })?.folderID)
    }

    @MainActor func testInboxCannotBeRemoved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)

        store.removeTaskList(TaskList.inboxID)

        XCTAssertNotNil(store.taskLists.first(where: { $0.id == TaskList.inboxID }))
        store.flushPendingWrites()
    }

}
