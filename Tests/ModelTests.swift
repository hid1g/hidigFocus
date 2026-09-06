import XCTest
@testable import hidigFocus

final class ModelTests: XCTestCase {
    func testSidebarStartsWithGroups() {
        XCTAssertEqual(AppSection.allCases.first, .groups)
    }

    func testEveryPaletteHasDistinctLightAndDarkColors() {
        let palettes = SidebarColorPreference.allCases
        let lightCanvases = Set(palettes.map { $0.theme(isDark: false).canvas })
        let darkCanvases = Set(palettes.map { $0.theme(isDark: true).canvas })

        XCTAssertEqual(lightCanvases.count, palettes.count)
        XCTAssertEqual(darkCanvases.count, palettes.count)
        for palette in palettes {
            XCTAssertNotEqual(palette.theme(isDark: false).canvas, palette.theme(isDark: true).canvas)
            XCTAssertNotEqual(palette.theme(isDark: false).text, palette.theme(isDark: true).text)
        }
    }

    func testKnownServiceAliasesAreBlockedTogether() {
        XCTAssertEqual(Set(LocalRulesServer.expandedDomains(for: "vk.com")), Set(["vk.com", "vk.ru"]))
        XCTAssertEqual(Set(LocalRulesServer.expandedDomains(for: "https://vk.ru/feed")), Set(["vk.com", "vk.ru"]))
        XCTAssertEqual(Set(LocalRulesServer.expandedDomains(for: "x.com")), Set(["x.com", "twitter.com", "t.co"]))
        XCTAssertEqual(
            Set(LocalRulesServer.expandedDomains(for: "youtube.com")),
            Set(["youtube.com", "youtu.be", "youtube-nocookie.com"])
        )
    }

    func testUnknownDomainKeepsItsFullDomainRule() {
        XCTAssertEqual(LocalRulesServer.expandedDomains(for: "https://news.example.com/path?q=1"), ["news.example.com"])
    }

    func testRussianPluralForms() {
        let form: (Int) -> String = {
            RussianPluralizer.form($0, one: "день", few: "дня", many: "дней")
        }

        XCTAssertEqual(form(0), "дней")
        XCTAssertEqual(form(1), "день")
        XCTAssertEqual(form(2), "дня")
        XCTAssertEqual(form(4), "дня")
        XCTAssertEqual(form(5), "дней")
        XCTAssertEqual(form(11), "дней")
        XCTAssertEqual(form(14), "дней")
        XCTAssertEqual(form(21), "день")
        XCTAssertEqual(form(24), "дня")
        XCTAssertEqual(form(25), "дней")
    }

    func testHabitStreakCountsConsecutiveDays() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 12)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: reference))
        let beforeYesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: reference))
        let habit = Habit(
            name: "Медитация",
            checkInDayKeys: [
                DayKey.make(from: reference, calendar: calendar),
                DayKey.make(from: yesterday, calendar: calendar),
                DayKey.make(from: beforeYesterday, calendar: calendar)
            ]
        )

        XCTAssertEqual(habit.currentStreak(referenceDate: reference, calendar: calendar), 3)
    }

    func testHabitStreakFallsBackToYesterdayUntilDayEnds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 12)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: reference))
        let habit = Habit(
            name: "Чтение",
            checkInDayKeys: [DayKey.make(from: yesterday, calendar: calendar)]
        )

        XCTAssertEqual(habit.currentStreak(referenceDate: reference, calendar: calendar), 1)
    }

    func testResetKeepsHistoricalCheckins() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let today = Date()
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        var habit = Habit(
            name: "Без соцсетей",
            checkInDayKeys: [
                DayKey.make(from: today, calendar: calendar),
                DayKey.make(from: yesterday, calendar: calendar)
            ]
        )

        habit.resetCurrentStreak(calendar: calendar)

        XCTAssertFalse(habit.isChecked(on: today, calendar: calendar))
        XCTAssertTrue(habit.isChecked(on: yesterday, calendar: calendar))
        XCTAssertEqual(habit.currentStreak(referenceDate: today, calendar: calendar), 0)
    }

    func testYesterdayCanRestoreAStreakButOlderGapRemainsBroken() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let today = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 12)))
        let yesterday = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: today))
        let twoDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -2, to: today))
        let threeDaysAgo = try XCTUnwrap(calendar.date(byAdding: .day, value: -3, to: today))
        var habit = Habit(name: "Медитация", checkInDayKeys: [
            DayKey.make(from: today, calendar: calendar),
            DayKey.make(from: twoDaysAgo, calendar: calendar),
            DayKey.make(from: threeDaysAgo, calendar: calendar)
        ])

        XCTAssertEqual(habit.currentStreak(referenceDate: today, calendar: calendar), 1)
        habit.toggle(on: yesterday, calendar: calendar)
        XCTAssertEqual(habit.currentStreak(referenceDate: today, calendar: calendar), 4)

        habit.checkInDayKeys.remove(DayKey.make(from: twoDaysAgo, calendar: calendar))
        XCTAssertEqual(habit.currentStreak(referenceDate: today, calendar: calendar), 2)
    }

    func testRecurringOpenTaskIsNotCompletedByHistoricalCompletedTime() {
        let task = TickTickTask(
            id: "task",
            projectID: "project",
            projectName: "Project",
            title: "Recurring",
            dueDate: Date(),
            completedAt: Date(timeIntervalSince1970: 0),
            status: 0
        )

        XCTAssertFalse(task.isCompleted)
    }

    func testNewGroupDraftDoesNotBlockUntilApplied() {
        let group = BlockGroup.draft(name: "Черновик")

        XCTAssertFalse(group.isEnabled)
        XCTAssertTrue(group.resources.isEmpty)
    }

    func testScheduleReportsEndOfCurrentInterval() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 10, minute: 15)))
        let schedule = BlockSchedule(startMinute: 9 * 60, endMinute: 18 * 60, weekdays: Set(2...6), isAllDay: false)

        let end = try XCTUnwrap(schedule.nextInactiveDate(after: now, calendar: calendar))

        XCTAssertEqual(calendar.component(.hour, from: end), 18)
        XCTAssertEqual(calendar.component(.minute, from: end), 0)
        XCTAssertTrue(calendar.isDate(end, inSameDayAs: now))
    }

    func testPermanentScheduleHasNoEndDate() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 8, day: 31, hour: 10)))

        XCTAssertNil(BlockSchedule.allDayEveryDay.nextInactiveDate(after: now, calendar: calendar))
    }
}
