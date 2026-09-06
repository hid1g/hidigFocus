import Foundation
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case today
    case groups
    case habits
    case statistics
    case tickTick
    case journal
    case settings

    static let allCases: [AppSection] = [.groups, .habits, .statistics, .journal, .tickTick, .settings]

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Сегодня"
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

struct Habit: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var checkInDayKeys: Set<String> = []
    var streakResetDayKey: String?

    func isChecked(on date: Date, calendar: Calendar = .current) -> Bool {
        checkInDayKeys.contains(DayKey.make(from: date, calendar: calendar))
    }

    func currentStreak(referenceDate: Date = Date(), calendar: Calendar = .current) -> Int {
        guard !checkInDayKeys.isEmpty else { return 0 }

        let todayKey = DayKey.make(from: referenceDate, calendar: calendar)
        var cursor = referenceDate
        if !checkInDayKeys.contains(todayKey) {
            cursor = calendar.date(byAdding: .day, value: -1, to: referenceDate) ?? referenceDate
        }

        var count = 0
        while true {
            let key = DayKey.make(from: cursor, calendar: calendar)
            if let reset = streakResetDayKey, key < reset { break }
            guard checkInDayKeys.contains(key) else { break }
            count += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return count
    }

    mutating func toggleToday(calendar: Calendar = .current) {
        let key = DayKey.make(from: Date(), calendar: calendar)
        if checkInDayKeys.contains(key) {
            checkInDayKeys.remove(key)
        } else {
            checkInDayKeys.insert(key)
        }
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
    var protectionEnabled = true
    var groups: [BlockGroup] = [.entertainment]
    var habits: [Habit] = [Habit(name: "Медитация")]
    var cachedTasks: [TickTickTask] = []
    var localTasks: [FocusTask] = []
    var lastSuccessfulSync: Date?
    var events: [ActivityEvent] = []
    var disciplineStreak = 0
    var disciplineLastCountedDayKey: String?

    private enum CodingKeys: String, CodingKey {
        case protectionEnabled, groups, habits, cachedTasks, localTasks, lastSuccessfulSync, events
        case disciplineStreak, disciplineLastCountedDayKey
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .protectionEnabled) ?? true
        groups = try container.decodeIfPresent([BlockGroup].self, forKey: .groups) ?? [.entertainment]
        habits = try container.decodeIfPresent([Habit].self, forKey: .habits) ?? [Habit(name: "Медитация")]
        cachedTasks = try container.decodeIfPresent([TickTickTask].self, forKey: .cachedTasks) ?? []
        localTasks = try container.decodeIfPresent([FocusTask].self, forKey: .localTasks) ?? []
        lastSuccessfulSync = try container.decodeIfPresent(Date.self, forKey: .lastSuccessfulSync)
        events = try container.decodeIfPresent([ActivityEvent].self, forKey: .events) ?? []
        disciplineStreak = try container.decodeIfPresent(Int.self, forKey: .disciplineStreak) ?? 0
        disciplineLastCountedDayKey = try container.decodeIfPresent(String.self, forKey: .disciplineLastCountedDayKey)
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
