import Foundation

func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
let reference = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 12))!
let yesterday = calendar.date(byAdding: .day, value: -1, to: reference)!
let beforeYesterday = calendar.date(byAdding: .day, value: -2, to: reference)!

let threeDayHabit = Habit(
    name: "Медитация",
    checkInDayKeys: [reference, yesterday, beforeYesterday].map {
        DayKey.make(from: $0, calendar: calendar)
    }.reduce(into: Set<String>()) { $0.insert($1) }
)
require(threeDayHabit.currentStreak(referenceDate: reference, calendar: calendar) == 3, "three-day streak")

let yesterdayOnly = Habit(
    name: "Чтение",
    checkInDayKeys: [DayKey.make(from: yesterday, calendar: calendar)]
)
require(yesterdayOnly.currentStreak(referenceDate: reference, calendar: calendar) == 1, "unfinished current day must not break streak")

var restored = Habit(
    name: "Восстановление",
    checkInDayKeys: [reference, beforeYesterday].map {
        DayKey.make(from: $0, calendar: calendar)
    }.reduce(into: Set<String>()) { $0.insert($1) }
)
require(restored.currentStreak(referenceDate: reference, calendar: calendar) == 1, "gap must break streak")
restored.toggle(on: yesterday, calendar: calendar)
require(restored.currentStreak(referenceDate: reference, calendar: calendar) == 3, "yesterday backfill must restore streak")

let recurringOpenTask = TickTickTask(
    id: "task",
    projectID: "project",
    projectName: "Project",
    title: "Recurring",
    dueDate: reference,
    completedAt: yesterday,
    status: 0
)
require(!recurringOpenTask.isCompleted, "historical completion must not complete current recurrence")

let normalized = LocalRulesServer.normalizedDomain("https://www.YouTube.com/watch?v=1")
require(normalized == "youtube.com", "domain normalization")

let pluralCases = [
    (0, "дней"), (1, "день"), (2, "дня"), (4, "дня"), (5, "дней"),
    (11, "дней"), (14, "дней"), (21, "день"), (24, "дня"), (25, "дней")
]
for (count, expected) in pluralCases {
    let actual = RussianPluralizer.form(count, one: "день", few: "дня", many: "дней")
    require(actual == expected, "Russian plural form for \(count)")
}

let weekdaySchedule = BlockSchedule(
    startMinute: 10 * 60,
    endMinute: 17 * 60,
    weekdays: Set(2...6),
    isAllDay: false
)
let fridayNoon = calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 12))!
let fridayEvening = calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 18))!
let saturdayNoon = calendar.date(from: DateComponents(year: 2026, month: 8, day: 29, hour: 12))!
require(weekdaySchedule.isActive(at: fridayNoon, calendar: calendar), "weekday schedule during interval")
require(!weekdaySchedule.isActive(at: fridayEvening, calendar: calendar), "weekday schedule after interval")
require(!weekdaySchedule.isActive(at: saturdayNoon, calendar: calendar), "weekday schedule on weekend")

let legacyStateData = Data(#"{"groups":[{"name":"Legacy","resources":[]}]}"#.utf8)
let legacyState = try JSONDecoder().decode(PersistedAppState.self, from: legacyStateData)
require(legacyState.groups.first?.accessMode == .tasks, "legacy group access mode migration")
require(legacyState.groups.first?.schedule == .allDayEveryDay, "legacy group schedule migration")
require(legacyState.localTasks.isEmpty, "legacy state local tasks migration")

print("Model smoke tests passed")
