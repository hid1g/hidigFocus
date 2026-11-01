import Foundation

struct TaskScheduleSelection {
    var start: Date
    var end: Date
    var hasTime: Bool
    var durationMode = false
    var timeZoneID: String
    var repeatRule: TaskRepeatRule?
    let originalDuration: Int

    init(task: ManagedTask, now: Date = Date()) {
        start = task.startDate ?? task.dueDate ?? now
        originalDuration = max(15, task.durationMinutes)
        end = task.calendarEndDate ?? start.addingTimeInterval(Double(originalDuration * 60))
        hasTime = (task.startDate != nil || task.dueDate != nil) && !task.isAllDay
        timeZoneID = task.timeZoneID
        repeatRule = task.repeatRule
    }
    var calendar: Calendar {
        var value = PlannerCalendar.current
        value.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        return value
    }
    mutating func selectDay(_ day: Date) {
        let length = end.timeIntervalSince(start)
        let time = calendar.dateComponents([.hour, .minute], from: start)
        start = calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
        end = start.addingTimeInterval(length)
    }
    func apply(to task: inout ManagedTask) {
        let date = hasTime ? start : calendar.startOfDay(for: start)
        let duration = hasTime && durationMode ? max(15, Int(end.timeIntervalSince(start) / 60)) : originalDuration
        task.startDate = date
        task.isAllDay = !hasTime
        task.durationMinutes = duration
        task.plannedEndDate = hasTime ? (durationMode ? end : date.addingTimeInterval(Double(duration * 60))) : nil
        task.timeZoneID = timeZoneID
        task.repeatRule = repeatRule
    }
}
