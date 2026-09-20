import Foundation

struct GoogleCalendarEventSnapshot: Codable, Equatable {
    var id: String
    var calendarID: String
    var etag: String?
    var title: String
    var description: String
    var startDate: Date
    var endDate: Date
    var isAllDay: Bool
    var timeZoneID: String
    var updatedAt: Date
    var recurrence: [String] = []
    var isDeleted = false
}

enum GoogleSyncDecision: Equatable {
    case createRemote
    case updateRemote
    case updateLocal
    case unchanged
    case unlinkDeletedRemote
    case conflictPreferLocal
    case conflictPreferRemote
}

enum GoogleSyncEngine {
    static let synchronizedFields = ["title", "description", "startDate", "durationMinutes", "isAllDay", "timeZoneID", "repeatRule"]

    static func decision(for task: ManagedTask, remote: GoogleCalendarEventSnapshot?) -> GoogleSyncDecision {
        guard task.googleEventID != nil else { return .createRemote }
        guard let remote else { return .unlinkDeletedRemote }
        if remote.isDeleted { return .unlinkDeletedRemote }
        if task.googleETag == remote.etag { return .unchanged }

        let localChanged = task.lastSyncedAt.map { task.modifiedAt > $0 } ?? true
        let remoteChanged = task.lastSyncedAt.map { remote.updatedAt > $0 } ?? true
        switch (localChanged, remoteChanged) {
        case (true, false): return .updateRemote
        case (false, true): return .updateLocal
        case (false, false): return .unchanged
        case (true, true):
            return task.modifiedAt >= remote.updatedAt ? .conflictPreferLocal : .conflictPreferRemote
        }
    }

    static func applyRemote(_ remote: GoogleCalendarEventSnapshot, to task: inout ManagedTask, syncedAt: Date = Date()) {
        task.title = remote.title
        task.description = remote.description
        task.startDate = remote.startDate
        task.durationMinutes = max(15, Int(remote.endDate.timeIntervalSince(remote.startDate) / 60))
        task.isAllDay = remote.isAllDay
        task.timeZoneID = remote.timeZoneID
        task.googleEventID = remote.id
        task.googleCalendarID = remote.calendarID
        task.googleETag = remote.etag
        task.googleUpdatedAt = remote.updatedAt
        task.lastSyncedAt = syncedAt
        task.modifiedAt = syncedAt
    }

    static func markRemoteSaved(_ remote: GoogleCalendarEventSnapshot, on task: inout ManagedTask, syncedAt: Date = Date()) {
        task.googleEventID = remote.id
        task.googleCalendarID = remote.calendarID
        task.googleETag = remote.etag
        task.googleUpdatedAt = remote.updatedAt
        task.lastSyncedAt = syncedAt
    }

    static func unlink(_ task: inout ManagedTask, syncedAt: Date = Date()) {
        task.googleEventID = nil
        task.googleCalendarID = nil
        task.googleETag = nil
        task.googleUpdatedAt = nil
        task.lastSyncedAt = syncedAt
    }
}

enum GoogleCalendarError: LocalizedError, Equatable {
    case notConfigured
    case notAuthorized
    case tokenExpired
    case offline
    case invalidResponse
    case api(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Google OAuth не настроен. Укажите Client ID локально в приложении."
        case .notAuthorized: return "Google Calendar не авторизован."
        case .tokenExpired: return "Сессия Google истекла, а обновить токен не удалось. Подключите аккаунт снова."
        case .offline: return "Нет подключения к интернету. Локальные изменения сохранены и будут синхронизированы позже."
        case .invalidResponse: return "Google Calendar вернул неизвестный формат ответа."
        case let .api(code, message): return "Google Calendar: ошибка \(code). \(message)"
        }
    }
}
