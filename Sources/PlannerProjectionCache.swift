import Foundation

struct PlannerProjectionKey: Equatable {
    var revision: UInt64
    var selection: TaskSidebarSelection
    var filter: PlannerFilter
    var sort: PlannerSort
    var search: String
    var calendar: Calendar
    var day: Date
    var locale: String = Locale.current.identifier
    var kind: String
    var collapsed: Set<UUID> = []
}

struct PlannerTaskSnapshot {
    var tasks: [ManagedTask]
    var rows: [PlannerTaskTree.Row] = []
    var groupedRows: [String: [PlannerTaskTree.Row]] = [:]
    var byProject: [UUID: [ManagedTask]] = [:]
    var byStage: [TaskKanbanStage: [ManagedTask]] = [:]
    var byQuadrant: [EisenhowerQuadrant: [ManagedTask]] = [:]
    var byStatus: [ManagedTaskStatus: [ManagedTask]] = [:]
}

/// Small bounded cache of immutable query results. Preparing a list also prepares
/// its tree; preparing a board groups the one ordered result, preserving card order.
final class PlannerProjectionCache {
    private struct Entry {
        var key: PlannerProjectionKey
        var value: PlannerTaskSnapshot
        var preparedAt: Date
        var validUntil: Date
    }
    private var entries: [Entry] = []
    private(set) var preparationCount = 0
    func value(for key: PlannerProjectionKey, now: Date, prepare: () -> PlannerTaskSnapshot) -> PlannerTaskSnapshot {
        if let i = entries.firstIndex(where: { $0.key == key && now >= $0.preparedAt && now < $0.validUntil }) {
            return entries[i].value
        }
        let value = prepare()
        preparationCount += 1
        var expiry = key.calendar.date(byAdding: .day, value: 1, to: key.day) ?? .distantFuture
        // An overdue section can change within the day, at the exact due instant.
        if key.kind == "list" {
            for row in value.rows where row.root.status == .active && !row.root.isAllDay {
                if let due = row.root.dueDate, due >= now { expiry = min(expiry, due.addingTimeInterval(0.000_001)) }
            }
        }
        entries.removeAll { $0.key == key || $0.key.revision != key.revision }
        if entries.count >= 16 { entries.removeFirst() }
        entries.append(Entry(key: key, value: value, preparedAt: now, validUntil: expiry))
        return value
    }
}
