import Foundation

enum TaskEditScope: String, CaseIterable, Identifiable {
    case occurrence, following, series
    var id: String { rawValue }
    var title: String {
        switch self {
        case .occurrence: return "Только этот экземпляр"
        case .following: return "Этот и следующие экземпляры"
        case .series: return "Вся серия"
        }
    }
}

/// A dated template. `from` is an immutable occurrence identity, independent of a move.
/// Templates never contain versions themselves. Optional storage preserves old snapshots.
struct TaskSeriesVersion: Codable, Equatable {
    var from: Date
    var template: ManagedTask
}

enum TaskSeriesEditing {
    static func versions(of root: ManagedTask) -> [TaskSeriesVersion] {
        if let versions = root.seriesVersions, !versions.isEmpty { return versions.sorted { $0.from < $1.from } }
        guard let date = root.startDate ?? root.dueDate else { return [] }
        var template = root; template.seriesVersions = nil
        return [TaskSeriesVersion(from: date, template: template)]
    }

    static func calendar(for task: ManagedTask) -> Calendar {
        var value = PlannerCalendar.current
        value.timeZone = TimeZone(identifier: task.timeZoneID) ?? .current
        return value
    }

    // Calendar arithmetic keeps wall-clock time across DST, including multi-day moves.
    static func shifted(_ date: Date, from old: Date, to new: Date, calendar: Calendar) -> Date {
        let delta = calendar.dateComponents([.day, .hour, .minute, .second], from: old, to: new)
        return calendar.date(byAdding: delta, to: date) ?? date
    }

    static func patch(_ value: ManagedTask, from original: ManagedTask, to draft: ManagedTask) -> ManagedTask {
        var result = value
        func field<T: Equatable>(_ key: WritableKeyPath<ManagedTask, T>) {
            if original[keyPath: key] != draft[keyPath: key] { result[keyPath: key] = draft[keyPath: key] }
        }
        field(\.title); field(\.description); field(\.notes); field(\.listID); field(\.tags)
        field(\.priority); field(\.checklist); field(\.attachments); field(\.reminders)
        field(\.durationMinutes); field(\.isAllDay); field(\.timeZoneID); field(\.repeatRule)
        if original.startDate != draft.startDate {
            if let old = original.startDate, let new = draft.startDate, let date = value.startDate {
                result.startDate = shifted(date, from: old, to: new, calendar: calendar(for: draft))
            } else { result.startDate = draft.startDate }
        }
        if original.dueDate != draft.dueDate {
            if let old = original.dueDate, let new = draft.dueDate, let date = value.dueDate {
                result.dueDate = shifted(date, from: old, to: new, calendar: calendar(for: draft))
            } else { result.dueDate = draft.dueDate }
        }
        if original.startDate != draft.startDate || original.durationMinutes != draft.durationMinutes || original.plannedEndDate != draft.plannedEndDate || original.isAllDay != draft.isAllDay {
            result.plannedEndDate = result.isAllDay ? nil : result.startDate.map { $0.addingTimeInterval(Double(result.durationMinutes * 60)) }
        }
        result.seriesVersions = nil
        return result
    }

    static func apply(from original: ManagedTask, to draft: ManagedTask, scope: TaskEditScope,
                      replaceExceptions: Bool, in state: inout PersistedAppState) {
        guard scope != .occurrence else { return }
        let rootID = original.seriesRootID ?? original.id
        guard let index = state.managedTasks.firstIndex(where: { $0.id == rootID }),
              let pivot = original.occurrenceDate ?? original.startDate ?? original.dueDate else { return }
        let root = state.managedTasks[index]
        var versions = versions(of: root)
        guard !versions.isEmpty else { return }
        if scope == .following, !versions.contains(where: { $0.from == pivot }),
           let previous = versions.last(where: { $0.from <= pivot }) {
            var template = previous.template
            let anchor = template.startDate ?? template.dueDate ?? previous.from
            let date = shifted(pivot, from: previous.from, to: anchor, calendar: calendar(for: template))
            template.startDate = date
            template.dueDate = template.dueDate.map { $0.addingTimeInterval(date.timeIntervalSince(anchor)) }
            versions.append(TaskSeriesVersion(from: pivot, template: template))
            versions.sort { $0.from < $1.from }
        }
        for i in versions.indices where scope == .series || versions[i].from >= pivot {
            versions[i].template = patch(versions[i].template, from: original, to: draft)
            // A local version owns its schedule; the raw imported rule remains in the baseline.
            if var rule = versions[i].template.repeatRule, let supported = RecurrenceProjection.supportedRule(rule) {
                rule = supported; rule.sourceRule = nil; versions[i].template.repeatRule = rule
            }
        }
        if original.repeatRule != draft.repeatRule, draft.repeatRule == nil,
           let firstAffected = versions.firstIndex(where: { scope == .series || $0.from >= pivot }) {
            versions = Array(versions.prefix(firstAffected + 1))
        }
        state.managedTasks[index].seriesVersions = versions
        state.managedTasks[index].modifiedAt = Date()
        state.managedTasks[index].changeHistory.insert(TaskChange(summary: "Изменена серия: \(scope.title)"), at: 0)
        for i in state.managedTasks.indices where state.managedTasks[i].seriesRootID == rootID {
            let member = state.managedTasks[i]
            guard member.status == .active, let date = member.occurrenceDate,
                  scope == .series || date >= pivot,
                  replaceExceptions || member.id == original.id else { continue }
            var changed = patch(member, from: original, to: draft)
            changed.repeatRule = nil
            TaskEngine.updateTask(changed, in: &state)
        }
    }

    static func displayedRoot(_ root: ManagedTask) -> ManagedTask {
        guard root.status == .active, let version = root.seriesVersions?.min(by: { $0.from < $1.from }) else { return root }
        var result = version.template
        result.id = root.id; result.seriesRootID = nil; result.occurrenceDate = version.from
        result.excludedOccurrences = root.excludedOccurrences; result.seriesVersions = root.seriesVersions
        result.changeHistory = root.changeHistory; result.tickTickBaseline = root.tickTickBaseline
        result.sourceUnavailable = root.sourceUnavailable
        result.status = root.status; result.completedAt = root.completedAt; result.deletedAt = root.deletedAt
        result.modifiedAt = root.modifiedAt; result.nextOccurrenceID = root.nextOccurrenceID
        return result
    }
}
