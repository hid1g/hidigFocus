import XCTest
@testable import hidigFocus

final class TaskScheduleSelectionTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return value
    }
    private var start: Date { calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 16, minute: 45))! }
    func testNewTaskDefaultsToDayWithoutInventingTime() {
        var task = ManagedTask(title: "Без времени")
        var selection = TaskScheduleSelection(task: task, now: start)
        XCTAssertFalse(selection.hasTime)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        selection.timeZoneID = calendar.timeZone.identifier
        selection.selectDay(tomorrow)
        selection.apply(to: &task)
        XCTAssertEqual(task.startDate, calendar.startOfDay(for: tomorrow))
        XCTAssertTrue(task.isAllDay)
        XCTAssertNil(task.plannedEndDate)
    }
    func testChangingDayKeepsExactTimeDurationAndDeadline() {
        let deadline = start.addingTimeInterval(86400 * 10)
        var task = ManagedTask(title: "Перенести", startDate: start, dueDate: deadline, durationMinutes: 45, timeZoneID: calendar.timeZone.identifier)
        var selection = TaskScheduleSelection(task: task)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!
        selection.selectDay(tomorrow)
        selection.apply(to: &task)
        XCTAssertEqual(task.startDate, tomorrow)
        XCTAssertEqual(task.durationMinutes, 45)
        XCTAssertEqual(task.plannedEndDate, tomorrow.addingTimeInterval(45 * 60))
        XCTAssertEqual(task.dueDate, deadline)
    }
    func testRemovingTimePreservesDurationForAddingTimeAgain() {
        var task = ManagedTask(title: "Убрать время", startDate: start, durationMinutes: 75, timeZoneID: calendar.timeZone.identifier)
        var selection = TaskScheduleSelection(task: task)
        selection.hasTime = false
        selection.apply(to: &task)
        XCTAssertTrue(task.isAllDay)
        XCTAssertNil(task.plannedEndDate)
        XCTAssertEqual(task.durationMinutes, 75)
        var timed = TaskScheduleSelection(task: task)
        timed.hasTime = true; timed.start = start
        timed.apply(to: &task)
        XCTAssertEqual(task.plannedEndDate, start.addingTimeInterval(75 * 60))
    }
    func testExplicitDurationRangeCrossesMidnightWithoutResettingRepeat() {
        let rule = TaskRepeatRule(frequency: .weekly, weekdays: [2, 4])
        var task = ManagedTask(title: "Диапазон", startDate: start, repeatRule: rule)
        var selection = TaskScheduleSelection(task: task)
        selection.durationMode = true
        selection.end = start.addingTimeInterval(9 * 3600)
        selection.apply(to: &task)
        XCTAssertEqual(task.durationMinutes, 540)
        XCTAssertEqual(task.plannedEndDate, selection.end)
        XCTAssertEqual(task.repeatRule, rule)
    }
}
