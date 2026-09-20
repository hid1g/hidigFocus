import Foundation

enum TasksPresentation: String, CaseIterable, Identifiable {
    case list
    case calendar
    case matrix

    var id: String { rawValue }
    var title: String {
        switch self {
        case .list: return "Список"
        case .calendar: return "Календарь"
        case .matrix: return "Матрица"
        }
    }
}

enum TaskCalendarMode: String, CaseIterable, Identifiable {
    case day
    case week
    case month
    case agenda

    var id: String { rawValue }
    var title: String {
        switch self {
        case .day: return "День"
        case .week: return "Неделя"
        case .month: return "Месяц"
        case .agenda: return "Повестка"
        }
    }
}

enum TaskSidebarSelection: Hashable {
    case today
    case nextSevenDays
    case inbox
    case list(UUID)
    case completed
    case trash
}

enum ManagedTaskStatus: String, Codable, CaseIterable {
    case active
    case completed
    case wontDo
    case trashed
}

enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
    case none = 0
    case low = 1
    case medium = 3
    case high = 5

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .none: return "Без приоритета"
        case .low: return "Низкий"
        case .medium: return "Средний"
        case .high: return "Высокий"
        }
    }
}

enum EisenhowerQuadrant: String, Codable, CaseIterable, Identifiable {
    case urgentImportant
    case important
    case urgent
    case neither

    var id: String { rawValue }
    var title: String {
        switch self {
        case .urgentImportant: return "Срочно и важно"
        case .important: return "Важно, но не срочно"
        case .urgent: return "Срочно, но не важно"
        case .neither: return "Не срочно и не важно"
        }
    }
}

enum TaskRepeatFrequency: String, Codable, CaseIterable, Identifiable {
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }
    var title: String {
        switch self {
        case .daily: return "Ежедневно"
        case .weekly: return "Еженедельно"
        case .monthly: return "Ежемесячно"
        case .yearly: return "Ежегодно"
        }
    }
}

struct TaskRepeatRule: Codable, Equatable {
    var frequency: TaskRepeatFrequency
    var interval: Int = 1
    var weekdays: Set<Int> = []
    var endDate: Date?
    var sourceRule: String?
}

struct TaskReminder: Identifiable, Codable, Equatable {
    var id = UUID()
    var date: Date?
    var relativeMinutes: Int?
    var sourceValue: String?
}

struct TaskChecklistItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isCompleted = false
    var sortOrder: Int64 = 0
}

struct TaskAttachment: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var localPath: String?
    var remoteURL: URL?
    var createdAt = Date()
}

struct TaskComment: Identifiable, Codable, Equatable {
    var id = UUID()
    var text: String
    var author: String?
    var createdAt = Date()
    var sourceID: String?
}

struct TaskChange: Identifiable, Codable, Equatable {
    var id = UUID()
    var date = Date()
    var summary: String
}

struct TaskFolder: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var colorHex = "#7A9B63"
    var sortOrder: Int64 = 0
    var isCollapsed = false
    var sourceID: String?
}

struct TaskList: Identifiable, Codable, Equatable {
    static let inboxID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let inbox = TaskList(id: inboxID, name: "Входящие", colorHex: "#7A9B63", sortOrder: 0, isPinned: true)

    var id = UUID()
    var folderID: UUID?
    var name: String
    var colorHex = "#7A9B63"
    var sortOrder: Int64 = 0
    var isPinned = false
    var sourceID: String?
}

struct ManagedTask: Identifiable, Codable, Equatable {
    var id = UUID()
    var sourceID: String?
    var sourceName: String?
    var sourceListID: String?
    var listID: UUID = TaskList.inboxID
    var parentTaskID: UUID?
    var title: String
    var description = ""
    var notes = ""
    var links: [URL] = []
    var startDate: Date?
    var dueDate: Date?
    var durationMinutes: Int = 30
    var isAllDay = false
    var timeZoneID = TimeZone.current.identifier
    var reminders: [TaskReminder] = []
    var repeatRule: TaskRepeatRule?
    var priority: TaskPriority = .none
    var isImportant = false
    var tags: [String] = []
    var subtasks: [ManagedTask] = []
    var checklist: [TaskChecklistItem] = []
    var attachments: [TaskAttachment] = []
    var comments: [TaskComment] = []
    var plannedPomodoros = 0
    var completedPomodoros = 0
    var status: ManagedTaskStatus = .active
    var createdAt = Date()
    var modifiedAt = Date()
    var completedAt: Date?
    var deletedAt: Date?
    var sortOrder: Int64 = 0
    var googleEventID: String?
    var googleCalendarID: String?
    var googleETag: String?
    var googleUpdatedAt: Date?
    var lastSyncedAt: Date?
    var changeHistory: [TaskChange] = []

    var quadrant: EisenhowerQuadrant {
        get {
            if isImportant && priority == .high { return .urgentImportant }
            if isImportant { return .important }
            if priority == .high { return .urgent }
            return .neither
        }
        set {
            switch newValue {
            case .urgentImportant:
                isImportant = true
                priority = .high
            case .important:
                isImportant = true
                if priority == .high { priority = .medium }
            case .urgent:
                isImportant = false
                priority = .high
            case .neither:
                isImportant = false
                if priority == .high { priority = .none }
            }
        }
    }

    var calendarEndDate: Date? {
        guard let startDate else { return nil }
        return Calendar.current.date(byAdding: .minute, value: max(15, durationMinutes), to: startDate)
    }
}

enum PomodoroPhase: String, Codable {
    case work
    case shortBreak
    case longBreak
}

struct PomodoroSession: Identifiable, Codable, Equatable {
    var id = UUID()
    var sourceID: String?
    var taskID: UUID?
    var listID: UUID?
    var phase: PomodoroPhase = .work
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: Int
    var wasCompleted: Bool
}

struct ActivePomodoro: Codable, Equatable {
    var id = UUID()
    var taskID: UUID
    var phase: PomodoroPhase = .work
    var startedAt = Date()
    var targetSeconds: Int
    var accumulatedPauseSeconds = 0
    var pausedAt: Date?
}

struct TaskSettings: Codable, Equatable {
    var workMinutes = 25
    var shortBreakMinutes = 5
    var longBreakMinutes = 15
    var completedPomodorosBeforeLongBreak = 4
    var showCompletedInMatrix = false
}

struct TaskImportReport: Identifiable, Codable, Equatable {
    var id = UUID()
    var source = "TickTick"
    var startedAt = Date()
    var finishedAt: Date?
    var foldersFound = 0
    var listsFound = 0
    var activeTasksFound = 0
    var completedTasksFound = 0
    var imported = 0
    var updated = 0
    var skipped = 0
    var failed = 0

    private enum CodingKeys: String, CodingKey {
        case id, source, startedAt, finishedAt, foldersFound, listsFound
        case activeTasksFound, completedTasksFound, imported, updated, skipped, failed
    }

    init(
        id: UUID = UUID(), source: String = "TickTick", startedAt: Date = Date(),
        finishedAt: Date? = nil, foldersFound: Int = 0, listsFound: Int = 0,
        activeTasksFound: Int = 0, completedTasksFound: Int = 0,
        imported: Int = 0, updated: Int = 0, skipped: Int = 0, failed: Int = 0
    ) {
        self.id = id
        self.source = source
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.foldersFound = foldersFound
        self.listsFound = listsFound
        self.activeTasksFound = activeTasksFound
        self.completedTasksFound = completedTasksFound
        self.imported = imported
        self.updated = updated
        self.skipped = skipped
        self.failed = failed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "TickTick"
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        foldersFound = try container.decodeIfPresent(Int.self, forKey: .foldersFound) ?? 0
        listsFound = try container.decodeIfPresent(Int.self, forKey: .listsFound) ?? 0
        activeTasksFound = try container.decodeIfPresent(Int.self, forKey: .activeTasksFound) ?? 0
        completedTasksFound = try container.decodeIfPresent(Int.self, forKey: .completedTasksFound) ?? 0
        imported = try container.decodeIfPresent(Int.self, forKey: .imported) ?? 0
        updated = try container.decodeIfPresent(Int.self, forKey: .updated) ?? 0
        skipped = try container.decodeIfPresent(Int.self, forKey: .skipped) ?? 0
        failed = try container.decodeIfPresent(Int.self, forKey: .failed) ?? 0
    }
}

struct GoogleCalendarConnection: Codable, Equatable {
    var isConnected = false
    var accountEmail: String?
    var selectedCalendarIDs: Set<String> = []
    var lastSuccessfulSync: Date?
    var lastSyncError: String?
}
