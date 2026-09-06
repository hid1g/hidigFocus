import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedProjectID = "all"
    @State private var showsCompletedTasks = false
    @State private var newLocalTaskTitle = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .top) {
                    PageTitle(
                        eyebrow: formattedDate,
                        title: "Сначала дела.",
                        subtitle: "Развлечения останутся за воротами, пока задачи на сегодня не завершены."
                    )
                    Spacer()
                    disciplineBadge
                }

                groupGate
                tasksSection
                habitsSection
            }
            .padding(.horizontal, 36)
            .padding(.top, 36)
            .padding(.bottom, 50)
            .frame(maxWidth: 1050, alignment: .leading)
        }
    }

    private var disciplineBadge: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(store.disciplineStreak)")
                .hidigFont(size: 29, weight: .bold, design: .rounded)
                .foregroundStyle(HidigPalette.forest)
            Text("\(RussianPluralizer.form(store.disciplineStreak, one: "день", few: "дня", many: "дней")) дисциплины")
                .hidigFont(size: 11, weight: .medium)
                .foregroundStyle(HidigPalette.secondary)
        }
        .padding(.top, 5)
    }

    private var groupGate: some View {
        VStack(spacing: 0) {
            ForEach(store.groups) { group in
                let unlocked = store.groupIsUnlocked(group)
                HStack(spacing: 18) {
                    Image(systemName: unlocked ? "lock.open.fill" : "lock.fill")
                        .hidigFont(size: 17, weight: .semibold)
                        .foregroundStyle(unlocked ? HidigPalette.lettuceStrong : HidigPalette.forest)
                        .frame(width: 42, height: 42)
                        .background(HidigPalette.lettuce.opacity(0.36))
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.name)
                            .hidigFont(size: 15, weight: .semibold)
                            .foregroundStyle(HidigPalette.forest)
                        Text(unlocked ? "Открыто" : gateDescription(for: group))
                            .hidigFont(size: 12)
                            .foregroundStyle(HidigPalette.secondary)
                    }
                    Spacer()
                    HStack(spacing: 7) {
                        ForEach(group.resources.prefix(5)) { resource in
                            Text(resource.shortLabel)
                                .hidigFont(size: 10, weight: .bold, design: .rounded)
                                .foregroundStyle(HidigPalette.forest)
                                .frame(width: 30, height: 30)
                                .background(HidigPalette.canvas)
                                .clipShape(Circle())
                                .help(resource.displayName)
                        }
                    }
                }
                .padding(.vertical, 16)
                if group.id != store.groups.last?.id {
                    Divider().overlay(HidigPalette.line.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 22)
        .background(HidigPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(HidigPalette.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    @ViewBuilder
    private var tasksSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionEyebrow(text: "Задачи сегодня")
                Spacer()
                Picker("Проект", selection: $selectedProjectID) {
                    Text("Все проекты").tag("all")
                    ForEach(projectOptions, id: \.id) { project in
                        Text(project.name).tag(project.id)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 190)
                if let date = store.state.lastSuccessfulSync {
                    Text("Обновлено \(date.formatted(date: .omitted, time: .shortened))")
                        .hidigFont(size: 10, weight: .medium)
                        .foregroundStyle(HidigPalette.secondary)
                }
                SyncButton(showTitle: false)
            }

            HStack(spacing: 9) {
                TextField("Новая задача hidigFocus", text: $newLocalTaskTitle)
                    .textFieldStyle(HidigTextFieldStyle())
                    .onSubmit(addLocalTask)
                Button("Добавить", action: addLocalTask)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(newLocalTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .frame(maxWidth: 600)

            if store.todayTasks.isEmpty {
                emptyTasks
            } else {
                taskGroupsPanel
            }
        }
    }

    private var taskGroupsPanel: some View {
        SoftPanel {
            VStack(alignment: .leading, spacing: 18) {
                if activeTaskGroups.isEmpty {
                    Text("В выбранном проекте нет незавершённых задач.")
                        .hidigFont(size: 12)
                        .foregroundStyle(HidigPalette.secondary)
                } else {
                    ForEach(activeTaskGroups) { group in
                        projectTaskSection(group)
                    }
                }

                if !completedTaskGroups.isEmpty {
                    Divider().overlay(HidigPalette.line)
                    DisclosureGroup(isExpanded: $showsCompletedTasks) {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(completedTaskGroups) { group in
                                projectTaskSection(group)
                            }
                        }
                        .padding(.top, 14)
                    } label: {
                        Text("Выполнено (\(filteredTasks.filter(\.isCompleted).count))")
                            .hidigFont(size: 12, weight: .semibold)
                            .foregroundStyle(HidigPalette.secondary)
                    }
                    .tint(HidigPalette.controlFill)
                }
            }
        }
    }

    private func projectTaskSection(_ group: TodayTaskProjectGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(group.name.uppercased())
                    .hidigFont(size: 10, weight: .bold, design: .rounded)
                    .tracking(0.7)
                    .foregroundStyle(HidigPalette.secondary)
                Spacer()
                Text("\(group.tasks.count)")
                    .hidigFont(size: 10, weight: .semibold)
                    .foregroundStyle(HidigPalette.secondary)
            }
            .padding(.bottom, 5)

            ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                taskRow(task)
                if index < group.tasks.count - 1 {
                    Divider().overlay(HidigPalette.line.opacity(0.55))
                }
            }
        }
    }

    private func taskRow(_ task: TickTickTask) -> some View {
        let isLocal = task.projectID == "hidigfocus.local"
        return HStack(alignment: .top, spacing: 13) {
            Button {
                if isLocal { store.toggleLocalTask(task.id) }
            } label: {
                HidigCheckmarkBox(isChecked: task.isCompleted, isEnabled: isLocal, size: 22)
            }
            .buttonStyle(.plain)
            .disabled(!isLocal)
            .padding(.top, 1)
            Text(task.title)
                .hidigFont(size: 14, weight: .medium)
                .strikethrough(task.isCompleted, color: HidigPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 18)
            Text(task.isCompleted ? "готово" : "в работе")
                .hidigFont(size: 10, weight: .semibold)
                .foregroundStyle(HidigPalette.secondary)
                .padding(.top, 3)
            if isLocal {
                Button { store.removeLocalTask(task.id) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(HidigIconButtonStyle(isDestructive: true))
                .help("Удалить локальную задачу")
            }
        }
        .padding(.vertical, 10)
    }

    private var projectOptions: [(id: String, name: String)] {
        Dictionary(grouping: store.todayTasks, by: \.projectID)
            .map { key, tasks in (id: key, name: tasks.first?.projectName ?? "TickTick") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var filteredTasks: [TickTickTask] {
        selectedProjectID == "all" ? store.todayTasks : store.todayTasks.filter { $0.projectID == selectedProjectID }
    }

    private var activeTaskGroups: [TodayTaskProjectGroup] {
        groupedTasks(filteredTasks.filter { !$0.isCompleted })
    }

    private var completedTaskGroups: [TodayTaskProjectGroup] {
        groupedTasks(filteredTasks.filter(\.isCompleted))
    }

    private func groupedTasks(_ tasks: [TickTickTask]) -> [TodayTaskProjectGroup] {
        Dictionary(grouping: tasks, by: \.projectID)
            .map { projectID, tasks in
                TodayTaskProjectGroup(
                    id: projectID,
                    name: tasks.first?.projectName ?? "TickTick",
                    tasks: tasks.sorted(by: taskComesFirst)
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func taskComesFirst(_ left: TickTickTask, _ right: TickTickTask) -> Bool {
        switch (left.dueDate, right.dueDate) {
        case let (leftDate?, rightDate?) where leftDate != rightDate: return leftDate < rightDate
        case (_?, nil): return true
        case (nil, _?): return false
        default: return left.title.localizedCaseInsensitiveCompare(right.title) == .orderedAscending
        }
    }

    private var emptyTasks: some View {
        SoftPanel {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .hidigFont(size: 20)
                    .foregroundStyle(HidigPalette.forest)
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.connectionState.title)
                        .hidigFont(size: 15, weight: .semibold)
                    Text(emptyTaskExplanation)
                        .hidigFont(size: 12)
                        .foregroundStyle(HidigPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Открыть настройку TickTick") {
                        store.selectedSection = .tickTick
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .padding(.top, 4)
                }
                Spacer()
            }
        }
    }

    private var habitsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionEyebrow(text: "Привычки сегодня")
                Spacer()
                Button("Все привычки") { store.selectedSection = .habits }
                    .buttonStyle(GhostButtonStyle())
            }
            SoftPanel {
                VStack(spacing: 0) {
                    ForEach(store.habits) { habit in
                        HabitCompactRow(habit: habit)
                        if habit.id != store.habits.last?.id {
                            Divider().overlay(HidigPalette.line.opacity(0.55))
                        }
                    }
                }
            }
        }
    }

    private func gateDescription(for group: BlockGroup) -> String {
        switch group.accessMode {
        case .schedule:
            return "По расписанию: \(group.schedule.timeDescription)"
        case .tasks:
            return "Осталось задач: \(store.remainingTaskCount(for: group))"
        case .scheduleAndTasks:
            return "\(group.schedule.timeDescription) · осталось задач: \(store.remainingTaskCount(for: group))"
        }
    }

    private var emptyTaskExplanation: String {
        switch store.connectionState {
        case .cliMissing: return "Добавьте задачу прямо здесь. TickTick можно подключить позже как дополнительный источник."
        case .signedOut: return "Добавьте задачу прямо здесь или войдите в TickTick для импорта задач."
        case .failed(let message): return message
        default: return "На сегодня задач нет. Добавьте локальную задачу или синхронизируйте внешний планировщик."
        }
    }

    private func addLocalTask() {
        store.addLocalTask(named: newLocalTaskTitle)
        newLocalTaskTitle = ""
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: Date())
    }
}

private struct TodayTaskProjectGroup: Identifiable {
    let id: String
    let name: String
    let tasks: [TickTickTask]
}

private struct HabitCompactRow: View {
    @EnvironmentObject private var store: AppStore
    let habit: Habit
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            Button { store.toggleHabit(habit.id) } label: {
                HidigCheckmarkBox(
                    isChecked: habit.isChecked(on: Date()),
                    isHovered: isHovered,
                    size: 27
                )
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            Text(habit.name)
                .hidigFont(size: 14, weight: .medium)
            Spacer()
            Text("серия \(RussianPluralizer.phrase(habit.currentStreak(), one: "день", few: "дня", many: "дней"))")
                .hidigFont(size: 11, weight: .semibold)
                .foregroundStyle(HidigPalette.secondary)
        }
        .padding(.vertical, 10)
    }
}
