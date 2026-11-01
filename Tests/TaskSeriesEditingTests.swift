import XCTest
@testable import hidigFocus

final class TaskSeriesEditingTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return value
    }
    private func date(_ day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func series(weekdays: Bool = false, imported: Bool = false) -> ManagedTask {
        ManagedTask(sourceID: imported ? "fixture" : nil, sourceName: imported ? "TickTick" : nil,
                    title: weekdays ? "Спланировать день" : "morning routine", startDate: date(26),
                    durationMinutes: 30, timeZoneID: "Europe/Moscow",
                    repeatRule: TaskRepeatRule(frequency: weekdays ? .weekly : .daily,
                        weekdays: weekdays ? [2,3,4,5,6] : [], sourceRule: imported ? "RRULE:FREQ=DAILY" : nil))
    }
    private func projected(_ state: PersistedAppState) -> [ManagedTask] {
        RecurrenceProjection.tasks(state.managedTasks, from: date(25), to: date(31).addingTimeInterval(4 * 86400))
            .sorted { $0.startDate! < $1.startDate! }
    }
    private func occurrence(_ day: Int, in state: PersistedAppState) throws -> ManagedTask {
        try XCTUnwrap(projected(state).first { calendar.isDate($0.startDate!, inSameDayAs: date(day)) })
    }

    private func assertProjection(_ actual: PersistedAppState, equals expected: PersistedAppState, file: StaticString = #filePath, line: UInt = #line) {
        let left = projected(actual), right = projected(expected)
        XCTAssertEqual(left.map(\.id), right.map(\.id), file: file, line: line)
        XCTAssertEqual(left.map(\.title), right.map(\.title), file: file, line: line)
        XCTAssertEqual(left.map(\.startDate), right.map(\.startDate), file: file, line: line)
        XCTAssertEqual(left.map(\.durationMinutes), right.map(\.durationMinutes), file: file, line: line)
        XCTAssertEqual(left.map(\.status), right.map(\.status), file: file, line: line)
        XCTAssertEqual(left.map(\.occurrenceDate), right.map(\.occurrenceDate), file: file, line: line)
    }

    func testDailyFollowingChanges28Through30AndKeepsEarlierDays() throws {
        let root = series(); var state = PersistedAppState(); state.managedTasks = [root]
        let selected = try occurrence(28, in: state); var draft = selected; draft.durationMinutes = 15
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .following, replaceExceptions: false, in: &state)
        XCTAssertEqual(try occurrence(27, in: state).durationMinutes, 30)
        for day in 28...30 { XCTAssertEqual(try occurrence(day, in: state).durationMinutes, 15) }
        XCTAssertEqual(state.managedTasks.count, 1, "Future projections must not create persisted copies")
        XCTAssertEqual(try occurrence(28, in: state).id, selected.id)
    }

    func testWeekdayFollowingRenameDoesNotCreateWeekendTasks() throws {
        var state = PersistedAppState(); state.managedTasks = [series(weekdays: true)]
        let selected = try occurrence(28, in: state); var draft = selected
        draft.title = "Спланировать день и просмотреть анализ рабочий"
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .following, replaceExceptions: false, in: &state)
        XCTAssertEqual(try occurrence(27, in: state).title, "Спланировать день")
        for day in 28...30 { XCTAssertEqual(try occurrence(day, in: state).title, draft.title) }
        XCTAssertTrue(projected(state).allSatisfy { !calendar.isDateInWeekend($0.startDate!) })
    }

    func testWholeSeriesKeepsCompletedSkippedAndIndividualEdits() throws {
        let root = series(); var state = PersistedAppState(); state.managedTasks = [root]
        var completed = try occurrence(27, in: state); completed.status = .completed; completed.completedAt = date(27)
        completed.changeHistory = [TaskChange(summary: "История")]
        var exception = try occurrence(29, in: state); exception.title = "Индивидуально"; exception.durationMinutes = 45
        var skipped = try occurrence(30, in: state); skipped.status = .wontDo
        state.managedTasks += [completed, exception, skipped]
        let selected = try occurrence(28, in: state); var draft = selected; draft.title = "Общее"; draft.durationMinutes = 15
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .series, replaceExceptions: false, in: &state)
        XCTAssertEqual(try occurrence(26, in: state).title, "Общее")
        XCTAssertEqual(try occurrence(28, in: state).durationMinutes, 15)
        XCTAssertEqual(state.managedTasks.first { $0.id == completed.id }, completed)
        XCTAssertEqual(state.managedTasks.first { $0.id == skipped.id }, skipped)
        XCTAssertEqual(try occurrence(29, in: state), exception)
        XCTAssertEqual(projected(state).filter { calendar.isDate($0.startDate!, inSameDayAs: date(29)) }.count, 1)
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .series, replaceExceptions: true, in: &state)
        XCTAssertEqual(try occurrence(29, in: state).title, "Общее")
        XCTAssertEqual(try occurrence(29, in: state).durationMinutes, 15)
        XCTAssertEqual(state.managedTasks.first { $0.id == completed.id }, completed)
    }

    func testWholeSeriesPreservesCompletedRootHistory() throws {
        var root = series(); root.status = .completed; root.completedAt = date(26)
        root.changeHistory = [TaskChange(summary: "Выполнено")]
        var state = PersistedAppState(); state.managedTasks = [root]
        let selected = try occurrence(28, in: state); var draft = selected; draft.title = "Новое"
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .series, replaceExceptions: true, in: &state)
        let history = try occurrence(26, in: state)
        XCTAssertEqual(history.title, root.title)
        XCTAssertEqual(history.status, .completed)
        XCTAssertEqual(history.completedAt, root.completedAt)
        XCTAssertEqual(history.id, root.id)
        XCTAssertEqual(try occurrence(27, in: state).title, "Новое")
    }

    func testFutureDateTimeMoveKeepsExceptionIdentityAndIndependentDeadline() throws {
        var root = series(); root.dueDate = date(26, hour: 18); var state = PersistedAppState(); state.managedTasks = [root]
        var exception = try occurrence(29, in: state); exception.startDate = date(29, hour: 14)
        exception.title = "Своя правка"; state.managedTasks.append(exception)
        let selected = try occurrence(28, in: state)
        var draft = selected; draft.startDate = date(28, hour: 11); draft.durationMinutes = 15
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .following, replaceExceptions: false, in: &state)
        XCTAssertEqual(try occurrence(28, in: state).startDate, date(28, hour: 11))
        XCTAssertEqual(try occurrence(30, in: state).startDate, date(30, hour: 11))
        XCTAssertEqual(try occurrence(30, in: state).durationMinutes, 15)
        XCTAssertEqual(try occurrence(29, in: state), exception)
        XCTAssertEqual(try occurrence(28, in: state).id, selected.id)
        XCTAssertEqual(try occurrence(27, in: state).startDate, date(27))
        XCTAssertEqual(try occurrence(28, in: state).dueDate, date(28, hour: 18))
        XCTAssertEqual(try occurrence(30, in: state).dueDate, date(30, hour: 18))
    }

    func testRuleChangeToWeekdaysAndThenStopFollowing() throws {
        var state = PersistedAppState(); state.managedTasks = [series()]
        var selected = try occurrence(28, in: state); selected.repeatRule = series().repeatRule
        var draft = selected; draft.repeatRule = TaskRepeatRule(frequency: .weekly, weekdays: [2,3,4,5,6])
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .following, replaceExceptions: false, in: &state)
        XCTAssertTrue(projected(state).allSatisfy { !calendar.isDateInWeekend($0.startDate!) })
        selected = try occurrence(29, in: state); selected.repeatRule = draft.repeatRule
        draft = selected; draft.repeatRule = nil
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .following, replaceExceptions: false, in: &state)
        XCTAssertEqual(projected(state).map(\.startDate), [date(26),date(27),date(28),date(29)])
    }

    func testMultipleFutureEditsAndWholeSeriesPatchKeepUnchangedFields() throws {
        var state = PersistedAppState(); state.managedTasks = [series()]
        var selected = try occurrence(28, in: state); var draft = selected; draft.durationMinutes = 15
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .following, replaceExceptions: false, in: &state)
        selected = try occurrence(30, in: state); draft = selected; draft.title = "Будущее"
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .following, replaceExceptions: false, in: &state)
        selected = try occurrence(29, in: state); draft = selected; draft.title = "Вся серия"
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .series, replaceExceptions: false, in: &state)
        XCTAssertTrue(projected(state).allSatisfy { $0.title == draft.title })
        XCTAssertEqual(try occurrence(26, in: state).durationMinutes, 30)
        XCTAssertEqual(try occurrence(30, in: state).durationMinutes, 15)
    }

    func testLocalSeriesAndExceptionSurviveChangedTickTickImportAndReload() throws {
        var state = PersistedAppState()
        var record = TickTickImportRecord(sourceID: "fixture", projectSourceID: "list", title: "Импорт",
            startDate: date(26), repeatRule: TaskRepeatRule(frequency: .daily, sourceRule: "RRULE:FREQ=DAILY"), durationMinutes: 30)
        _ = TaskEngine.importTickTick(folders: [], lists: [], records: [record], into: &state)
        let selected = try occurrence(28, in: state); var draft = selected; draft.durationMinutes = 15
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .following, replaceExceptions: false, in: &state)
        var exception = try occurrence(29, in: state); exception.title = "Локально"; state.managedTasks.append(exception)
        record.title = "Внешнее изменение"; record.durationMinutes = 60; record.startDate = date(27, hour: 10)
        _ = TaskEngine.importTickTick(folders: [], lists: [], records: [record], into: &state, completeSnapshot: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        try repository.save(state)
        let reloaded = try repository.load()
        assertProjection(reloaded, equals: state)
        XCTAssertEqual(try occurrence(28, in: reloaded).durationMinutes, 15)
        XCTAssertEqual(try occurrence(29, in: reloaded).title, "Локально")
        XCTAssertEqual(try occurrence(30, in: reloaded).durationMinutes, 15)
    }

    @MainActor func testStoreSingleEditAfterSeriesEditCompletionUndoAndRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        let store = AppStore(repository: repository, startServices: false)
        store.planner.anchor = date(26)
        let id = try XCTUnwrap(store.createPlannerTask(series()))
        let before = try XCTUnwrap(store.task(id: id)); var draft = before; draft.durationMinutes = 15
        store.updateSeriesEdits(from: before, to: draft, scope: .series)
        XCTAssertEqual(store.task(id: id)?.durationMinutes, 15)
        store.undoTaskAction(); XCTAssertEqual(store.task(id: id)?.durationMinutes, 30)
        store.redoTaskAction(); XCTAssertEqual(store.task(id: id)?.durationMinutes, 15)
        let root = try XCTUnwrap(store.task(id: id)); draft = root; draft.title = "Один"
        store.updateManagedTaskEdits(from: root, to: draft)
        XCTAssertEqual(store.resolvedTask(id: id)?.title, "Один")
        XCTAssertEqual(try occurrence(27, in: store.state).title, "morning routine")
        store.flushPendingWrites()
        assertProjection(try repository.load(), equals: store.state)
        let reloaded = AppStore(repository: repository, startServices: false)
        reloaded.prepareCalendarIndex(around: date(28), force: true)
        for _ in 0..<200 where reloaded.planner.preparingCalendar { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(reloaded.calendarTasks(on: date(28)).first?.durationMinutes, 15)
        reloaded.flushPendingWrites()
    }
    func testWeekdaySeriesSupportsSingleAndWholeSeriesChanges() throws {
        var state = PersistedAppState(); state.managedTasks = [series(weekdays: true)]
        let selected = try occurrence(28, in: state)
        var exception = selected; exception.title = "Один день"; state.managedTasks.append(exception)
        XCTAssertEqual(try occurrence(29, in: state).title, "Спланировать день")
        var draft = selected; draft.title = "Общее название"
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .series, replaceExceptions: false, in: &state)
        // The explicitly opened instance changes even when other exceptions are preserved.
        XCTAssertEqual(try occurrence(28, in: state).title, draft.title)
        XCTAssertEqual(try occurrence(26, in: state).title, draft.title)
        XCTAssertEqual(try occurrence(30, in: state).title, draft.title)
    }

    func testMovedOccurrenceKeepsDeletedSlotAndCompletionAfterSync() throws {
        let root = series(); var state = PersistedAppState(); state.managedTasks = [root]
        var deleted = try occurrence(29, in: state); deleted.status = .trashed; deleted.deletedAt = date(27)
        state.managedTasks.append(deleted)
        let selected = try occurrence(28, in: state); var draft = selected; draft.startDate = date(28, hour: 11)
        TaskSeriesEditing.apply(from: selected, to: draft, scope: .following, replaceExceptions: true, in: &state)
        XCTAssertEqual(state.managedTasks.first { $0.id == deleted.id }, deleted)
        XCTAssertEqual(projected(state).filter { calendar.isDate($0.startDate!, inSameDayAs: date(29)) }.count, 1)
        XCTAssertEqual(try occurrence(29, in: state).status, .trashed)
        let index = PlannerCalendarIndex()
        index.replaceTasks(state.managedTasks)
        XCTAssertTrue(index.day(date(29)).isEmpty)
        XCTAssertEqual(index.day(date(30)).first?.startDate, date(30, hour: 11))
    }

    @MainActor func testCompletingRevisedRootDoesNotRestartOldRecurrence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory), startServices: false)
        let id = try XCTUnwrap(store.createPlannerTask(series()))
        let original = try XCTUnwrap(store.task(id: id)); var draft = original; draft.durationMinutes = 15
        store.updateSeriesEdits(from: original, to: draft)
        store.setManagedTaskCompleted(id, completed: true)
        XCTAssertEqual(store.resolvedTask(id: id)?.status, .completed)
        XCTAssertEqual(store.resolvedTask(id: id)?.durationMinutes, 15)
        XCTAssertEqual(try occurrence(27, in: store.state).durationMinutes, 15)
        XCTAssertEqual(try occurrence(27, in: store.state).status, .active)
        XCTAssertEqual(store.state.managedTasks.count, 2)
        store.flushPendingWrites()
    }

    func testCalendarDayShiftKeepsWallClockAcrossDSTAndIDs() throws {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 9))!
        let nextDay = cal.date(byAdding: .day, value: 1, to: start)!
        let root = ManagedTask(title: "DST", startDate: start, timeZoneID: "Europe/Berlin", repeatRule: TaskRepeatRule(frequency: .daily))
        var state = PersistedAppState(); state.managedTasks = [root]
        var draft = root; draft.startDate = nextDay
        TaskSeriesEditing.apply(from: root, to: draft, scope: .series, replaceExceptions: false, in: &state)
        let values = RecurrenceProjection.tasks(state.managedTasks, from: start, to: start.addingTimeInterval(4 * 86400))
        XCTAssertEqual(values.count, 3)
        XCTAssertTrue(values.allSatisfy { cal.component(.hour, from: $0.startDate!) == 9 })
        XCTAssertEqual(values.first?.id, root.id)
        XCTAssertEqual(values.first?.occurrenceDate, start)
    }

    func testExportIsolatedUIFixtureWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["HIDIGFOCUS_SERIES_QA_SEED"] else { throw XCTSkip("UI fixture export is opt-in") }
        guard path.hasPrefix("/tmp/hidigFocus-series-qa-") else { return XCTFail("Fixture export must use its isolated temporary directory") }
        var state = PersistedAppState(); state.protectionEnabled = false
        var daily = series(); daily.title = "TEST morning routine"
        var weekdays = series(weekdays: true); weekdays.title = "TEST Спланировать день"; weekdays.startDate = date(26, hour: 10)
        var allDay = series(); allDay.title = "TEST На весь день"; allDay.isAllDay = true
        state.managedTasks = [daily, weekdays, allDay]
        try AppStateRepository(applicationSupportDirectory: URL(fileURLWithPath: path)).save(state)
    }

}
