import Foundation

extension TaskRepeatRule {
    var displayTitle: String {
        if weekdays == Set([2, 3, 4, 5, 6]) && interval == 1 { return "Каждый будний день" }
        let days = weekdays.sorted().filter { (1...7).contains($0) }
            .map { Calendar.current.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
        let base = interval == 1 ? frequency.title : "\(frequency.title), интервал: \(interval)"
        return days.isEmpty ? base : "\(base) · \(days)"
    }
}

struct PlannerInterval: Equatable {
    let id: String
    let start: Double
    let end: Double
}

struct PlannerPlacement: Equatable {
    let lane: Int
    let laneCount: Int
}

enum PlannerLayout {
    // Each connected group shares its peak column count; adjacent events reuse a lane.
    static func placements(_ intervals: [PlannerInterval]) -> [String: PlannerPlacement] {
        let sorted = intervals.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.end != $1.end { return $0.end > $1.end }
            return $0.id < $1.id
        }
        var result: [String: PlannerPlacement] = [:]
        var group: [(String, Int)] = []
        var laneEnds: [Double] = []
        var groupEnd = -Double.infinity
        func finish() {
            for (id, lane) in group { result[id] = PlannerPlacement(lane: lane, laneCount: laneEnds.count) }
        }
        for interval in sorted {
            if interval.start >= groupEnd {
                finish()
                group = []
                laneEnds = []
                groupEnd = -Double.infinity
            }
            let lane = laneEnds.firstIndex { $0 <= interval.start } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(interval.end) }
            else { laneEnds[lane] = interval.end }
            group.append((interval.id, lane))
            groupEnd = max(interval.end, groupEnd)
        }
        finish()
        return result
    }
}

extension ManagedTask {
    var isOverdue: Bool {
        guard status == .active, let dueDate else { return false }
        return dueDate < (isAllDay ? Calendar.current.startOfDay(for: Date()) : Date())
    }

    var scheduleLabel: String {
        guard let date = startDate ?? dueDate else { return "Без даты" }
        let day = date.formatted(date: .abbreviated, time: .omitted)
        if isAllDay { return "\(day) · весь день" }
        let start = date.formatted(date: .omitted, time: .shortened)
        let end = (calendarEndDate ?? dueDate)?.formatted(date: .omitted, time: .shortened)
        return "\(day) · \(start)\(end.map { "–\($0)" } ?? "")"
    }
}
