import XCTest
@testable import hidigFocus

final class PlannerUpgradeTests: XCTestCase {
    func testCompletedHistoryIsVisibleByDefaultAndCanBeHidden() {
        var task = ManagedTask(title: "Старая выполненная задача")
        task.status = .completed
        var filter = PlannerFilter()
        XCTAssertTrue(filter.matches(task, search: ""))
        XCTAssertFalse(filter.isActive)
        filter.showCompleted = false
        XCTAssertFalse(filter.matches(task, search: ""))
        XCTAssertTrue(filter.isActive)
    }

    func testCompletedVisibilityMigrationPreservesOtherFiltersAndLaterChoice() throws {
        let suite = "CompletedVisibilityTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var old = PlannerFilter()
        old.showCompleted = false
        old.listIDs = [UUID()]
        old.showEvents = false
        defaults.set(try JSONEncoder().encode(old), forKey: "planner.filter")
        let workspace = PlannerWorkspace(defaults: defaults)
        XCTAssertTrue(workspace.filter.showCompleted)
        XCTAssertEqual(workspace.filter.listIDs, old.listIDs)
        XCTAssertFalse(workspace.filter.showEvents)
        workspace.filter.showCompleted = false
        XCTAssertFalse(PlannerWorkspace(defaults: defaults).filter.showCompleted)
    }

    func testCalendarRenderWindowKeepsCurrentAndPreviousPeriodVisible() {
        XCTAssertEqual(CalendarRenderWindow.days(offset: 0, dayWidth: 200, visibleDays: 4), -1...4)
        let previous = CalendarRenderWindow.days(offset: 800, dayWidth: 200, visibleDays: 4)
        for day in -4...3 { XCTAssertTrue(previous.contains(day)) }
        let next = CalendarRenderWindow.days(offset: -800, dayWidth: 200, visibleDays: 4)
        for day in 0...7 { XCTAssertTrue(next.contains(day)) }
    }

    func testExactTimeInputPreservesMinuteAndRejectsInvalidValues() {
        XCTAssertEqual(PlannerTimeInput.minutes("09:17"), 557)
        XCTAssertEqual(PlannerTimeInput.minutes("23:59"), 1439)
        XCTAssertEqual(PlannerTimeInput.minutes(" 0:00 "), 0)
        for invalid in ["24:00", "12:60", "9", ":30", "-1:00", "09:17 AM", "a:20"] { XCTAssertNil(PlannerTimeInput.minutes(invalid)) }
    }

    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func testSchedulingPreservesIndependentDeadline() {
        var state = PersistedAppState()
        let deadline = base.addingTimeInterval(86_400)
        let task = ManagedTask(title: "Срок", startDate: base, dueDate: deadline)
        state.managedTasks = [task]
        TaskEngine.schedule(task.id, at: base.addingTimeInterval(3600), durationMinutes: 90, in: &state)
        XCTAssertEqual(state.managedTasks[0].dueDate, deadline)
        XCTAssertEqual(state.managedTasks[0].calendarEndDate, base.addingTimeInterval(9000))
        TaskEngine.schedule(task.id, at: nil, in: &state)
        XCTAssertNil(state.managedTasks[0].startDate)
        XCTAssertNil(state.managedTasks[0].plannedEndDate)
        XCTAssertEqual(state.managedTasks[0].dueDate, deadline)
    }
    func testFilterSearchRespectsListTagsStatusAndSource() {
        let a = UUID(), b = UUID()
        let task = ManagedTask(listID: a, title: "Задача", notes: "контекст", tags: ["метка"])
        var filter = PlannerFilter(); filter.listIDs = [a]
        XCTAssertTrue(filter.matches(task, search: "метка"))
        XCTAssertTrue(filter.matches(task, search: "контекст"))
        filter.listIDs = [b]; XCTAssertFalse(filter.matches(task, search: "метка"))
        filter.listIDs = []; filter.showLocal = false; XCTAssertFalse(filter.matches(task, search: ""))
        var imported = task; imported.sourceID = "remote"
        XCTAssertTrue(filter.matches(imported, search: ""))
        filter.showCompleted = false
        imported.status = .completed; XCTAssertFalse(filter.matches(imported, search: ""))
        filter.showCompleted = true; XCTAssertTrue(filter.matches(imported, search: ""))
        imported.status = .trashed; XCTAssertFalse(filter.matches(imported, search: ""))
    }
    func testSortIsDeterministic() {
        let a = ManagedTask(title: "B", priority: .high, sortOrder: 2)
        let b = ManagedTask(title: "A", priority: .none, sortOrder: 1)
        let filter = PlannerFilter()
        XCTAssertEqual(filter.sorted([a,b], by: .manual).map(\.id), [b.id,a.id])
        XCTAssertEqual(filter.sorted([a,b], by: .priority).map(\.id), [a.id,b.id])
        XCTAssertEqual(filter.sorted([a,b], by: .title).map(\.id), [b.id,a.id])
    }
    func testAxisLockDoesNotChangeDirectionDuringGesture() {
        var lock = CalendarAxisLock()
        XCTAssertTrue(lock.accept(dx: 10, dy: 1))
        XCTAssertTrue(lock.accept(dx: 0, dy: 100))
        lock.reset()
        XCTAssertFalse(lock.accept(dx: 1, dy: 10))
        XCTAssertFalse(lock.accept(dx: 100, dy: 0))
    }
    func testFutureRepeatsAreStableAndNotPersisted() throws {
        let root = ManagedTask(title: "Каждый день", startDate: base, durationMinutes: 45, repeatRule: TaskRepeatRule(frequency: .daily))
        let end = base.addingTimeInterval(4 * 86_400)
        let first = RecurrenceProjection.tasks([root], from: base, to: end)
        let second = RecurrenceProjection.tasks([root], from: base, to: end)
        XCTAssertEqual(first.map(\.id), second.map(\.id))
        XCTAssertEqual(first.count, 4)
        XCTAssertEqual(first[1].seriesRootID, root.id)
        XCTAssertNil(first[1].repeatRule)
        XCTAssertEqual(first[1].calendarEndDate?.timeIntervalSince(try XCTUnwrap(first[1].startDate)), 45 * 60)
    }
    func testUnavailableImportedSeriesPreservesHistoryWithoutPhantomOccurrences() {
        let root = ManagedTask(sourceID: "old-parent", sourceName: "TickTick", title: "Prep to aspiranture", startDate: base, sourceUnavailable: true, repeatRule: TaskRepeatRule(frequency: .daily))
        let history = ManagedTask(title: "Completed history", startDate: base, status: .completed)
        let stored = RecurrenceProjection.tasks([root, history], from: base, to: base.addingTimeInterval(86400))
        XCTAssertEqual(Set(stored.map(\.id)), Set([root.id, history.id]))
        XCTAssertTrue(RecurrenceProjection.tasks([root, history], from: base.addingTimeInterval(30 * 86400), to: base.addingTimeInterval(34 * 86400)).isEmpty)
    }
    func testHierarchyContextDoesNotActivateSeriesAndRegularImportRestoresIt() {
        var state = PersistedAppState()
        var record = TickTickImportRecord(sourceID: "parent", projectSourceID: "list", title: "Parent", isHierarchyContext: true, startDate: base, repeatRule: TaskRepeatRule(frequency: .daily))
        _ = TaskEngine.importTickTick(folders: [], lists: [], records: [record], into: &state)
        let originalID = state.managedTasks[0].id
        XCTAssertEqual(state.managedTasks[0].sourceUnavailable, true)
        XCTAssertTrue(RecurrenceProjection.tasks(state.managedTasks, from: base.addingTimeInterval(86400), to: base.addingTimeInterval(3 * 86400)).isEmpty)
        record.isHierarchyContext = nil
        _ = TaskEngine.importTickTick(folders: [], lists: [], records: [record], into: &state)
        XCTAssertEqual(state.managedTasks[0].id, originalID)
        XCTAssertEqual(state.managedTasks[0].sourceUnavailable, false)
        XCTAssertEqual(RecurrenceProjection.tasks(state.managedTasks, from: base.addingTimeInterval(86400), to: base.addingTimeInterval(3 * 86400)).count, 2)
    }
    func testSavedAndExcludedOccurrencesDoNotDuplicate() throws {
        var root = ManagedTask(title: "Повтор", startDate: base, repeatRule: TaskRepeatRule(frequency: .daily))
        let projected = RecurrenceProjection.tasks([root], from: base, to: base.addingTimeInterval(3 * 86_400))
        var saved = try XCTUnwrap(projected.dropFirst().first); saved.status = .completed
        root.excludedOccurrences = [saved.occurrenceDate!]
        let result = RecurrenceProjection.tasks([root,saved], from: base, to: base.addingTimeInterval(3 * 86_400))
        XCTAssertEqual(result.filter { $0.occurrenceDate == saved.occurrenceDate }.count, 1)
        XCTAssertEqual(result.first { $0.id == saved.id }?.status, .completed)
    }
    func testImportedUnknownRulesAreNotApproximated() {
        let task = ManagedTask(title: "Импорт", startDate: base, repeatRule: TaskRepeatRule(frequency: .daily, sourceRule: "FREQ=UNKNOWN"))
        XCTAssertEqual(RecurrenceProjection.tasks([task], from: base, to: base.addingTimeInterval(10 * 86_400)).count, 1)
    }
    func testCompletionSuccessorDoesNotDuplicateProjection() {
        var state = PersistedAppState()
        let task = ManagedTask(title: "Повтор", startDate: base, repeatRule: TaskRepeatRule(frequency: .daily))
        state.managedTasks = [task]
        TaskEngine.setCompleted(task.id, completed: true, in: &state)
        let result = RecurrenceProjection.tasks(state.managedTasks, from: base, to: base.addingTimeInterval(4 * 86_400))
        XCTAssertEqual(result.count, 4)
        XCTAssertEqual(Set(result.compactMap(\.startDate)).count, 4)
    }
    func testHistoryPreservesConcurrentUntouchedFields() {
        let original = ManagedTask(title: "До", description: "Описание", startDate: base)
        var after = original; after.title = "После"
        var concurrent = after; concurrent.description = "Новый импорт"
        let entry = TaskHistoryEntry(before: [original], after: [after])
        let undone = entry.applying(to: [concurrent], reverse: true)
        XCTAssertEqual(undone.first?.title, "До")
        XCTAssertEqual(undone.first?.description, "Новый импорт")
        let redone = entry.applying(to: undone, reverse: false)
        XCTAssertEqual(redone.first?.title, "После")
        XCTAssertEqual(redone.first?.description, "Новый импорт")
    }
    func testCascadeTrashRestorePreservesHierarchy() {
        let parent = ManagedTask(title: "Родитель")
        let child = ManagedTask(parentTaskID: parent.id, title: "Подзадача")
        let nested = ManagedTask(parentTaskID: child.id, title: "Вложенная")
        var state = PersistedAppState(); state.managedTasks = [parent,child,nested]
        TaskEngine.trash(parent.id, in: &state, now: base)
        XCTAssertTrue(state.managedTasks.allSatisfy { $0.status == .trashed })
        TaskEngine.restoreFromTrash(parent.id, in: &state)
        XCTAssertTrue(state.managedTasks.allSatisfy { $0.status == .active })
        XCTAssertEqual(state.managedTasks[2].parentTaskID, child.id)
    }
    func testReminderPlanReplansAndCancels() {
        var task = ManagedTask(title: "Напомнить", startDate: base, reminders: [TaskReminder(relativeMinutes: 15)])
        XCTAssertEqual(ReminderPlan.requests(tasks: [task], now: base.addingTimeInterval(-3600)).first?.date, base.addingTimeInterval(-900))
        task.startDate = base.addingTimeInterval(3600)
        XCTAssertEqual(ReminderPlan.requests(tasks: [task], now: base).first?.date, base.addingTimeInterval(2700))
        task.status = .completed
        XCTAssertTrue(ReminderPlan.requests(tasks: [task], now: base).isEmpty)
    }
    func testExactReminderWorksWithoutScheduledStart() {
        let task = ManagedTask(title: "Без даты", reminders: [TaskReminder(date: base)])
        XCTAssertEqual(ReminderPlan.requests(tasks: [task], now: base.addingTimeInterval(-1)).count, 1)
    }
    func testQuickInputPreviewsRecognizedDateAndTime() {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let parsed = QuickTaskInput.parse("Позвонить завтра 14:30", now: base, calendar: cal)
        XCTAssertEqual(parsed.title, "Позвонить")
        XCTAssertEqual(cal.component(.hour, from: parsed.date!), 14)
        XCTAssertEqual(cal.component(.minute, from: parsed.date!), 30)
        XCTAssertEqual(cal.startOfDay(for: parsed.date!), cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: base)))
        XCTAssertEqual(QuickTaskInput.parse("Работа 25:30", now: base).title, "Работа 25:30")
    }
    func testSameETagDoesNotHideLocalEdits() {
        let task = ManagedTask(title: "Изменение", modifiedAt: base.addingTimeInterval(1), googleEventID: "e", googleETag: "v1", lastSyncedAt: base)
        let event = GoogleCalendarEventSnapshot(id: "e", calendarID: "c", etag: "v1", title: "Старое", description: "", startDate: base, endDate: base.addingTimeInterval(3600), isAllDay: false, timeZoneID: "Europe/Moscow", updatedAt: base)
        XCTAssertEqual(GoogleSyncEngine.decision(for: task, remote: event), .updateRemote)
    }
    func testSourceDeletionOnlyMarksLocalCopy() {
        var state = PersistedAppState()
        let task = ManagedTask(sourceID: "removed", sourceName: "TickTick", title: "Сохранить")
        state.managedTasks = [task]
        _ = TaskEngine.importTickTick(folders: [], lists: [], records: [], into: &state, completeSnapshot: true)
        XCTAssertEqual(state.managedTasks[0].status, .active)
        XCTAssertEqual(state.managedTasks[0].sourceUnavailable, true)
    }
    func testSerialWriterRejectsStaleSnapshotsAndFlushesLast() {
        let lock = NSLock(); var saved: [String] = []
        let writer = SaveCoordinator { state in lock.lock(); saved.append(state.managedTasks[0].title); lock.unlock() }
        for (revision,title) in [(UInt64(2),"Новая"),(1,"Старая"),(3,"Последняя")] {
            var state = PersistedAppState(); state.managedTasks = [ManagedTask(title: title)]
            writer.enqueue(state, revision: revision) { _,_ in }
        }
        writer.flush()
        XCTAssertEqual(saved, ["Новая","Последняя"])
    }
    func testWriterFailureDoesNotPreventRetry() {
        enum Failure: Error { case disk }
        var fail = true; var saved = false
        let writer = SaveCoordinator { _ in if fail { fail = false; throw Failure.disk }; saved = true }
        writer.enqueue(PersistedAppState(), revision: 1) { _,_ in }
        writer.flush()
        writer.enqueue(PersistedAppState(), revision: 1) { _,_ in }
        writer.flush(); XCTAssertTrue(saved)
    }
    func testMigrationCreatesBackupAndPreservesDeadlineAndNestedSubtasks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var state = PersistedAppState(); state.schemaVersion = 2
        let root = ManagedTask(title: "Старая", startDate: base, dueDate: base.addingTimeInterval(7200), subtasks: [ManagedTask(title: "Вложенная")])
        state.managedTasks = [root]
        let repo = AppStateRepository(applicationSupportDirectory: directory); try repo.save(state)
        let migrated = try repo.load()
        XCTAssertEqual(migrated.schemaVersion, 3)
        XCTAssertEqual(migrated.managedTasks.count, 2)
        XCTAssertEqual(migrated.managedTasks[0].dueDate, root.dueDate)
        XCTAssertEqual(migrated.managedTasks[1].parentTaskID, root.id)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: directory.path).contains { $0.contains("before-schema-3") })
        XCTAssertEqual(try repo.load().managedTasks.count, 2)
    }
    func testProjectionAcrossDSTUsesCalendarDays() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = try XCTUnwrap(cal.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 9)))
        let task = ManagedTask(title: "DST", startDate: start, timeZoneID: "Europe/Berlin", repeatRule: TaskRepeatRule(frequency: .daily))
        let values = RecurrenceProjection.tasks([task], from: start, to: start.addingTimeInterval(3 * 86400))
        XCTAssertTrue(values.allSatisfy { cal.component(.hour, from: $0.startDate!) == 9 })
    }
}
