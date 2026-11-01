import Foundation

struct PlannerDaySnapshot {
    let tasks: [ManagedTask]
    let events: [GoogleCalendarEventSnapshot]
    let allDayTasks: [ManagedTask]
    let timedTasks: [ManagedTask]
    let allDayEvents: [GoogleCalendarEventSnapshot]
    let timedEvents: [GoogleCalendarEventSnapshot]
    let intervals: [String: PlannerInterval]
    let placements: [String: PlannerPlacement]

    init(tasks: [ManagedTask], events: [GoogleCalendarEventSnapshot], day: Date, calendar: Calendar) {
        self.tasks = tasks; self.events = events
        allDayTasks = tasks.filter { $0.isAllDay || $0.startDate == nil }
        timedTasks = tasks.filter { !$0.isAllDay && $0.startDate != nil }
        allDayEvents = events.filter(\.isAllDay)
        timedEvents = events.filter { !$0.isAllDay }
        let end = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        func minute(_ date: Date) -> Double {
            if date <= day { return 0 }
            if date >= end { return 1440 }
            let components = calendar.dateComponents([.hour, .minute], from: date)
            return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
        }
        var slots: [String: PlannerInterval] = [:]
        var ordered: [PlannerInterval] = []
        for task in timedTasks {
            let start = task.startDate ?? task.dueDate ?? day
            let first = minute(start)
            let slot = PlannerInterval(id: task.id.uuidString, start: first,
                end: min(1440, max(first + 1, minute(task.calendarEndDate ?? start.addingTimeInterval(Double(task.durationMinutes * 60))))))
            slots[slot.id] = slot; ordered.append(slot)
        }
        for event in timedEvents {
            let first = minute(event.startDate)
            let slot = PlannerInterval(id: event.identity, start: first, end: minute(event.endDate))
            slots[slot.id] = slot
            ordered.append(PlannerInterval(id: slot.id, start: slot.start, end: max(slot.start + 1, slot.end)))
        }
        intervals = slots
        placements = PlannerLayout.placements(ordered)
    }
}

struct PlannerDaySnapshotKey: Equatable {
    let taskRevision: UInt64
    let calendarRevision: UInt64
    let eventRevision: UInt64
    let day: Date
    let calendar: Calendar
    let filter: PlannerFilter
    let search: String
}
