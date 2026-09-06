import SwiftUI

struct HabitsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var newHabitName = ""
    @State private var weekOffset = 0
    @State private var draggedHabitID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    PageTitle(
                        eyebrow: "Ритм без наказания",
                        title: "Привычки",
                        subtitle: "Вчерашнюю отметку можно восстановить. Пропуск двух дней и более уже не возвращается в серию."
                    )
                    weekNavigation
                }

                HStack(spacing: 10) {
                    TextField("Новая привычка", text: $newHabitName)
                        .textFieldStyle(HidigTextFieldStyle())
                        .onSubmit(addHabit)
                    Button("Добавить", action: addHabit).buttonStyle(PrimaryButtonStyle())
                }
                .frame(maxWidth: 560)

                VStack(spacing: 0) {
                    habitHeader
                    Divider().overlay(HidigPalette.line)
                    if store.habits.isEmpty {
                        Text("Добавьте первую привычку — она появится здесь.")
                            .hidigFont(size: 13)
                            .foregroundStyle(HidigPalette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 28)
                    } else {
                        ForEach(store.habits) { habit in
                            habitRow(habit)
                                .onDrag {
                                    draggedHabitID = habit.id
                                    return NSItemProvider(object: habit.id.uuidString as NSString)
                                }
                                .onDrop(
                                    of: [.text],
                                    delegate: HabitDropDelegate(
                                        targetHabitID: habit.id,
                                        draggedHabitID: $draggedHabitID,
                                        store: store
                                    )
                                )
                            if habit.id != store.habits.last?.id { Divider().overlay(HidigPalette.line.opacity(0.55)) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .foregroundStyle(HidigPalette.forest)
                .background(HidigPalette.surface)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(HidigPalette.line))
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 36)
            .frame(maxWidth: 1100, alignment: .leading)
        }
    }

    private var weekNavigation: some View {
        HStack(spacing: 8) {
            Button { weekOffset -= 1 } label: { Label("Предыдущая", systemImage: "chevron.left") }
            Button("Сегодня") { weekOffset = 0 }
            Button { weekOffset += 1 } label: { Label("Следующая", systemImage: "chevron.right") }
            Text(visibleRangeTitle)
                .hidigFont(size: 12, weight: .semibold)
                .foregroundStyle(HidigPalette.secondary)
                .padding(.leading, 6)
        }
        .buttonStyle(SecondaryButtonStyle())
    }

    private var habitHeader: some View {
        HStack {
            Text("Привычка").frame(maxWidth: .infinity, alignment: .leading)
            ForEach(visibleDates, id: \.self) { date in
                VStack(spacing: 2) {
                    Text(weekday(date))
                    Text(day(date)).foregroundStyle(HidigPalette.secondary)
                }
                .frame(width: 46)
            }
            Text("Серия").frame(width: 62)
            Color.clear.frame(width: 28)
        }
        .hidigFont(size: 10, weight: .semibold)
        .foregroundStyle(HidigPalette.secondary)
        .padding(.vertical, 12)
    }

    private func habitRow(_ habit: Habit) -> some View {
        HStack {
            Image(systemName: "line.3.horizontal")
                .hidigFont(size: 11, weight: .semibold)
                .foregroundStyle(HidigPalette.secondary)
                .frame(width: 18)
                .help("Перетащите, чтобы изменить порядок")
            Text(habit.name)
                .hidigFont(size: 14, weight: .semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(visibleDates, id: \.self) { date in
                let checked = habit.isChecked(on: date)
                let editable = isEditable(date)
                HabitDayCheckButton(
                    isChecked: checked,
                    isEditable: editable,
                    action: { store.toggleHabit(habit.id, on: date) }
                )
                .frame(width: 46)
            }
            Text("\(habit.currentStreak())")
                .hidigFont(size: 18, weight: .bold, design: .rounded)
                .frame(width: 62)
            Button { store.removeHabit(habit.id) } label: { Image(systemName: "trash") }
                .buttonStyle(HidigIconButtonStyle(isDestructive: true))
                .frame(width: 32)
                .help("Удалить привычку")
        }
        .padding(.vertical, 14)
    }

    private var visibleDates: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let base = calendar.date(byAdding: .day, value: weekOffset * 7, to: today) ?? today
        return (-6...0).compactMap { calendar.date(byAdding: .day, value: $0, to: base) }
    }

    private func isEditable(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        return target == today || target == yesterday
    }

    private func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EE"
        return formatter.string(from: date).replacingOccurrences(of: ".", with: "").uppercased()
    }

    private func day(_ date: Date) -> String { String(Calendar.current.component(.day, from: date)) }
    private var visibleRangeTitle: String {
        guard let first = visibleDates.first, let last = visibleDates.last else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "d MMM"
        return "\(formatter.string(from: first)) — \(formatter.string(from: last))"
    }
    private func addHabit() { store.addHabit(named: newHabitName); newHabitName = "" }
}

private struct HabitDropDelegate: DropDelegate {
    let targetHabitID: UUID
    @Binding var draggedHabitID: UUID?
    let store: AppStore

    func dropEntered(info: DropInfo) {
        guard let draggedHabitID, draggedHabitID != targetHabitID else { return }
        store.moveHabit(draggedHabitID, relativeTo: targetHabitID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedHabitID = nil
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}

private struct HabitDayCheckButton: View {
    let isChecked: Bool
    let isEditable: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HidigCheckmarkBox(
                isChecked: isChecked,
                isEnabled: isEditable,
                isHovered: isHovered,
                size: 28
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEditable)
        .onHover { isHovered = $0 }
        .help(isEditable ? "Изменить отметку" : "Редактировать можно только сегодня и вчера")
    }
}
