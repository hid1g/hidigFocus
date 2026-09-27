import Foundation

struct TickTickImportRecord: Codable, Equatable {
    var sourceID: String
    var projectSourceID: String
    var title: String
    var parentSourceID: String?
    var childSourceIDs: [String]?
    // A fetched ancestor supplies structure, not an active planning series.
    var isHierarchyContext: Bool?
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
    var isCompleted: Bool?
    var isAbandoned: Bool?

    var completed: Bool { isCompleted ?? (completedAt != nil) }
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
        calendar: Calendar = PlannerCalendar.current
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

    static func duplicate(_ id: UUID, in state: inout PersistedAppState) -> UUID? {
        guard let original = state.managedTasks.first(where: { $0.id == id }) else { return nil }
        let now = Date()
        func detachedCopy(of task: ManagedTask, parentID: UUID?) -> ManagedTask {
            var copy = task
            copy.id = UUID()
            copy.parentTaskID = parentID
            copy.nextOccurrenceID = nil
            copy.seriesRootID = nil
            copy.occurrenceDate = nil
            copy.excludedOccurrences = nil
            copy.sourceID = nil
            copy.sourceName = nil
            copy.sourceListID = nil
            copy.tickTickBaseline = nil
            copy.googleEventID = nil
            copy.googleCalendarID = nil
            copy.googleETag = nil
            copy.googleUpdatedAt = nil
            copy.lastSyncedAt = nil
            copy.status = .active
            copy.completedAt = nil
            copy.deletedAt = nil
            copy.createdAt = now
            copy.modifiedAt = now
            copy.changeHistory = []
            copy.completedPomodoros = 0
            copy.checklist = task.checklist.map { item in
                var duplicate = item
                duplicate.id = UUID()
                duplicate.isCompleted = false
                return duplicate
            }
            copy.subtasks = task.subtasks.map { detachedCopy(of: $0, parentID: copy.id) }
            return copy
        }
        var copy = detachedCopy(of: original, parentID: original.parentTaskID)
        copy.sortOrder = (state.managedTasks.map(\.sortOrder).max() ?? 0) + 1
        state.managedTasks.append(copy)
        return copy.id
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

    static func applyEdits(from original: ManagedTask, to draft: ManagedTask, in state: inout PersistedAppState) {
        guard var latest = state.managedTasks.first(where: { $0.id == draft.id }) else { return }
        func merge<T: Equatable>(_ key: WritableKeyPath<ManagedTask, T>) {
            if original[keyPath: key] != draft[keyPath: key] { latest[keyPath: key] = draft[keyPath: key] }
        }
        merge(\.title); merge(\.description); merge(\.notes); merge(\.listID)
        merge(\.startDate); merge(\.dueDate); merge(\.durationMinutes); merge(\.isAllDay)
        merge(\.timeZoneID); merge(\.priority); merge(\.tags); merge(\.checklist)
        merge(\.repeatRule); merge(\.reminders); merge(\.attachments); merge(\.subtasks)
        merge(\.plannedEndDate); merge(\.excludedOccurrences)
        updateTask(latest, in: &state)
    }

    static func setCompleted(_ id: UUID, completed: Bool, in state: inout PersistedAppState, now: Date = Date()) {
        guard let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { return }
        let wasActive = state.managedTasks[index].status == .active
        state.managedTasks[index].status = completed ? .completed : .active
        state.managedTasks[index].completedAt = completed ? now : nil
        state.managedTasks[index].modifiedAt = now
        state.managedTasks[index].changeHistory.insert(
            TaskChange(date: now, summary: completed ? "Задача выполнена" : "Задача восстановлена"),
            at: 0
        )
        let original = state.managedTasks[index]
        // Imported RRULEs stay under the source's control until edited locally.
        if completed, wasActive, original.nextOccurrenceID == nil,
           let rule = original.repeatRule, rule.sourceRule == nil,
           let date = original.startDate ?? original.dueDate {
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(identifier: original.timeZoneID) ?? .current
            if let next = nextOccurrence(after: date, for: rule, calendar: calendar),
               let nextID = duplicate(id, in: &state) {
                schedule(nextID, at: next, durationMinutes: original.durationMinutes,
                         allDay: original.isAllDay, in: &state, now: now)
                state.managedTasks[index].nextOccurrenceID = nextID
                if let nextIndex = state.managedTasks.firstIndex(where: { $0.id == nextID }) {
                    state.managedTasks[nextIndex].seriesRootID = original.id
                    state.managedTasks[nextIndex].occurrenceDate = next
                    state.managedTasks[nextIndex].repeatRule = nil
                }
            }
        }
    }

    static func trash(_ id: UUID, in state: inout PersistedAppState, now: Date = Date()) {
        guard let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { return }
        state.managedTasks[index].status = .trashed
        state.managedTasks[index].deletedAt = now
        state.managedTasks[index].modifiedAt = now
        let childIDs = state.managedTasks.filter { $0.parentTaskID == id || $0.seriesRootID == id }.map(\.id)
        for child in childIDs { trash(child, in: &state, now: now) }
    }

    static func restoreFromTrash(_ id: UUID, in state: inout PersistedAppState, now: Date = Date()) {
        guard let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { return }
        let deletedAt = state.managedTasks[index].deletedAt
        let children = state.managedTasks.filter {
            ($0.parentTaskID == id || $0.seriesRootID == id) && $0.deletedAt == deletedAt && $0.status == .trashed
        }.map(\.id)
        for child in children { restoreFromTrash(child, in: &state, now: now) }
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
        // Scheduling controls the planned interval, never the independent deadline.
        state.managedTasks[index].plannedEndDate = date.map {
            $0.addingTimeInterval(Double(state.managedTasks[index].durationMinutes * 60))
        }
        state.managedTasks[index].modifiedAt = now
    }

    static func setQuadrant(_ id: UUID, quadrant: EisenhowerQuadrant, in state: inout PersistedAppState, now: Date = Date()) {
        guard let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { return }
        state.managedTasks[index].quadrant = quadrant
        state.managedTasks[index].modifiedAt = now
    }

    static func calendarMoveDate(from start: Date, translation: CGSize, dayWidth: CGFloat,
                                 hourHeight: CGFloat, calendar: Calendar = PlannerCalendar.current) -> Date {
        let dayShift = Int((translation.width / max(1, dayWidth)).rounded())
        let minutes = calendar.component(.hour, from: start) * 60 + calendar.component(.minute, from: start)
        let target = Double(minutes) + Double(translation.height / max(1, hourHeight)) * 60
        let snapped = max(0, min(1425, Int((target / 15).rounded()) * 15))
        let day = calendar.date(byAdding: .day, value: dayShift, to: start) ?? start
        return calendar.date(bySettingHour: snapped / 60, minute: snapped % 60, second: 0, of: day) ?? start
    }

    static func nextOccurrence(after date: Date, for rule: TaskRepeatRule, calendar: Calendar = PlannerCalendar.current) -> Date? {
        let interval = max(1, rule.interval)
        let candidate: Date?
        let weekdays = rule.weekdays.filter { (1...7).contains($0) }
        if rule.frequency == .weekly && !weekdays.isEmpty {
            guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return nil }
            // Search the rest of this week, then the next eligible interval week.
            candidate = (1...(interval * 7 + 7)).lazy.compactMap { offset -> Date? in
                guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                      weekdays.contains(calendar.component(.weekday, from: day)),
                      let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start else { return nil }
                let weeks = (calendar.dateComponents([.day], from: weekStart, to: start).day ?? 0) / 7
                return weeks % interval == 0 ? day : nil
            }.first
        } else {
            let component: Calendar.Component
            switch rule.frequency {
            case .daily: component = .day
            case .weekly: component = .weekOfYear
            case .monthly: component = .month
            case .yearly: component = .year
            }
            candidate = calendar.date(byAdding: component, value: interval, to: date)
        }
        guard let candidate else { return nil }
        if let endDate = rule.endDate,
           calendar.startOfDay(for: candidate) > calendar.startOfDay(for: endDate) { return nil }
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

    static func startFocus(taskID: UUID? = nil, phase: PomodoroPhase = .work, stopwatch: Bool = false, in state: inout PersistedAppState, now: Date = Date()) -> Bool {
        guard state.activePomodoro == nil else { return false }
        if let taskID, !state.managedTasks.contains(where: { $0.id == taskID && $0.status == .active }) { return false }
        let minutes: Int
        switch phase {
        case .work: minutes = state.taskSettings.workMinutes
        case .shortBreak: minutes = state.taskSettings.shortBreakMinutes
        case .longBreak: minutes = state.taskSettings.longBreakMinutes
        }
        state.activePomodoro = ActivePomodoro(taskID: taskID, isStopwatch: stopwatch, phase: phase, startedAt: now, targetSeconds: max(1, minutes) * 60)
        return true
    }
    static func focusElapsed(_ active: ActivePomodoro, now: Date = Date()) -> Int {
        max(0, Int((active.pausedAt ?? now).timeIntervalSince(active.startedAt)) - active.accumulatedPauseSeconds)
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
            durationSeconds: completed && active.isStopwatch != true ? min(duration, active.targetSeconds) : duration,
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
        now: Date = Date(),
        completeSnapshot: Bool = false
    ) -> TaskImportReport {
        var report = TaskImportReport(
            startedAt: now,
            foldersFound: folders.count,
            listsFound: lists.count,
            activeTasksFound: records.filter { !$0.completed && $0.isAbandoned != true }.count,
            completedTasksFound: records.filter { $0.completed }.count
        )

        for folder in folders where !state.taskFolders.contains(where: { $0.sourceID == folder.sourceID && folder.sourceID != nil }) {
            state.taskFolders.append(folder)
        }
        for list in lists {
            if let index = state.taskLists.firstIndex(where: { $0.sourceID == list.sourceID && list.sourceID != nil }) {
                state.taskLists[index].name = list.name
                state.taskLists[index].colorHex = list.colorHex
                state.taskLists[index].sortOrder = list.sortOrder
            } else { state.taskLists.append(list) }
        }
        if completeSnapshot {
            let present = Set(records.map(\.sourceID))
            for index in state.managedTasks.indices where state.managedTasks[index].sourceName == "TickTick" && state.managedTasks[index].status == .active {
                if let id = state.managedTasks[index].sourceID { state.managedTasks[index].sourceUnavailable = !present.contains(id) }
            }
        }
        let listBySource = Dictionary(uniqueKeysWithValues: state.taskLists.compactMap { list in
            list.sourceID.map { ($0, list.id) }
        })

        var taskBySource = Dictionary(state.managedTasks.enumerated().compactMap { index, task -> (String, Int)? in
            guard task.sourceName == "TickTick", let sourceID = task.sourceID else { return nil }
            return (sourceID, index)
        }, uniquingKeysWith: { first, _ in first })

        for record in records {
            let listID = listBySource[record.projectSourceID] ?? TaskList.inboxID
            if let index = taskBySource[record.sourceID] {
                let original = state.managedTasks[index]
                // Preserve local edits while the corresponding source field is unchanged.
                // On the first reconciliation the source repairs stale legacy imports.
                let previous = original.tickTickBaseline
                func changed<T: Equatable>(_ key: KeyPath<TickTickImportRecord, T>) -> Bool {
                    previous.map { $0[keyPath: key] != record[keyPath: key] } ?? true
                }
                if original.status != .trashed {
                    if previous?.parentSourceID != nil && record.parentSourceID == nil && changed(\.parentSourceID) {
                        state.managedTasks[index].parentTaskID = nil
                    }
                    if changed(\.title) { state.managedTasks[index].title = record.title }
                    if changed(\.description) { state.managedTasks[index].description = record.description }
                    if changed(\.notes) { state.managedTasks[index].notes = record.notes }
                    if changed(\.projectSourceID) {
                        state.managedTasks[index].listID = listID
                        state.managedTasks[index].sourceListID = record.projectSourceID
                    }
                    if changed(\.startDate) || changed(\.dueDate) || changed(\.durationMinutes) || changed(\.isAllDay) {
                        state.managedTasks[index].startDate = record.startDate
                        state.managedTasks[index].dueDate = record.dueDate
                        state.managedTasks[index].durationMinutes = record.durationMinutes
                        state.managedTasks[index].plannedEndDate = record.startDate.map { $0.addingTimeInterval(Double(record.durationMinutes * 60)) }
                        state.managedTasks[index].isAllDay = record.isAllDay
                    }
                    if changed(\.timeZoneID) { state.managedTasks[index].timeZoneID = record.timeZoneID }
                    if changed(\.priority) { state.managedTasks[index].priority = record.priority }
                    if changed(\.tags) { state.managedTasks[index].tags = record.tags }
                    if changed(\.repeatRule) { state.managedTasks[index].repeatRule = record.repeatRule }
                    if changed(\.reminders) { state.managedTasks[index].reminders = record.reminders }
                    if changed(\.checklist) { state.managedTasks[index].checklist = record.checklist }
                    if changed(\.sortOrder) { state.managedTasks[index].sortOrder = record.sortOrder }
                    if previous?.completed != record.completed || changed(\.completedAt) || (previous?.isAbandoned ?? false) != (record.isAbandoned ?? false) {
                        state.managedTasks[index].status = record.isAbandoned == true ? .wontDo : (record.completed ? .completed : .active)
                        state.managedTasks[index].completedAt = record.completedAt
                    }
                }
                state.managedTasks[index].sourceUnavailable = record.isHierarchyContext == true
                state.managedTasks[index].tickTickBaseline = record
                if state.managedTasks[index] != original {
                    state.managedTasks[index].modifiedAt = now
                    state.managedTasks[index].changeHistory.insert(
                        TaskChange(date: now, summary: "Обновлено из TickTick"),
                        at: 0
                    )
                    report.updated += 1
                } else {
                    report.skipped += 1
                }
                continue
            }
            taskBySource[record.sourceID] = state.managedTasks.count
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
                sourceUnavailable: record.isHierarchyContext == true,
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
                status: record.isAbandoned == true ? .wontDo : (record.completed ? .completed : .active),
                completedAt: record.completedAt,
                sortOrder: record.sortOrder,
                tickTickBaseline: record
            ))
            report.imported += 1
        }
        restoreImportedHierarchy(in: &state)
        report.finishedAt = now
        state.taskImportHistory.insert(report, at: 0)
        state.taskImportHistory = Array(state.taskImportHistory.prefix(100))
        return report
    }

    /// Resolve after all rows exist: import order and incremental snapshots cannot break links.
    static func restoreImportedHierarchy(in state: inout PersistedAppState) {
        let indices = Dictionary(state.managedTasks.enumerated().compactMap { index, task -> (String, Int)? in
            guard task.sourceName == "TickTick", let source = task.sourceID else { return nil }
            return (source, index)
        }, uniquingKeysWith: { first, _ in first })
        var parents: [String: String] = [:]
        for task in state.managedTasks where task.sourceName == "TickTick" {
            guard let source = task.sourceID, let baseline = task.tickTickBaseline else { continue }
            if let parent = baseline.parentSourceID { parents[source] = parent }
        }
        for task in state.managedTasks where task.sourceName == "TickTick" {
            guard let source = task.sourceID else { continue }
            for child in task.tickTickBaseline?.childSourceIDs ?? [] where parents[child] == nil {
                parents[child] = source
            }
        }
        for (child, parent) in parents {
            guard let childIndex = indices[child], let parentIndex = indices[parent], child != parent else { continue }
            var seen: Set<String> = [child]
            var cursor: String? = parent
            var valid = true
            while let value = cursor {
                if !seen.insert(value).inserted { valid = false; break }
                cursor = parents[value]
            }
            guard valid else { continue }
            state.managedTasks[childIndex].parentTaskID = state.managedTasks[parentIndex].id
        }
    }

    static func completedTasks(in state: PersistedAppState) -> [ManagedTask] {
        state.managedTasks.filter { $0.status == .completed }.sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }
}
