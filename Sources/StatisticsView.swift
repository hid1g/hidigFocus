import SwiftUI

struct StatisticsView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @State private var period = 7
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageTitle(
                    eyebrow: "Только факты",
                    title: "Статистика",
                    subtitle: "Показатели строятся из локальной истории hidigFocus и подключённых источников задач."
                )

                Picker("Период", selection: $period) { Text("Сегодня").tag(1); Text("7 дней").tag(7); Text("30 дней").tag(30) }.pickerStyle(.segmented).frame(width: 320)
                HStack(spacing: 14) {
                    metric(value: "\(completedInPeriod)", label: "выполнено задач за период")
                    metric(value: "\(habitChecksInPeriod)", label: "отметок привычек за период")
                    metric(value: "\(focusMinutes)", label: "минут фокусировки за период")
                }
                Text("Задачи учитываются по дате выполнения; привычки — по дневным отметкам; фокус — по завершённым рабочим сессиям. Эти показатели не складываются.").font(.caption).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    metric(
                        value: "\(activeGroupCount)",
                        label: RussianPluralizer.form(activeGroupCount, one: "активная группа", few: "активные группы", many: "активных групп")
                    )
                    metric(value: "\(store.completedTaskCount)/\(store.todayTasks.count)", label: "задач блокировки сегодня")
                    metric(value: "\(checkedHabitsToday)/\(store.habitsDueToday.count)", label: "привычек сегодня")
                    metric(
                        value: "\(store.disciplineStreak)",
                        label: "\(RussianPluralizer.form(store.disciplineStreak, one: "день", few: "дня", many: "дней")) без отключения защиты"
                    )
                }

                SoftPanel {
                        VStack(alignment: .leading, spacing: 18) {
                            SectionEyebrow(text: "Прогресс привычек")
                            if store.habits.isEmpty {
                                Text("Привычек пока нет.")
                                    .foregroundStyle(HidigPalette.secondary)
                            } else {
                                ForEach(store.habits) { habit in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(habit.name).hidigFont(size: 13, weight: .medium)
                                            Spacer()
                                            Text(habitProgress(habit).label)
                                                .hidigFont(size: 11, weight: .semibold)
                                                .foregroundStyle(HidigPalette.secondary)
                                        }
                                        GeometryReader { proxy in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(HidigPalette.canvas)
                                                Capsule().fill(HidigPalette.lettuceStrong)
                                                    .frame(width: proxy.size.width * habitProgress(habit).ratio)
                                            }
                                        }
                                        .frame(height: 7)
                                    }
                                }
                            }
                        }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 36)
            .padding(.top, 36)
            .padding(.bottom, 50)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }

    private var periodStart: Date { Calendar.current.date(byAdding: .day, value: 1-period, to: Calendar.current.startOfDay(for: Date())) ?? Date() }
    private var completedInPeriod: Int { store.state.managedTasks.filter { $0.status == .completed && ($0.completedAt ?? .distantPast) >= periodStart }.count }
    private var habitChecksInPeriod: Int {
        (0..<period).reduce(0) { sum, offset in
            let date = Calendar.current.date(byAdding: .day, value: offset, to: periodStart) ?? periodStart
            return sum + store.habits.filter { $0.isChecked(on: date) }.count
        }
    }
    private var focusMinutes: Int { store.pomodoroSessions.filter { $0.phase == .work && $0.wasCompleted && $0.endedAt >= periodStart }.reduce(0) { $0 + $1.durationSeconds } / 60 }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(value)
                .hidigFont(size: 28, weight: .bold, design: .rounded)
                .foregroundStyle(HidigPalette.forest)
            Text(label)
                .hidigFont(size: 10, weight: .semibold)
                .foregroundStyle(HidigPalette.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HidigPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 15))
    }

    private var checkedHabitsToday: Int {
        store.habitsDueToday.filter { $0.isChecked(on: Date()) }.count
    }

    private var activeGroupCount: Int {
        store.groups.filter(\.isEnabled).count
    }

    private func habitProgress(_ habit: Habit) -> (label: String, ratio: CGFloat) {
        if habit.schedule.kind == .weeklyGoal || habit.schedule.kind == .monthlyGoal {
            let value = habit.progress()
            return (
                "\(value.completed)/\(value.target)",
                min(CGFloat(value.completed) / CGFloat(max(value.target, 1)), 1)
            )
        }

        let start = Calendar.current.startOfDay(for: Date())
        let scheduledDates = (-6...0)
            .compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
            .filter { habit.isScheduled(on: $0) }
        let completed = scheduledDates.filter { habit.isChecked(on: $0) }.count
        let target = max(scheduledDates.count, 1)
        return ("\(completed)/\(scheduledDates.count)", CGFloat(completed) / CGFloat(target))
    }
}
