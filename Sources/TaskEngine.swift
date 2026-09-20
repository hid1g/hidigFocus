import Foundation

struct TickTickImportRecord: Equatable {
    var sourceID: String
    var projectSourceID: String
    var title: String
    var description: String = ""
    var notes: String = ""
    var startDate: Date?
    var dueDate: Date?
    var completedAt: Date?
    var isAllDay = false
    var timeZoneID = TimeZone.current.identifier
    var priority: TaskPriority = .none
    var reminders: [TaskReminder] = []
    var repeatRule: TaskRepeatRule?
    var tags: [String] = []
    var checklist: [TaskChecklistItem] = []
    var sortOrder: Int64 = 0
    var plannedPomodoros = 0
    var completedPomodoros = 0
    var durationMinutes = 30
}

struct TaskImportPreview: Equatable {
    var folders: Int
    var lists: Int
    var activeTasks: Int
    var completedTasks: Int
}

enum TaskEngine {
    static func calendarDropDate(
        on day: Date,
        yOffset: CGFloat,
        hourHeight: CGFloat = 64,
        firstHour: Int = 7,
        calendar: Calendar = .current
    ) -> Date {
        let safeHeight = max(1, hourHeight)
        let rawMinute = firstHour * 60 + Int(max(0, yOffset) / safeHeight * 60)
        let minute = max(0, min(23 * 60 + 45, (rawMinute / 15) * 15))
        return calendar.date(
            bySettingHour: minute / 60,
            minute: minute % 60,
            second: 0,
            of: day
        ) ?? day
    }

    static func addTask(title rawTitle: String, listID: UUID, to state: inout PersistedAppState) -> UUID? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, state.taskLists.contains(where: { $0.id == listID }) else { return nil }
        let nextOrder = (state.managedTasks.map(\.sortOrder).max() ?? 0) + 1
        let task = ManagedTask(listID: listID, title: title, sortOrder: nextOrder)
        state.managedTasks.append(task)
        return task.id
    }

    static func updateTask(_ task: ManagedTask, in state: inout PersistedAppState, now: Date = Date()) {
        guard let index = state.managedTasks.firstIndex(where: { $0.id == task.id }) else { return }
        var value = task
        value.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.title.isEmpty else { return }
        value.modifiedAt = now
        value.changeHistory.insert(TaskChange(date: now, summary: "Задача изменена"), at: 0)
        state.managedTasks[index] = value
    }

    static func setCompleted(_ id: UUID, completed: Bool, in state: inout PersistedAppState, now: Date = Date()) {
        guard let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { return }
        state.managedTasks[index].status = completed ? .completed : .active
        state.managedTasks[index].completedAt = completed ? now : nil
        state.managedTasks[index].modifiedAt = now
        state.managedTasks[index].changeHistory.insert(
            TaskChange(date: now, summary: completed ? "Задача выполнена" : "Задача восстановлена"),
            at: 0
        )
    }

    static func trash(_ id: UUID, in state: inout PersistedAppState, now: Date = Date()) {
        guard let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { return }
        state.managedTasks[index].status = .trashed
        state.managedTasks[index].deletedAt = now
        state.managedTasks[index].modifiedAt = now
    }

    static func restoreFromTrash(_ id: UUID, in state: inout PersistedAppState, now: Date = Date()) {
        guard let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { return }
        state.managedTasks[index].status = .active
        state.managedTasks[index].deletedAt = nil
        state.managedTasks[index].modifiedAt = now
    }

    static func permanentlyDelete(_ id: UUID, in state: inout PersistedAppState) {
        state.managedTasks.removeAll { $0.id == id }
        state.pomodoroSessions.removeAll { $0.taskID == id }
        if state.activePomodoro?.taskID == id { state.activePomodoro = nil }
    }

    static func schedule(_ id: UUID, at date: Date?, durationMinutes: Int? = nil, allDay: Bool? = nil, in state: inout PersistedAppState, now: Date = Date()) {
        guard let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { return }
        state.managedTasks[index].startDate = date
        if let durationMinutes { state.managedTasks[index].durationMinutes = max(15, durationMinutes) }
        if let allDay { state.managedTasks[index].isAllDay = allDay }
        state.managedTasks[index].modifiedAt = now
    }

    static func setQuadrant(_ id: UUID, quadrant: EisenhowerQuadrant, in state: inout PersistedAppState, now: Date = Date()) {
        guard let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { return }
        state.managedTasks[index].quadrant = quadrant
        state.managedTasks[index].modifiedAt = now
    }

    static func nextOccurrence(after date: Date, for rule: TaskRepeatRule, calendar: Calendar = .current) -> Date? {
        let interval = max(1, rule.interval)
        let candidate: Date?
        switch rule.frequency {
        case .daily: candidate = calendar.date(byAdding: .day, value: interval, to: date)
        case .weekly: candidate = calendar.date(byAdding: .weekOfYear, value: interval, to: date)
        case .monthly: candidate = calendar.date(byAdding: .month, value: interval, to: date)
        case .yearly: candidate = calendar.date(byAdding: .year, value: interval, to: date)
        }
        guard let candidate else { return nil }
        if let endDate = rule.endDate, candidate > endDate { return nil }
        return candidate
    }

    static func startPomodoro(taskID: UUID, in state: inout PersistedAppState, now: Date = Date()) -> Bool {
        guard state.activePomodoro == nil,
              state.managedTasks.contains(where: { $0.id == taskID && $0.status == .active }) else { return false }
        state.activePomodoro = ActivePomodoro(
            taskID: taskID,
            startedAt: now,
            targetSeconds: max(1, state.taskSettings.workMinutes) * 60
        )
        return true
    }

    static func pausePomodoro(in state: inout PersistedAppState, now: Date = Date()) {
        guard state.activePomodoro?.pausedAt == nil else { return }
        state.activePomodoro?.pausedAt = now
    }

    static func resumePomodoro(in state: inout PersistedAppState, now: Date = Date()) {
        guard let pausedAt = state.activePomodoro?.pausedAt else { return }
        state.activePomodoro?.accumulatedPauseSeconds += max(0, Int(now.timeIntervalSince(pausedAt)))
        state.activePomodoro?.pausedAt = nil
    }

    @discardableResult
    static func finishPomodoro(in state: inout PersistedAppState, now: Date = Date(), completed: Bool = true) -> PomodoroSession? {
        guard let active = state.activePomodoro else { return nil }
        let pauseTail = active.pausedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
        let duration = max(0, Int(now.timeIntervalSince(active.startedAt)) - active.accumulatedPauseSeconds - pauseTail)
        let listID = state.managedTasks.first(where: { $0.id == active.taskID })?.listID
        let session = PomodoroSession(
            taskID: active.taskID,
            listID: listID,
            phase: active.phase,
            startedAt: active.startedAt,
            endedAt: now,
            durationSeconds: duration,
            wasCompleted: completed
        )
        state.pomodoroSessions.append(session)
        if completed, active.phase == .work,
           let index = state.managedTasks.firstIndex(where: { $0.id == active.taskID }) {
            state.managedTasks[index].completedPomodoros += 1
        }
        state.activePomodoro = nil
        return session
    }

    static func importTickTick(
        folders: [TaskFolder],
        lists: [TaskList],
        records: [TickTickImportRecord],
        into state: inout PersistedAppState,
        now: Date = Date()
    ) -> TaskImportReport {
        var report = TaskImportReport(
            startedAt: now,
            foldersFound: folders.count,
            listsFound: lists.count,
            activeTasksFound: records.filter { $0.completedAt == nil }.count,
            completedTasksFound: records.filter { $0.completedAt != nil }.count
        )

        for folder in folders where !state.taskFolders.contains(where: { $0.sourceID == folder.sourceID && folder.sourceID != nil }) {
            state.taskFolders.append(folder)
        }
        for list in lists where !state.taskLists.contains(where: { $0.sourceID == list.sourceID && list.sourceID != nil }) {
            state.taskLists.append(list)
        }
        let listBySource = Dictionary(uniqueKeysWithValues: state.taskLists.compactMap { list in
            list.sourceID.map { ($0, list.id) }
        })

        for record in records {
            let listID = listBySource[record.projectSourceID] ?? TaskList.inboxID
            if state.managedTasks.contains(where: { $0.sourceName == "TickTick" && $0.sourceID == record.sourceID }) {
                report.skipped += 1
                continue
            }
            state.managedTasks.append(ManagedTask(
                sourceID: record.sourceID,
                sourceName: "TickTick",
                sourceListID: record.projectSourceID,
                listID: listID,
                title: record.title,
                description: record.description,
                notes: record.notes,
                startDate: record.startDate,
                dueDate: record.dueDate,
                durationMinutes: record.durationMinutes,
                isAllDay: record.isAllDay,
                timeZoneID: record.timeZoneID,
                reminders: record.reminders,
                repeatRule: record.repeatRule,
                priority: record.priority,
                tags: record.tags,
                checklist: record.checklist,
                plannedPomodoros: record.plannedPomodoros,
                completedPomodoros: record.completedPomodoros,
                status: record.completedAt == nil ? .active : .completed,
                completedAt: record.completedAt,
                sortOrder: record.sortOrder
            ))
            report.imported += 1
        }
        report.finishedAt = now
        state.taskImportHistory.insert(report, at: 0)
        return report
    }

    static func completedTasks(in state: PersistedAppState) -> [ManagedTask] {
        state.managedTasks.filter { $0.status == .completed }.sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }
}
