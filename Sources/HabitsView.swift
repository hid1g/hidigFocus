import SwiftUI

struct HabitsView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @State private var weekOffset = 0
    @State private var draggedHabitID: UUID?
    @State private var editorTarget: HabitEditorTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 14) {
                    PageTitle(
                        eyebrow: "Ритм без наказания",
                        title: "Привычки",
                        subtitle: "Создавайте ежедневные, интервальные и гибкие цели. Серия учитывает только запланированный ритм."
                    )
                    weekNavigation
                }

                Button {
                    editorTarget = HabitEditorTarget(habit: Habit(name: ""), isNew: true)
                } label: {
                    Label("Новая привычка", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle())

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
        .sheet(item: $editorTarget) { target in
            HabitEditorSheet(target: target, isPresented: Binding(
                get: { editorTarget != nil },
                set: { if !$0 { editorTarget = nil } }
            ))
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
            Color.clear.frame(width: 64)
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
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(habit.name)
                        .hidigFont(size: 14, weight: .semibold)
                    if habit.priority != .normal {
                        Text(habit.priority.title)
                            .hidigFont(size: 9, weight: .bold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(HidigPalette.lettuce)
                            .clipShape(Capsule())
                    }
                }
                Text(habit.schedule.summary)
                    .hidigFont(size: 10, weight: .medium)
                    .foregroundStyle(HidigPalette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(visibleDates, id: \.self) { date in
                let checked = habit.isChecked(on: date)
                let scheduled = habit.isScheduled(on: date)
                let editable = isEditable(date) && scheduled
                HabitDayCheckButton(
                    isChecked: checked,
                    isEditable: editable,
                    isScheduled: scheduled,
                    action: { store.toggleHabit(habit.id, on: date) }
                )
                .frame(width: 46)
            }
            VStack(spacing: 2) {
                Text("\(habit.currentStreak())")
                    .hidigFont(size: 18, weight: .bold, design: .rounded)
                if !habit.streakUnit.isEmpty {
                    Text(habit.streakUnit)
                        .hidigFont(size: 9, weight: .semibold)
                        .foregroundStyle(HidigPalette.secondary)
                }
            }
            .frame(width: 62)
            Button {
                editorTarget = HabitEditorTarget(habit: habit, isNew: false)
            } label: { Image(systemName: "pencil") }
                .buttonStyle(HidigIconButtonStyle())
                .frame(width: 32)
                .help("Редактировать привычку")
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
}

private struct HabitEditorTarget: Identifiable {
    let habit: Habit
    let isNew: Bool
    var id: UUID { habit.id }
}

private struct HabitEditorSheet: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let target: HabitEditorTarget
    @Binding var isPresented: Bool
    @State private var habit: Habit

    private let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]

    init(target: HabitEditorTarget, isPresented: Binding<Bool>) {
        self.target = target
        _isPresented = isPresented
        _habit = State(initialValue: target.habit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                Text(target.isNew ? "Новая привычка" : "Настройки привычки")
                    .hidigFont(size: 25, weight: .bold, design: .rounded)
                Text("Настройте важность и реальный ритм выполнения.")
                    .hidigFont(size: 11)
                    .foregroundStyle(HidigPalette.secondary)
            }
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    editorSection("Название") {
                        TextField("Например, Медитация", text: $habit.name)
                            .textFieldStyle(HidigTextFieldStyle())
                    }

                    editorSection("Приоритет") {
                        HStack(spacing: 8) {
                            ForEach(HabitPriority.allCases) { priority in
                                choiceButton(priority.title, selected: habit.priority == priority) {
                                    habit.priority = priority
                                }
                            }
                        }
                    }

                    editorSection("Регулярность") {
                        VStack(alignment: .leading, spacing: 14) {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                ForEach(HabitScheduleKind.allCases) { kind in
                                    choiceButton(kind.title, selected: habit.schedule.kind == kind) {
                                        selectScheduleKind(kind)
                                    }
                                }
                            }
                            scheduleEditor
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack {
                Button("Отмена") { isPresented = false }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button(target.isNew ? "Создать" : "Сохранить") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(habit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.top, 20)
        }
        .padding(26)
        .frame(width: 560, height: 640)
        .foregroundStyle(HidigPalette.forest)
        .background(HidigPalette.canvas)
    }

    @ViewBuilder
    private var scheduleEditor: some View {
        switch habit.schedule.kind {
        case .weekdays:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    presetButton("Каждый день", days: Set(1...7))
                    presetButton("Будни", days: Set(2...6))
                    presetButton("Выходные", days: Set([1, 7]))
                }
                HStack(spacing: 7) {
                    ForEach(orderedWeekdays, id: \.self) { weekday in
                        choiceButton(shortWeekday(weekday), selected: habit.schedule.weekdays.contains(weekday)) {
                            toggleWeekday(weekday)
                        }
                    }
                }
                Text("Можно выбрать любое сочетание дней недели.")
                    .hidigFont(size: 10)
                    .foregroundStyle(HidigPalette.secondary)
            }
        case .interval:
            stepperCard(
                title: "Каждые \(RussianPluralizer.phrase(habit.schedule.intervalDays, one: "день", few: "дня", many: "дней"))",
                value: $habit.schedule.intervalDays,
                range: 1...30,
                hint: "Отсчёт начинается с даты создания привычки."
            )
        case .weeklyGoal:
            stepperCard(
                title: "\(RussianPluralizer.phrase(habit.schedule.targetCount, one: "раз", few: "раза", many: "раз")) в неделю",
                value: $habit.schedule.targetCount,
                range: 1...7,
                hint: "Выполняйте в любые дни. Серия считается по завершённым неделям."
            )
        case .monthlyGoal:
            stepperCard(
                title: "\(RussianPluralizer.phrase(habit.schedule.targetCount, one: "раз", few: "раза", many: "раз")) в месяц",
                value: $habit.schedule.targetCount,
                range: 1...30,
                hint: "Выполняйте в любые дни. Серия считается по завершённым месяцам."
            )
        }
    }

    private func editorSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionEyebrow(text: title)
            content()
        }
        .padding(16)
        .background(HidigPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func choiceButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .hidigFont(size: 11, weight: .semibold)
                Text(title)
                    .hidigFont(size: 11, weight: .semibold)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(SelectionRowButtonStyle(isSelected: selected))
    }

    private func presetButton(_ title: String, days: Set<Int>) -> some View {
        choiceButton(title, selected: habit.schedule.weekdays == days) {
            habit.schedule.weekdays = days
        }
    }

    private func stepperCard(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Stepper(value: value, in: range) {
                Text(title).hidigFont(size: 13, weight: .semibold)
            }
            Text(hint)
                .hidigFont(size: 10)
                .foregroundStyle(HidigPalette.secondary)
        }
        .padding(14)
        .background(HidigPalette.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func toggleWeekday(_ weekday: Int) {
        if habit.schedule.weekdays.contains(weekday) {
            if habit.schedule.weekdays.count > 1 { habit.schedule.weekdays.remove(weekday) }
        } else {
            habit.schedule.weekdays.insert(weekday)
        }
    }

    private func selectScheduleKind(_ kind: HabitScheduleKind) {
        habit.schedule.kind = kind
        habit.schedule.intervalDays = max(1, min(habit.schedule.intervalDays, 30))
        let maximum = kind == .weeklyGoal ? 7 : 30
        habit.schedule.targetCount = max(1, min(habit.schedule.targetCount, maximum))
    }

    private func shortWeekday(_ weekday: Int) -> String {
        [1: "Вс", 2: "Пн", 3: "Вт", 4: "Ср", 5: "Чт", 6: "Пт", 7: "Сб"][weekday] ?? ""
    }

    private func save() {
        if target.isNew {
            store.addHabit(habit)
        } else {
            store.updateHabit(habit)
        }
        isPresented = false
    }
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
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let isChecked: Bool
    let isEditable: Bool
    let isScheduled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Group {
            if isScheduled {
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
            } else {
                Image(systemName: "minus")
                    .hidigFont(size: 10, weight: .semibold)
                    .foregroundStyle(HidigPalette.secondary.opacity(0.55))
                    .frame(width: 28, height: 28)
                    .background(HidigPalette.disabledFill.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .help("Привычка не запланирована на этот день")
            }
        }
    }
}
