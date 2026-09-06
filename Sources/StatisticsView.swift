import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                PageTitle(
                    eyebrow: "Только факты",
                    title: "Статистика",
                    subtitle: "Показатели строятся из локальной истории hidigFocus и подключённых источников задач."
                )

                HStack(spacing: 14) {
                    metric(
                        value: "\(store.disciplineStreak)",
                        label: "\(RussianPluralizer.form(store.disciplineStreak, one: "день", few: "дня", many: "дней")) дисциплины"
                    )
                    metric(value: "\(store.completedTaskCount)/\(store.todayTasks.count)", label: "задач сегодня")
                    metric(value: "\(checkedHabitsToday)/\(store.habits.count)", label: "привычек сегодня")
                    metric(value: "\(closedAppsThisWeek)", label: "закрытий приложений за 7 дней")
                }

                SoftPanel {
                        VStack(alignment: .leading, spacing: 18) {
                            SectionEyebrow(text: "Привычки за 7 дней")
                            if store.habits.isEmpty {
                                Text("Привычек пока нет.")
                                    .foregroundStyle(HidigPalette.secondary)
                            } else {
                                ForEach(store.habits) { habit in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(habit.name).hidigFont(size: 13, weight: .medium)
                                            Spacer()
                                            Text("\(habitWeekCount(habit))/7")
                                                .hidigFont(size: 11, weight: .semibold)
                                                .foregroundStyle(HidigPalette.secondary)
                                        }
                                        GeometryReader { proxy in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(HidigPalette.canvas)
                                                Capsule().fill(HidigPalette.lettuceStrong)
                                                    .frame(width: proxy.size.width * CGFloat(habitWeekCount(habit)) / 7)
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
        store.habits.filter { $0.isChecked(on: Date()) }.count
    }

    private var closedAppsThisWeek: Int {
        store.events(inLastDays: 7, kind: .applicationClosed).count
    }

    private func habitWeekCount(_ habit: Habit) -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        return (-6...0).compactMap { Calendar.current.date(byAdding: .day, value: $0, to: start) }
            .filter { habit.isChecked(on: $0) }
            .count
    }
}
