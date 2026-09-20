import XCTest
@testable import hidigFocus

final class ProtectionDaysTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return value
    }

    func testElapsedDaysAreCountedOnceAcrossDSTAndRestart() throws {
        var state = PersistedAppState()
        state.disciplineLastCountedDayKey = "2026-03-28"
        state.disciplineStreak = 4
        let now = try XCTUnwrap(DayKey.date(from: "2026-03-30", calendar: calendar))
        XCTAssertTrue(state.advanceProtectionDays(now: now, calendar: calendar))
        XCTAssertEqual(state.disciplineStreak, 6)
        var restored = try JSONDecoder().decode(PersistedAppState.self, from: JSONEncoder().encode(state))
        XCTAssertFalse(restored.advanceProtectionDays(now: now, calendar: calendar))
        XCTAssertEqual(restored.disciplineStreak, 6)
    }

    func testDisabledProtectionDoesNotAccumulateDays() throws {
        var state = PersistedAppState()
        state.protectionEnabled = false
        state.disciplineLastCountedDayKey = "2026-03-28"
        let now = try XCTUnwrap(DayKey.date(from: "2026-03-30", calendar: calendar))
        XCTAssertFalse(state.advanceProtectionDays(now: now, calendar: calendar))
        XCTAssertEqual(state.disciplineStreak, 0)
    }

    func testClockMovingBackDoesNotDoubleCountDays() throws {
        var state = PersistedAppState()
        state.disciplineLastCountedDayKey = "2026-03-30"
        state.disciplineStreak = 6
        let yesterday = try XCTUnwrap(DayKey.date(from: "2026-03-29", calendar: calendar))
        XCTAssertFalse(state.advanceProtectionDays(now: yesterday, calendar: calendar))
        XCTAssertEqual(state.disciplineLastCountedDayKey, "2026-03-30")
        XCTAssertEqual(state.disciplineStreak, 6)
    }
}
