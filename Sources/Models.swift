import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case today
    case tasks
    case groups
    case habits
    case statistics
    case tickTick
    case journal
    case settings

    static let allCases: [AppSection] = [.tasks, .groups, .habits, .statistics, .journal, .tickTick, .settings]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Сегодня"
        case .tasks: return "Задачи"
        case .groups: return "Группы"
        case .habits: return "Привычки"
        case .statistics: return "Статистика"
        case .tickTick: return "Интеграции"
        case .journal: return "Журнал"
        case .settings: return "Настройки"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sun.max"
        case .tasks: return "checklist"
        case .groups: return "shield"
        case .habits: return "checkmark.circle"
        case .statistics: return "chart.bar"
        case .tickTick: return "puzzlepiece.extension"
        case .journal: return "note.text"
        case .settings: return "gearshape"
        }
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Как в системе"
        case .light: return "Светлая"
        case .dark: return "Тёмная"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon.stars"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum BlockedResourceKind: String, Codable, CaseIterable, Identifiable {
    case domain
    case application

    var id: String { rawValue }

    var title: String {
        switch self {
        case .domain: return "Сайт"
        case .application: return "Приложение"
        }
    }
}

struct BlockedResource: Identifiable, Codable, Equatable, Hashable {
    var id = UUID()
    var kind: BlockedResourceKind
    var displayName: String
    var identifier: String
    var path: String?

    var shortLabel: String {
        let words = displayName.split(separator: " ")
        if words.count > 1 {
            return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}

struct BlockGroup: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var resources: [BlockedResource]
    var requiresAllTodayTasks = true
    var requiredTaskIDs: Set<String> = []
    var isEnabled = true
    var accessMode: GroupAccessMode = .tasks
    var schedule: BlockSchedule = .allDayEveryDay

    init(
        id: UUID = UUID(),
        name: String,
        resources: [BlockedResource],
        requiresAllTodayTasks: Bool = true,
        requiredTaskIDs: Set<String> = [],
        isEnabled: Bool = true,
        accessMode: GroupAccessMode = .tasks,
        schedule: BlockSchedule = .allDayEveryDay
    ) {
        self.id = id
        self.name = name
        self.resources = resources
        self.requiresAllTodayTasks = requiresAllTodayTasks
        self.requiredTaskIDs = requiredTaskIDs
        self.isEnabled = isEnabled
        self.accessMode = accessMode
        self.schedule = schedule
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, resources, requiresAllTodayTasks, requiredTaskIDs, isEnabled, accessMode, schedule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        resources = try container.decodeIfPresent([BlockedResource].self, forKey: .resources) ?? []
        requiresAllTodayTasks = try container.decodeIfPresent(Bool.self, forKey: .requiresAllTodayTasks) ?? true
        requiredTaskIDs = try container.decodeIfPresent(Set<String>.self, forKey: .requiredTaskIDs) ?? []
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        accessMode = try container.decodeIfPresent(GroupAccessMode.self, forKey: .accessMode) ?? .tasks
        schedule = try container.decodeIfPresent(BlockSchedule.self, forKey: .schedule) ?? .allDayEveryDay
    }

    static func draft(name: String) -> BlockGroup {
        BlockGroup(name: name, resources: [], isEnabled: false)
    }

    static let entertainment = BlockGroup(
        name: "Развлечения и соцсети",
        resources: [
            BlockedResource(kind: .domain, displayName: "YouTube", identifier: "youtube.com"),
            BlockedResource(kind: .domain, displayName: "ВКонтакте", identifier: "vk.com"),
            BlockedResource(kind: .domain, displayName: "Twitter", identifier: "x.com"),
            BlockedResource(kind: .domain, displayName: "Telegram Web", identifier: "web.telegram.org")
        ]
    )
}

enum GroupAccessMode: String, Codable, CaseIterable, Identifiable {
    case schedule
    case tasks
    case scheduleAndTasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .schedule: return "По расписанию"
        case .tasks: return "До выполнения задач"
        case .scheduleAndTasks: return "Расписание и задачи"
        }
    }

    var usesSchedule: Bool { self != .tasks }
    var usesTasks: Bool { self != .schedule }
}

struct BlockSchedule: Codable, Equatable {
    var startMinute: Int
    var endMinute: Int
    var weekdays: Set<Int>
    var isAllDay: Bool

    static let allDayEveryDay = BlockSchedule(
        startMinute: 0,
        endMinute: 24 * 60,
        weekdays: Set(1...7),
        isAllDay: true
    )

    func isActive(at date: Date = Date(), calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        guard weekdays.contains(weekday) else { return false }
        guard !isAllDay else { return true }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if startMinute == endMinute { return true }
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }

    func nextInactiveDate(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard isActive(at: date, calendar: calendar) else { return date }

        if isAllDay || startMinute == endMinute {
            guard weekdays != Set(1...7) else { return nil }
            let startOfToday = calendar.startOfDay(for: date)
            for offset in 1...7 {
                guard let candidate = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
                let weekday = calendar.component(.weekday, from: candidate)
                if !weekdays.contains(weekday) { return candidate }
            }
            return nil
        }

        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let endDayOffset = startMinute > endMinute && minute >= startMinute ? 1 : 0
        guard let endDay = calendar.date(byAdding: .day, value: endDayOffset, to: date) else { return nil }
        return calendar.date(
            bySettingHour: endMinute / 60,
            minute: endMinute % 60,
            second: 0,
            of: endDay
        )
    }

    var timeDescription: String {
        if isAllDay { return "весь день" }
        return "\(Self.timeString(startMinute))–\(Self.timeString(endMinute))"
    }

    private static func timeString(_ minute: Int) -> String {
        String(format: "%02d:%02d", max(0, min(minute, 1439)) / 60, max(0, min(minute, 1439)) % 60)
    }
}

enum BrowserBlockReason: String, Codable {
    case tasks
    case schedule
    case permanent
}

struct BrowserBlockRule: Codable, Equatable {
    var domain: String
    var groupName: String
    var reason: BrowserBlockReason
    var remainingTasks: [String]
    var blockedUntil: Date?
}

struct TickTickTask: Identifiable, Codable, Equatable, Hashable {
    var id: String
    var projectID: String
    var projectName: String
    var title: String
    var dueDate: Date?
    var completedAt: Date?
    var status: Int

    var isCompleted: Bool {
        status == 2
    }
}

struct FocusTask: Identifiable, Codable, Equatable, Hashable {
    var id: String = "local.\(UUID().uuidString)"
    var title: String
    var dayKey: String = DayKey.make(from: Date())
    var isCompleted = false

    var asTask: TickTickTask {
        TickTickTask(
            id: id,
            projectID: "hidigfocus.local",
            projectName: "hidigFocus",
            title: title,
            dueDate: nil,
            completedAt: isCompleted ? Date() : nil,
            status: isCompleted ? 2 : 0
        )
    }
}

enum HabitPriority: String, Codable, CaseIterable, Identifiable {
    case normal
    case important
    case key

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: return "Обычная"
        case .important: return "Важная"
        case .key: return "Ключевая"
        }
    }

    var rank: Int {
        switch self {
        case .normal: return 0
        case .important: return 1
        case .key: return 2
        }
    }
}

enum HabitScheduleKind: String, Codable, CaseIterable, Identifiable {
    case weekdays
    case interval
    case weeklyGoal
    case monthlyGoal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekdays: return "По дням"
        case .interval: return "Интервал"
        case .weeklyGoal: return "За неделю"
        case .monthlyGoal: return "За месяц"
        }
    }
}

struct HabitSchedule: Codable, Equatable {
    var kind: HabitScheduleKind = .weekdays
    var weekdays: Set<Int> = Set(1...7)
    var intervalDays = 1
    var targetCount = 1

    static let everyDay = HabitSchedule()

    var summary: String {
        switch kind {
        case .weekdays:
            if weekdays == Set(1...7) { return "Каждый день" }
            if weekdays == Set(2...6) { return "По будням" }
            if weekdays == Set([1, 7]) { return "По выходным" }
            let order = [2, 3, 4, 5, 6, 7, 1]
            let names = [1: "Вс", 2: "Пн", 3: "Вт", 4: "Ср", 5: "Чт", 6: "Пт", 7: "Сб"]
            return order.filter(weekdays.contains).compactMap { names[$0] }.joined(separator: ", ")
        case .interval:
            if intervalDays == 1 { return "Каждый день" }
            return "Каждые \(RussianPluralizer.phrase(intervalDays, one: "день", few: "дня", many: "дней"))"
        case .weeklyGoal:
            return "\(RussianPluralizer.phrase(targetCount, one: "раз", few: "раза", many: "раз")) в неделю"
        case .monthlyGoal:
            return "\(RussianPluralizer.phrase(targetCount, one: "раз", few: "раза", many: "раз")) в месяц"
        }
    }
}

struct Habit: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var createdAt: Date
    var checkInDayKeys: Set<String>
    var streakResetDayKey: String?
    var priority: HabitPriority
    var schedule: HabitSchedule

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        checkInDayKeys: Set<String> = [],
        streakResetDayKey: String? = nil,
        priority: HabitPriority = .normal,
        schedule: HabitSchedule = .everyDay
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.checkInDayKeys = checkInDayKeys
        self.streakResetDayKey = streakResetDayKey
        self.priority = priority
        self.schedule = schedule
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, createdAt, checkInDayKeys, streakResetDayKey, priority, schedule
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        checkInDayKeys = try container.decodeIfPresent(Set<String>.self, forKey: .checkInDayKeys) ?? []
        streakResetDayKey = try container.decodeIfPresent(String.self, forKey: .streakResetDayKey)
        priority = try container.decodeIfPresent(HabitPriority.self, forKey: .priority) ?? .normal
        schedule = try container.decodeIfPresent(HabitSchedule.self, forKey: .schedule) ?? .everyDay
    }

    func isChecked(on date: Date, calendar: Calendar = .current) -> Bool {
        checkInDayKeys.contains(DayKey.make(from: date, calendar: calendar))
    }

    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        switch schedule.kind {
        case .weekdays:
            return schedule.weekdays.contains(calendar.component(.weekday, from: date))
        case .interval:
            let start = calendar.startOfDay(for: createdAt)
            let target = calendar.startOfDay(for: date)
            guard target >= start else { return false }
            let days = calendar.dateComponents([.day], from: start, to: target).day ?? 0
            return days % max(1, min(schedule.intervalDays, 30)) == 0
        case .weeklyGoal, .monthlyGoal:
            return true
        }
    }

    func isDue(on date: Date, calendar: Calendar = .current) -> Bool {
        switch schedule.kind {
        case .weekdays, .interval:
            return isScheduled(on: date, calendar: calendar)
        case .weeklyGoal, .monthlyGoal:
            let value = progress(on: date, calendar: calendar)
            return isChecked(on: date, calendar: calendar) || value.completed < value.target
        }
    }

    func progress(on date: Date = Date(), calendar: Calendar = .current) -> (completed: Int, target: Int) {
        switch schedule.kind {
        case .weeklyGoal:
            return (checkInCount(in: calendar.dateInterval(of: .weekOfYear, for: date), calendar: calendar), max(1, min(schedule.targetCount, 7)))
        case .monthlyGoal:
            return (checkInCount(in: calendar.dateInterval(of: .month, for: date), calendar: calendar), max(1, min(schedule.targetCount, 30)))
        case .weekdays, .interval:
            return (isChecked(on: date, calendar: calendar) ? 1 : 0, 1)
        }
    }

    var progressDescription: String? {
        switch schedule.kind {
        case .weeklyGoal, .monthlyGoal:
            let value = progress()
            return "\(value.completed)/\(value.target)"
        case .weekdays, .interval:
            return nil
        }
    }

    func currentStreak(referenceDate: Date = Date(), calendar: Calendar = .current) -> Int {
        guard !checkInDayKeys.isEmpty else { return 0 }
        switch schedule.kind {
        case .weekdays, .interval:
            return occurrenceStreak(referenceDate: referenceDate, calendar: calendar)
        case .weeklyGoal:
            return periodStreak(component: .weekOfYear, referenceDate: referenceDate, calendar: calendar)
        case .monthlyGoal:
            return periodStreak(component: .month, referenceDate: referenceDate, calendar: calendar)
        }
    }

    var streakUnit: String {
        switch schedule.kind {
        case .weeklyGoal: return "нед."
        case .monthlyGoal: return "мес."
        case .weekdays, .interval: return ""
        }
    }

    mutating func toggleToday(calendar: Calendar = .current) {
        toggle(on: Date(), calendar: calendar)
    }

    mutating func toggle(on date: Date, calendar: Calendar = .current) {
        let key = DayKey.make(from: date, calendar: calendar)
        if checkInDayKeys.contains(key) {
            checkInDayKeys.remove(key)
        } else {
            checkInDayKeys.insert(key)
        }
    }

    mutating func resetCurrentStreak(calendar: Calendar = .current) {
        let key = DayKey.make(from: Date(), calendar: calendar)
        streakResetDayKey = key
        checkInDayKeys.remove(key)
    }

    private func occurrenceStreak(referenceDate: Date, calendar: Calendar) -> Int {
        var cursor = calendar.startOfDay(for: referenceDate)
        if isScheduled(on: cursor, calendar: calendar), !isChecked(on: cursor, calendar: calendar) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }

        var count = 0
        for _ in 0..<3_660 {
            if isScheduled(on: cursor, calendar: calendar) {
                let key = DayKey.make(from: cursor, calendar: calendar)
                if let reset = streakResetDayKey, key < reset { break }
                guard checkInDayKeys.contains(key) else { break }
                count += 1
            }
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    private func periodStreak(component: Calendar.Component, referenceDate: Date, calendar: Calendar) -> Int {
        guard var interval = calendar.dateInterval(of: component, for: referenceDate) else { return 0 }
        var count = 0
        if streakCheckInCount(in: interval, calendar: calendar) >= max(1, schedule.targetCount) {
            count = 1
        }
        guard let previousStart = calendar.date(byAdding: component, value: -1, to: interval.start),
              let previousInterval = calendar.dateInterval(of: component, for: previousStart) else { return count }
        interval = previousInterval

        for _ in 0..<520 {
            if streakCheckInCount(in: interval, calendar: calendar) < max(1, schedule.targetCount) { break }
            count += 1
            guard let priorStart = calendar.date(byAdding: component, value: -1, to: interval.start),
                  let priorInterval = calendar.dateInterval(of: component, for: priorStart) else { break }
            interval = priorInterval
        }
        return count
    }

    private func checkInCount(in interval: DateInterval?, calendar: Calendar) -> Int {
        guard let interval else { return 0 }
        return checkInDayKeys.compactMap { DayKey.date(from: $0, calendar: calendar) }
            .filter(interval.contains)
            .count
    }

    private func streakCheckInCount(in interval: DateInterval, calendar: Calendar) -> Int {
        checkInDayKeys
            .filter { key in
                guard let reset = streakResetDayKey else { return true }
                return key >= reset
            }
            .compactMap { DayKey.date(from: $0, calendar: calendar) }
            .filter(interval.contains)
            .count
    }
}

enum ActivityEventKind: String, Codable {
    case applicationClosed
    case groupUnlockAttempt
    case taskSync
    case protectionDisabled
    case habitChecked
    case groupUnlocked
    case error
}

struct ActivityEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var timestamp = Date()
    var kind: ActivityEventKind
    var message: String
}

struct JournalEntry: Identifiable, Equatable {
    var id: String { fileURL.path }
    var fileURL: URL
    var title: String
    var modifiedAt: Date
}

enum JournalSaveState: Equatable {
    case idle
    case saving
    case saved(Date)
    case failed

    var title: String {
        switch self {
        case .idle: return "Изменений пока нет"
        case .saving: return "Сохраняется…"
        case .saved(let date): return "Сохранено в \(date.formatted(date: .omitted, time: .shortened))"
        case .failed: return "Не удалось сохранить"
        }
    }

    var isError: Bool {
        if case .failed = self { return true }
        return false
    }
}

struct PersistedAppState: Codable {
    var schemaVersion = 2
    var protectionEnabled = true
    var groups: [BlockGroup] = [.entertainment]
    var habits: [Habit] = [Habit(name: "Медитация")]
    var cachedTasks: [TickTickTask] = []
    var localTasks: [FocusTask] = []
    var lastSuccessfulSync: Date?
    var events: [ActivityEvent] = []
    var disciplineStreak = 0
    var disciplineLastCountedDayKey: String?
    var taskFolders: [TaskFolder] = []
    var taskLists: [TaskList] = [TaskList.inbox]
    var managedTasks: [ManagedTask] = []
    var pomodoroSessions: [PomodoroSession] = []
    var activePomodoro: ActivePomodoro?
    var taskSettings = TaskSettings()
    var taskImportHistory: [TaskImportReport] = []
    var lastPlannerSyncAt: Date?
    var googleCalendarConnection = GoogleCalendarConnection()

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, protectionEnabled, groups, habits, cachedTasks, localTasks, lastSuccessfulSync, events
        case disciplineStreak, disciplineLastCountedDayKey
        case taskFolders, taskLists, managedTasks, pomodoroSessions, activePomodoro, taskSettings
        case taskImportHistory, googleCalendarConnection, lastPlannerSyncAt
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        protectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .protectionEnabled) ?? true
        groups = try container.decodeIfPresent([BlockGroup].self, forKey: .groups) ?? [.entertainment]
        habits = try container.decodeIfPresent([Habit].self, forKey: .habits) ?? [Habit(name: "Медитация")]
        cachedTasks = try container.decodeIfPresent([TickTickTask].self, forKey: .cachedTasks) ?? []
        localTasks = try container.decodeIfPresent([FocusTask].self, forKey: .localTasks) ?? []
        lastSuccessfulSync = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSync)
        events = try container.decodeIfPresent([ActivityEvent].self, forKey: .events) ?? []
        disciplineStreak = try container.decodeIfPresent(Int.self, forKey: .disciplineStreak) ?? 0
        disciplineLastCountedDayKey = try container.decodeIfPresent(String.self, forKey: .disciplineLastCountedDayKey)
        taskFolders = try container.decodeIfPresent([TaskFolder].self, forKey: .taskFolders) ?? []
        taskLists = try container.decodeIfPresent([TaskList].self, forKey: .taskLists) ?? [.inbox]
        if !taskLists.contains(where: { $0.id == TaskList.inbox.id }) { taskLists.insert(.inbox, at: 0) }
        managedTasks = try container.decodeIfPresent([ManagedTask].self, forKey: .managedTasks) ?? []
        pomodoroSessions = try container.decodeIfPresent([PomodoroSession].self, forKey: .pomodoroSessions) ?? []
        activePomodoro = try container.decodeIfPresent(ActivePomodoro.self, forKey: .activePomodoro)
        taskSettings = try container.decodeIfPresent(TaskSettings.self, forKey: .taskSettings) ?? TaskSettings()
        taskImportHistory = try container.decodeIfPresent([TaskImportReport].self, forKey: .taskImportHistory) ?? []
        lastPlannerSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastPlannerSyncAt)
        googleCalendarConnection = try container.decodeIfPresent(GoogleCalendarConnection.self, forKey: .googleCalendarConnection) ?? GoogleCalendarConnection()
        schemaVersion = 2
    }
}

enum TickTickConnectionState: Equatable {
    case checking
    case cliMissing
    case signedOut
    case connecting
    case connected
    case failed(String)

    var title: String {
        switch self {
        case .checking: return "Проверяем подключение"
        case .cliMissing: return "Нужен TickTick CLI"
        case .signedOut: return "Требуется вход"
        case .connecting: return "Открываем авторизацию"
        case .connected: return "Аккаунт подключён"
        case .failed: return "Ошибка подключения"
        }
    }
}

enum DayKey {
    static func make(from date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    static func date(from key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

enum RussianPluralizer {
    static func form(_ count: Int, one: String, few: String, many: String) -> String {
        let absolute = abs(count)
        let lastTwo = absolute % 100
        if (11...14).contains(lastTwo) { return many }

        switch absolute % 10 {
        case 1: return one
        case 2...4: return few
        default: return many
        }
    }

    static func phrase(_ count: Int, one: String, few: String, many: String) -> String {
        "\(count) \(form(count, one: one, few: few, many: many))"
    }
}

enum AppError: LocalizedError {
    case invalidDomain
    case invalidApplication
    case duplicateResource
    case journalUnavailable
    case invalidJournalTitle
    case journalTitleExists

    var errorDescription: String? {
        switch self {
        case .invalidDomain: return "Введите корректный домен без пути."
        case .invalidApplication: return "Не удалось определить выбранное приложение."
        case .duplicateResource: return "Этот ресурс уже есть в группе."
        case .journalUnavailable: return "Не удалось открыть папку журнала."
        case .invalidJournalTitle: return "Введите название файла. Символы / и : использовать нельзя."
        case .journalTitleExists: return "Файл с таким названием уже существует."
        }
    }
}

// Calendar-day streak: enabling starts at zero; each crossed local day adds one.
extension PersistedAppState {
    @discardableResult
    mutating func advanceProtectionDays(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = DayKey.make(from: now, calendar: calendar)
        guard protectionEnabled else { return false }
        guard let key = disciplineLastCountedDayKey,
              let previous = DayKey.date(from: key, calendar: calendar) else {
            disciplineLastCountedDayKey = today
            return true
        }
        let elapsed = calendar.dateComponents([.day], from: previous, to: calendar.startOfDay(for: now)).day ?? 0
        guard elapsed > 0 else { return false }
        disciplineStreak += elapsed
        disciplineLastCountedDayKey = today
        return true
    }
}
