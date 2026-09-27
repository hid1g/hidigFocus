import Foundation

enum PlannerCalendar {
    static var current: Calendar {
        var calendar = Calendar.current
        let weekday = UserDefaults.standard.integer(forKey: "planner.firstWeekday")
        if (1...7).contains(weekday) { calendar.firstWeekday = weekday }
        if let value = UserDefaults.standard.string(forKey: "planner.timeZone"), let zone = TimeZone(identifier: value) { calendar.timeZone = zone }
        return calendar
    }
    static func time(_ date: Date) -> String {
        let zone = current.timeZone
        let use24Hours = UserDefaults.standard.object(forKey: "planner.use24Hours") as? Bool != false
        let key = "hidigFocus.time.\(zone.identifier).\(use24Hours)"
        // Each thread owns its formatter; preferences form the cache key.
        let storage = Thread.current.threadDictionary
        let formatter: DateFormatter
        if let cached = storage[key] as? DateFormatter { formatter = cached }
        else {
            if storage.allKeys.filter({ ($0 as? String)?.hasPrefix("hidigFocus.time.") == true }).count >= 8 {
                for key in storage.allKeys where (key as? String)?.hasPrefix("hidigFocus.time.") == true { storage.removeObject(forKey: key) }
            }
            formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ru_RU"); formatter.timeZone = zone
            formatter.dateFormat = use24Hours ? "HH:mm" : "h:mm a"
            storage[key] = formatter
        }
        return formatter.string(from: date)
    }
}

/// Accepts exact minute input without rounding the user's deadline.
enum PlannerTimeInput {
    static func minutes(_ text: String) -> Int? {
        let components = text.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 2, components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let hour = Int(components[0]), let minute = Int(components[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }
}
