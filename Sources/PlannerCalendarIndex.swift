import Foundation

/// A rolling window expands recurrences once and serves adjacent days without rescanning tasks.
final class PlannerCalendarIndex {
    private let radius: Int
    init(radius: Int = 14) { self.radius = radius }
    private var tasks: [ManagedTask] = []
    private var first: Date?
    private var end: Date?
    private var buckets: [Date: [ManagedTask]] = [:]
    private(set) var generation: UInt64 = 0
    private(set) var projectedByID: [UUID: ManagedTask] = [:]
    func replaceTasks(_ tasks: [ManagedTask]) { self.tasks = tasks; first = nil; end = nil; buckets.removeAll(); projectedByID.removeAll() }
    func cachedDay(_ day: Date, calendar: Calendar = PlannerCalendar.current) -> [ManagedTask]? {
        let date = calendar.startOfDay(for: day)
        guard let first, let end, date >= first && date < end else { return nil }
        return buckets[date] ?? []
    }
    func day(_ day: Date, calendar: Calendar = PlannerCalendar.current) -> [ManagedTask] {
        let date = calendar.startOfDay(for: day)
        if let first, let end, date >= first && date < end { return buckets[date] ?? [] }
        rebuild(around: date, calendar: calendar)
        return buckets[date] ?? []
    }
    private func rebuild(around date: Date, calendar: Calendar) {
        let first = calendar.date(byAdding: .day, value: -radius, to: date) ?? date
        let end = calendar.date(byAdding: .day, value: radius + 1, to: date) ?? date
        self.first = first; self.end = end; generation += 1
        buckets.removeAll(); projectedByID.removeAll()
        let existing = Set(tasks.map(\.id))
        for task in RecurrenceProjection.tasks(tasks, from: first, to: end) where task.status == .active || task.status == .completed {
            guard let start = task.startDate ?? task.dueDate else { continue }
            if !existing.contains(task.id) { projectedByID[task.id] = task }
            var day = max(first, calendar.startOfDay(for: start))
            let finish = task.isAllDay || task.startDate == nil ? calendar.date(byAdding: .day, value: 1, to: day)! : (task.calendarEndDate ?? start.addingTimeInterval(900))
            while day < end && day < finish {
                buckets[day, default: []].append(task)
                guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
                day = next
            }
        }
        for key in buckets.keys {
            buckets[key]?.sort { ($0.startDate ?? $0.dueDate ?? .distantPast) < ($1.startDate ?? $1.dueDate ?? .distantPast) }
        }
    }
}
