import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GroupsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showsNewGroup = false
    @State private var showsAddDomain = false
    @State private var resourceToEdit: ResourceEditTarget?
    @State private var groupToRename: GroupRenameTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .bottom) {
                PageTitle(
                    eyebrow: "Правила доступа",
                    title: "Группы",
                    subtitle: "Каждая группа объединяет сайты и приложения с одним условием открытия."
                )
                Spacer()
                Button("Новая группа") { showsNewGroup = true }
                    .buttonStyle(PrimaryButtonStyle())
            }

            HStack(alignment: .top, spacing: 22) {
                groupsList.frame(width: 255)
                if let group = store.selectedGroup {
                    groupEditor(group)
                } else {
                    SoftPanel { Text("Добавьте первую группу.") }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 36)
        .padding(.top, 36)
        .padding(.bottom, 38)
        .sheet(isPresented: $showsNewGroup) { NewGroupSheet(isPresented: $showsNewGroup) }
        .sheet(isPresented: $showsAddDomain) {
            if let groupID = store.selectedGroupID {
                AddDomainSheet(groupID: groupID, isPresented: $showsAddDomain)
            }
        }
        .sheet(item: $resourceToEdit) { target in
            EditResourceSheet(target: target, isPresented: Binding(
                get: { resourceToEdit != nil },
                set: { if !$0 { resourceToEdit = nil } }
            ))
        }
        .sheet(item: $groupToRename) { target in
            RenameGroupSheet(target: target, isPresented: Binding(
                get: { groupToRename != nil },
                set: { if !$0 { groupToRename = nil } }
            ))
        }
    }

    private var groupsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(store.groups) { group in
                Button {
                    store.selectedGroupID = group.id
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: store.groupIsUnlocked(group) ? "lock.open" : "lock")
                            .frame(width: 17)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(group.name).lineLimit(1)
                            Text(RussianPluralizer.phrase(group.resources.count, one: "ресурс", few: "ресурса", many: "ресурсов"))
                                .hidigFont(size: 10)
                                .foregroundStyle(HidigPalette.secondary)
                        }
                        Spacer()
                    }
                    .hidigFont(size: 13, weight: .medium)
                    .foregroundStyle(HidigPalette.forest)
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SelectionRowButtonStyle(isSelected: store.selectedGroupID == group.id))
                .contextMenu {
                    Button("Переименовать") {
                        groupToRename = GroupRenameTarget(group: group)
                    }
                    Button(group.isEnabled ? "Отключить" : "Включить") {
                        store.setGroupEnabled(group.id, value: !group.isEnabled)
                    }
                    Divider()
                    Button("Удалить", role: .destructive) {
                        store.removeGroup(group.id)
                    }
                }
            }
        }
    }

    private func groupEditor(_ group: BlockGroup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(group.name)
                            .hidigFont(size: 24, weight: .bold, design: .rounded)
                            .foregroundStyle(HidigPalette.forest)
                        Text(group.isEnabled
                            ? (store.groupIsUnlocked(group) ? "Сейчас открыта" : "Сейчас закрыта")
                            : "Черновик — правило не применяется")
                            .hidigFont(size: 12, weight: .semibold)
                            .foregroundStyle(HidigPalette.secondary)
                    }
                    Spacer()
                    Button {
                        groupToRename = GroupRenameTarget(group: group)
                    } label: {
                        Label("Переименовать", systemImage: "pencil")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help("Переименовать группу")
                    if group.isEnabled {
                        Toggle("Правило активно", isOn: Binding(
                            get: { group.isEnabled },
                            set: { store.setGroupEnabled(group.id, value: $0) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .hidigFont(size: 11, weight: .semibold)
                    } else {
                        Text("Не применяется")
                            .hidigFont(size: 11, weight: .semibold)
                            .foregroundStyle(HidigPalette.secondary)
                    }
                }

                Divider().overlay(HidigPalette.line)

                if !group.isEnabled {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Группа сохранена как черновик")
                                .hidigFont(size: 13, weight: .semibold)
                            Text("Сайты и приложения не блокируются, пока вы не примените правило.")
                                .hidigFont(size: 11)
                                .foregroundStyle(HidigPalette.secondary)
                        }
                        Spacer()
                        Button("Применить и включить") {
                            store.setGroupEnabled(group.id, value: true)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(14)
                    .background(HidigPalette.canvas)
                    .overlay(RoundedRectangle(cornerRadius: 13).stroke(HidigPalette.line))
                    .clipShape(RoundedRectangle(cornerRadius: 13))
                }

                VStack(alignment: .leading, spacing: 13) {
                    SectionEyebrow(text: "Что закрываем")
                    if group.resources.isEmpty {
                        Text("В группе пока нет сайтов или приложений.")
                            .hidigFont(size: 13)
                            .foregroundStyle(HidigPalette.secondary)
                    }
                    ForEach(group.resources) { resource in
                        HStack(spacing: 13) {
                            Text(resource.shortLabel)
                                .hidigFont(size: 10, weight: .bold, design: .rounded)
                                .frame(width: 34, height: 34)
                                .background(HidigPalette.lettuce.opacity(0.3))
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(resource.displayName).hidigFont(size: 13, weight: .medium)
                                Text(resource.identifier)
                                    .hidigFont(size: 10)
                                    .foregroundStyle(HidigPalette.secondary)
                            }
                            Spacer()
                            Button {
                                resourceToEdit = ResourceEditTarget(groupID: group.id, resource: resource)
                            } label: { Image(systemName: "pencil") }
                                .buttonStyle(HidigIconButtonStyle())
                                .help("Редактировать")
                            Button {
                                store.removeResource(resource.id, from: group.id)
                            } label: { Image(systemName: "xmark") }
                                .buttonStyle(HidigIconButtonStyle())
                                .help("Удалить")
                        }
                        .padding(.vertical, 5)
                    }
                    HStack {
                        Button("Добавить сайт") { showsAddDomain = true }
                            .buttonStyle(SecondaryButtonStyle())
                        Button("Добавить приложение") { chooseApplication(for: group.id) }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }

                Divider().overlay(HidigPalette.line)

                VStack(alignment: .leading, spacing: 13) {
                    SectionEyebrow(text: "Условие открытия")
                    AccessModeSelector(selected: group.accessMode) {
                        store.setGroupAccessMode(group.id, mode: $0)
                    }

                    if group.accessMode.usesSchedule {
                        BlockScheduleEditor(schedule: group.schedule) {
                            store.updateGroupSchedule(group.id, schedule: $0)
                        }
                    }

                    if group.accessMode.usesTasks {
                        TaskRequirementSelector(
                            requiresAllTasks: group.requiresAllTodayTasks,
                            onChange: { store.setGroupUsesAllTasks(group.id, value: $0) }
                        )

                        if !group.requiresAllTodayTasks {
                            if store.todayTasks.isEmpty {
                                Text("Добавьте задачу hidigFocus или подключите TickTick.")
                                    .hidigFont(size: 12)
                                    .foregroundStyle(HidigPalette.secondary)
                            } else {
                                TaskSelectionList(group: group)
                            }
                        }
                        Text("Если нужных задач нет, группа остаётся закрытой. Локальные задачи работают без подключения TickTick.")
                                .hidigFont(size: 12)
                                .foregroundStyle(HidigPalette.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button("Удалить группу", role: .destructive) {
                        store.removeGroup(group.id)
                    }
                    .buttonStyle(DestructiveButtonStyle())
                    .help("Удалить группу")
                }
            }
            .padding(24)
        }
        .background(HidigPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func chooseApplication(for groupID: UUID) {
        let panel = NSOpenPanel()
        panel.title = "Выберите приложение"
        panel.prompt = "Добавить"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.addApplication(at: url, to: groupID)
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}

private struct ResourceEditTarget: Identifiable {
    let groupID: UUID
    let resource: BlockedResource
    var id: UUID { resource.id }
}

private struct GroupRenameTarget: Identifiable {
    let group: BlockGroup
    var id: UUID { group.id }
}

private enum TaskListFilter: String, CaseIterable, Identifiable {
    case all
    case active
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "Все"
        case .active: return "Активные"
        case .completed: return "Выполненные"
        }
    }
}

private struct TaskSelectionList: View {
    @EnvironmentObject private var store: AppStore
    let group: BlockGroup

    @State private var search = ""
    @State private var filter = TaskListFilter.active

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("Поиск задачи", text: $search)
                    .textFieldStyle(HidigTextFieldStyle())
                SyncButton(showTitle: false)
            }

            HStack(spacing: 6) {
                ForEach(TaskListFilter.allCases) { option in
                    Button { filter = option } label: {
                        Text(option.title)
                            .hidigFont(size: 11, weight: .semibold)
                            .padding(.horizontal, 10)
                            .frame(minHeight: 32)
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(SelectionRowButtonStyle(isSelected: filter == option))
                }
                Spacer()
                Text("Выбрано: \(group.requiredTaskIDs.count)")
                    .hidigFont(size: 10, weight: .semibold)
                    .foregroundStyle(HidigPalette.secondary)
            }

            HStack(spacing: 7) {
                Button("Выбрать показанные") { selectVisibleTasks() }
                    .buttonStyle(GhostButtonStyle())
                Button("Снять выбор") {
                    store.setRequiredTasks([], in: group.id)
                }
                .buttonStyle(GhostButtonStyle())
                .disabled(group.requiredTaskIDs.isEmpty)
            }

            if groupedTasks.isEmpty {
                Text("По заданным условиям задач нет.")
                    .hidigFont(size: 11)
                    .foregroundStyle(HidigPalette.secondary)
                    .padding(.vertical, 10)
            } else {
                ForEach(groupedTasks, id: \.project) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(section.project.uppercased())
                                .hidigFont(size: 10, weight: .bold, design: .rounded)
                                .tracking(0.7)
                                .foregroundStyle(HidigPalette.secondary)
                            Spacer()
                            Text("\(section.tasks.count)")
                                .hidigFont(size: 9, weight: .semibold)
                                .foregroundStyle(HidigPalette.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.top, 8)

                        ForEach(section.tasks) { task in
                            HidigCheckboxRow(
                                title: task.title,
                                isOn: group.requiredTaskIDs.contains(task.id),
                                action: { store.toggleRequiredTask(task.id, in: group.id) }
                            )
                        }
                    }
                }
            }
        }
    }

    private var filteredTasks: [TickTickTask] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.todayTasks.filter { task in
            let matchesStatus: Bool
            switch filter {
            case .all: matchesStatus = true
            case .active: matchesStatus = !task.isCompleted
            case .completed: matchesStatus = task.isCompleted
            }
            let matchesSearch = query.isEmpty
                || task.title.localizedCaseInsensitiveContains(query)
                || task.projectName.localizedCaseInsensitiveContains(query)
            return matchesStatus && matchesSearch
        }
    }

    private var groupedTasks: [(project: String, tasks: [TickTickTask])] {
        Dictionary(grouping: filteredTasks) { task in
            task.projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Без проекта"
                : task.projectName
        }
        .map { project, tasks in
            (project: project, tasks: tasks.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        }
        .sorted { $0.project.localizedCaseInsensitiveCompare($1.project) == .orderedAscending }
    }

    private func selectVisibleTasks() {
        let selected = group.requiredTaskIDs.union(filteredTasks.map(\.id))
        store.setRequiredTasks(selected, in: group.id)
    }
}

private struct AccessModeSelector: View {
    let selected: GroupAccessMode
    let onChange: (GroupAccessMode) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(GroupAccessMode.allCases) { mode in
                Button { onChange(mode) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Image(systemName: icon(for: mode))
                            .hidigFont(size: 14, weight: .semibold)
                        Text(mode.title)
                            .hidigFont(size: 11, weight: .semibold)
                            .lineLimit(2)
                    }
                    .foregroundStyle(HidigPalette.forest)
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SelectionRowButtonStyle(isSelected: selected == mode))
            }
        }
    }

    private func icon(for mode: GroupAccessMode) -> String {
        switch mode {
        case .schedule: return "clock"
        case .tasks: return "checkmark.circle"
        case .scheduleAndTasks: return "clock.badge.checkmark"
        }
    }
}

private struct BlockScheduleEditor: View {
    let schedule: BlockSchedule
    let onChange: (BlockSchedule) -> Void

    private let orderedWeekdays = [2, 3, 4, 5, 6, 7, 1]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Расписание блокировки")
                    .hidigFont(size: 12, weight: .semibold)
                Spacer()
                Toggle("Весь день", isOn: allDayBinding)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }

            if !schedule.isAllDay {
                HStack(spacing: 12) {
                    timeField("С", minute: startBinding)
                    timeField("До", minute: endBinding)
                    Spacer()
                }
            }

            HStack(spacing: 7) {
                presetButton("Каждый день", days: Set(1...7))
                presetButton("Будни", days: Set(2...6))
                presetButton("Выходные", days: [1, 7])
            }

            HStack(spacing: 6) {
                ForEach(orderedWeekdays, id: \.self) { weekday in
                    Button {
                        var value = schedule
                        if value.weekdays.contains(weekday) {
                            if value.weekdays.count > 1 { value.weekdays.remove(weekday) }
                        } else {
                            value.weekdays.insert(weekday)
                        }
                        onChange(value)
                    } label: {
                        Text(shortWeekday(weekday))
                            .hidigFont(size: 10, weight: .semibold)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ScheduleChoiceButtonStyle(isSelected: schedule.weekdays.contains(weekday)))
                }
            }

            Text("Блокировка действует \(schedule.timeDescription) в выбранные дни.")
                .hidigFont(size: 10)
                .foregroundStyle(HidigPalette.secondary)
        }
        .padding(14)
        .background(HidigPalette.canvas)
        .overlay(RoundedRectangle(cornerRadius: 13).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 13))
    }

    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { schedule.isAllDay },
            set: { value in
                var updated = schedule
                updated.isAllDay = value
                onChange(updated)
            }
        )
    }

    private var startBinding: Binding<Int> {
        Binding(get: { schedule.startMinute }, set: { value in
            var updated = schedule
            updated.startMinute = value
            onChange(updated)
        })
    }

    private var endBinding: Binding<Int> {
        Binding(get: { schedule.endMinute }, set: { value in
            var updated = schedule
            updated.endMinute = value
            onChange(updated)
        })
    }

    private func timeField(_ title: String, minute: Binding<Int>) -> some View {
        HStack(spacing: 7) {
            Text(title).hidigFont(size: 11, weight: .medium).foregroundStyle(HidigPalette.secondary)
            DatePicker("", selection: dateBinding(for: minute), displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
    }

    private func dateBinding(for minute: Binding<Int>) -> Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: minute.wrappedValue / 60,
                    minute: minute.wrappedValue % 60,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { date in
                minute.wrappedValue = Calendar.current.component(.hour, from: date) * 60
                    + Calendar.current.component(.minute, from: date)
            }
        )
    }

    private func presetButton(_ title: String, days: Set<Int>) -> some View {
        Button {
            var value = schedule
            value.weekdays = days
            onChange(value)
        } label: {
            Text(title)
                .hidigFont(size: 11, weight: .semibold)
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(ScheduleChoiceButtonStyle(isSelected: schedule.weekdays == days))
    }

    private func shortWeekday(_ weekday: Int) -> String {
        [1: "Вс", 2: "Пн", 3: "Вт", 4: "Ср", 5: "Чт", 6: "Пт", 7: "Сб"][weekday] ?? ""
    }
}

private struct ScheduleChoiceButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        ScheduleChoiceButtonBody(
            label: configuration.label,
            isSelected: isSelected,
            isPressed: configuration.isPressed
        )
    }
}

private struct ScheduleChoiceButtonBody<Label: View>: View {
    @State private var isHovered = false

    let label: Label
    let isSelected: Bool
    let isPressed: Bool

    var body: some View {
        label
            .foregroundStyle(isSelected ? Color.white : HidigPalette.forest)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? HidigPalette.controlFill : HidigPalette.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
            .scaleEffect(isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.12), value: isPressed)
            .onHover { isHovered = $0 }
    }

    private var background: Color {
        if isSelected {
            return isHovered || isPressed
                ? HidigPalette.controlFill.opacity(0.86)
                : HidigPalette.controlFill
        }
        return isHovered || isPressed
            ? HidigPalette.hover.opacity(0.72)
            : HidigPalette.surfaceRaised
    }
}

private struct TaskRequirementSelector: View {
    let requiresAllTasks: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        HStack(spacing: 6) {
            option("Все задачи на сегодня", value: true)
            option("Только выбранные задачи", value: false)
        }
        .padding(5)
        .background(HidigPalette.canvas)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(HidigPalette.line)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func option(_ title: String, value: Bool) -> some View {
        let isSelected = requiresAllTasks == value
        return Button { onChange(value) } label: {
            HStack(spacing: 7) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .hidigFont(size: 13, weight: .semibold)
                    .foregroundStyle(isSelected ? HidigPalette.lettuceStrong : HidigPalette.secondary)
                Text(title)
                    .hidigFont(size: 12, weight: .semibold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(HidigPalette.forest)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 38)
            .contentShape(Rectangle())
        }
        .buttonStyle(SelectionRowButtonStyle(isSelected: isSelected))
    }
}

private struct NewGroupSheet: View {
    @EnvironmentObject private var store: AppStore
    @Binding var isPresented: Bool
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Новая группа")
                .hidigFont(size: 26, weight: .bold, design: .rounded)
            TextField("Например, Видео и соцсети", text: $name)
                .textFieldStyle(HidigTextFieldStyle())
            HStack {
                Button("Отмена") { isPresented = false }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Создать") {
                    store.addGroup(named: name)
                    isPresented = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 420)
        .background(HidigPalette.canvas)
    }
}

private struct RenameGroupSheet: View {
    @EnvironmentObject private var store: AppStore
    let target: GroupRenameTarget
    @Binding var isPresented: Bool
    @State private var name: String

    init(target: GroupRenameTarget, isPresented: Binding<Bool>) {
        self.target = target
        _isPresented = isPresented
        _name = State(initialValue: target.group.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Переименовать группу")
                .hidigFont(size: 26, weight: .bold, design: .rounded)
            TextField("Название группы", text: $name)
                .textFieldStyle(HidigTextFieldStyle())
                .onSubmit(save)
            HStack {
                Button("Отмена") { isPresented = false }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Сохранить", action: save)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 420)
        .foregroundStyle(HidigPalette.forest)
        .background(HidigPalette.canvas)
    }

    private func save() {
        store.updateGroupName(target.group.id, name: name)
        isPresented = false
    }
}

private struct AddDomainSheet: View {
    @EnvironmentObject private var store: AppStore
    let groupID: UUID
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var domain = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Добавить сайт")
                .hidigFont(size: 26, weight: .bold, design: .rounded)
            TextField("Название, например YouTube", text: $name)
                .textFieldStyle(HidigTextFieldStyle())
            TextField("Домен, например youtube.com", text: $domain)
                .textFieldStyle(HidigTextFieldStyle())
            Text("Поддомены этого домена также будут закрыты.")
                .hidigFont(size: 11)
                .foregroundStyle(HidigPalette.secondary)
            HStack {
                Button("Отмена") { isPresented = false }.buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Добавить") {
                    do {
                        try store.addDomain(domain, displayName: name, to: groupID)
                        isPresented = false
                    } catch {
                        store.errorMessage = error.localizedDescription
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(28)
        .frame(width: 440)
        .background(HidigPalette.canvas)
    }
}

private struct EditResourceSheet: View {
    @EnvironmentObject private var store: AppStore
    let target: ResourceEditTarget
    @Binding var isPresented: Bool
    @State private var name: String
    @State private var identifier: String

    init(target: ResourceEditTarget, isPresented: Binding<Bool>) {
        self.target = target
        _isPresented = isPresented
        _name = State(initialValue: target.resource.displayName)
        _identifier = State(initialValue: target.resource.identifier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Редактировать \(target.resource.kind == .domain ? "сайт" : "приложение")")
                .hidigFont(size: 26, weight: .bold, design: .rounded)
            TextField("Название", text: $name)
                .textFieldStyle(HidigTextFieldStyle())
            TextField(identifierPlaceholder, text: $identifier)
                .textFieldStyle(HidigTextFieldStyle())
            Text(identifierHint)
                .hidigFont(size: 11)
                .foregroundStyle(HidigPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Отмена") { isPresented = false }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Сохранить") { save() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(28)
        .frame(width: 440)
        .foregroundStyle(HidigPalette.forest)
        .background(HidigPalette.canvas)
    }

    private var identifierPlaceholder: String {
        target.resource.kind == .domain ? "Домен, например youtube.com" : "Идентификатор приложения"
    }

    private var identifierHint: String {
        target.resource.kind == .domain
            ? "Введите домен без https:// и пути. Поддомены также будут заблокированы."
            : "Изменяйте идентификатор только если приложение перестало определяться. Путь к приложению сохранится."
    }

    private func save() {
        do {
            try store.updateResource(
                target.resource.id,
                in: target.groupID,
                displayName: name,
                identifier: identifier
            )
            isPresented = false
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }
}
