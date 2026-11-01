import XCTest
@testable import hidigFocus

final class CalendarAllDayDragTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Moscow")!
        return value
    }
    private var anchor: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 27, hour: 9))!
    }
    private let region = CalendarAllDayDropRegion(bounds: CGRect(x: 100, y: 200, width: 800, height: 120))

    func testEmptySiblingPreferenceDoesNotEraseDropBounds() {
        var value = CGRect.zero
        CalendarAllDayBounds.reduce(value: &value) { region.bounds }
        CalendarAllDayBounds.reduce(value: &value) { .zero }
        XCTAssertEqual(value, region.bounds)
    }

    func testAllDayDropUsesPointerColumnAndMidnight() throws {
        let first = try XCTUnwrap(region.day(at: CGPoint(x: 110, y: 250), anchor: anchor, dayWidth: 200, panOffset: 0, calendar: calendar))
        let third = try XCTUnwrap(region.day(at: CGPoint(x: 550, y: 250), anchor: anchor, dayWidth: 200, panOffset: 0, calendar: calendar))
        XCTAssertEqual(first, calendar.startOfDay(for: anchor))
        XCTAssertEqual(third, calendar.date(byAdding: .day, value: 2, to: first))
    }

    func testRegionRejectsTimelineSidebarAndHiddenColumns() {
        for point in [CGPoint(x: 90, y: 250), CGPoint(x: 950, y: 250), CGPoint(x: 250, y: 330), CGPoint(x: 250, y: 190)] {
            XCTAssertNil(region.day(at: point, anchor: anchor, dayWidth: 200, panOffset: 0, calendar: calendar))
        }
    }

    func testDropTracksShiftedCalendarStrip() {
        let point = CGPoint(x: 150, y: 250)
        let next = region.day(at: point, anchor: anchor, dayWidth: 200, panOffset: -200, calendar: calendar)
        let previous = region.day(at: point, anchor: anchor, dayWidth: 200, panOffset: 200, calendar: calendar)
        let day = calendar.startOfDay(for: anchor)
        XCTAssertEqual(next, calendar.date(byAdding: .day, value: 1, to: day))
        XCTAssertEqual(previous, calendar.date(byAdding: .day, value: -1, to: day))
    }

    func testTimedAllDayRoundTripPreservesDurationAndDeadline() throws {
        var state = PersistedAppState()
        let deadline = anchor.addingTimeInterval(86400 * 7)
        let task = ManagedTask(title: "Перенос", startDate: anchor, dueDate: deadline, durationMinutes: 45)
        state.managedTasks = [task]
        let day = calendar.startOfDay(for: anchor)
        TaskEngine.schedule(task.id, at: day, allDay: true, in: &state)
        XCTAssertTrue(state.managedTasks[0].isAllDay)
        XCTAssertEqual(state.managedTasks[0].durationMinutes, 45)
        let timed = TaskEngine.calendarDropDate(on: day, yOffset: 810, hourHeight: 72, firstHour: 0, calendar: calendar)
        TaskEngine.schedule(task.id, at: timed, allDay: false, in: &state)
        XCTAssertFalse(state.managedTasks[0].isAllDay)
        XCTAssertEqual(state.managedTasks[0].plannedEndDate, timed.addingTimeInterval(45 * 60))
        XCTAssertEqual(state.managedTasks[0].dueDate, deadline)
    }
}
