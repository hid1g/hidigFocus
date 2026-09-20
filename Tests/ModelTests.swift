import XCTest
@testable import hidigFocus

final class ModelTests: XCTestCase {
    func testTasksAppearImmediatelyBeforeGroups() {
        XCTAssertEqual(AppSection.allCases.first, .tasks)
        XCTAssertEqual(AppSection.allCases.dropFirst().first, .groups)
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

    func testLegacyHabitKeepsDataAndDefaultsToDailySchedule() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "Старая привычка",
          "createdAt": "2026-08-20T09:00:00Z",
          "checkInDayKeys": ["2026-08-28", "2026-08-29"]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let habit = try decoder.decode(Habit.self, from: Data(json.utf8))

        XCTAssertEqual(habit.id, id)
        XCTAssertEqual(habit.name, "Старая привычка")
        XCTAssertEqual(habit.checkInDayKeys, Set(["2026-08-28", "2026-08-29"]))
        XCTAssertEqual(habit.priority, .normal)
        XCTAssertEqual(habit.schedule, .everyDay)
    }

    func testWeekdayHabitIgnoresWeekendInSchedule() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let friday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 4, hour: 12)))
        let saturday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 5, hour: 12)))
        let habit = Habit(
            name: "Рабочий ритм",
            createdAt: friday,
            checkInDayKeys: [DayKey.make(from: friday, calendar: calendar)],
            schedule: HabitSchedule(kind: .weekdays, weekdays: Set(2...6))
        )

        XCTAssertTrue(habit.isScheduled(on: friday, calendar: calendar))
        XCTAssertFalse(habit.isScheduled(on: saturday, calendar: calendar))
    }

    func testIntervalHabitUsesCreationDateAsAnchor() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 12)))
        let thirdDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 2, to: start))
        let fourthDay = try XCTUnwrap(calendar.date(byAdding: .day, value: 3, to: start))
        let habit = Habit(
            name: "Каждые три дня",
            createdAt: start,
            schedule: HabitSchedule(kind: .interval, intervalDays: 3)
        )

        XCTAssertFalse(habit.isScheduled(on: thirdDay, calendar: calendar))
        XCTAssertTrue(habit.isScheduled(on: fourthDay, calendar: calendar))
    }

    func testWeeklyGoalReportsCurrentProgress() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12)))
        let tuesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: monday))
        let habit = Habit(
            name: "Тренировка",
            createdAt: monday,
            checkInDayKeys: [DayKey.make(from: monday, calendar: calendar), DayKey.make(from: tuesday, calendar: calendar)],
            schedule: HabitSchedule(kind: .weeklyGoal, targetCount: 3)
        )

        let progress = habit.progress(on: tuesday, calendar: calendar)
        XCTAssertEqual(progress.completed, 2)
        XCTAssertEqual(progress.target, 3)
        XCTAssertTrue(habit.isDue(on: tuesday, calendar: calendar))
    }

    func testWeeklyGoalStreakDoesNotReturnAfterReset() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let monday = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 7, hour: 12)))
        let tuesday = try XCTUnwrap(calendar.date(byAdding: .day, value: 1, to: monday))
        let habit = Habit(
            name: "Тренировка",
            createdAt: monday,
            checkInDayKeys: [DayKey.make(from: monday, calendar: calendar)],
            streakResetDayKey: DayKey.make(from: tuesday, calendar: calendar),
            schedule: HabitSchedule(kind: .weeklyGoal, targetCount: 1)
        )

        XCTAssertEqual(habit.progress(on: tuesday, calendar: calendar).completed, 1)
        XCTAssertEqual(habit.currentStreak(referenceDate: tuesday, calendar: calendar), 0)
    }
}
