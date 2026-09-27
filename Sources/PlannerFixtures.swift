import Foundation

/// Explicit QA fixtures, never loaded into the normal application data directory.
enum PlannerFixtures {
    static func make(count: Int, now: Date = Date()) -> PersistedAppState {
        var state = PersistedAppState()
        state.protectionEnabled = false
        let day = Calendar.current.startOfDay(for: now)
        state.managedTasks = (0..<max(1, count)).map { index in
            let shift = index < 20 ? 0 : (index % 61) - 30
            let date = Calendar.current.date(byAdding: .day, value: shift, to: day) ?? day
            let start = Calendar.current.date(bySettingHour: 7 + (index % 12), minute: (index % 4) * 15, second: 0, of: date) ?? date
            return ManagedTask(title: index == 0 ? "morning routine" : "Задача \(index + 1)", description: index % 3 == 0 && index != 0 ? "Тестовое описание" : "", startDate: start, durationMinutes: index % 4 == 0 ? 90 : 30, isAllDay: index > 0 && index < 9,
                repeatRule: index % 100 == 0 ? TaskRepeatRule(frequency: .daily) : nil,
                priority: TaskPriority.allCases[index % TaskPriority.allCases.count], tags: index % 5 == 0 ? ["проверка"] : [], checklist: index == 0 ? [TaskChecklistItem(title: "Mobility train"), TaskChecklistItem(title: "Take suppls")] : [], status: index % 7 == 0 && index != 0 ? .completed : .active, completedAt: index % 7 == 0 && index != 0 ? now : nil, sortOrder: Int64(index))
        }
        return state
    }
}
