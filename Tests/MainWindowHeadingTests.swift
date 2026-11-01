import XCTest
@testable import hidigFocus

final class MainWindowHeadingTests: XCTestCase {
    func testHeadingIncludesDayMonthAndYearInPlannerTimeZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-31T22:30:00Z"))
        func words(_ value: String) -> String { value.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        XCTAssertEqual(words(MainWindowHeading.date(instant, calendar: calendar)), "1 ноября 2026 г.")
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(words(MainWindowHeading.date(instant, calendar: calendar)), "31 октября 2026 г.")
    }
}
