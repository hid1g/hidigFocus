import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuartzCore

struct TasksView: View {
    @Environment(\.hidigContentWidth) private var contentWidth
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @State private var quickTaskTitle = ""
    @EnvironmentObject private var workspace: PlannerWorkspace
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    private var searchText: String { workspace.search }
    @AppStorage("taskListsVisible", store: HidigRuntime.defaults) private var taskListsVisible = false
    @AppStorage("taskListsWidth", store: HidigRuntime.defaults) private var taskListsWidth = 210.0
    @State private var taskListsDraftWidth = 210.0
    @State private var showsCompactTaskLists = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                if contentWidth < 900 {
                    VStack(alignment: .leading, spacing: 0) {
                        TasksPresentationControl(selection: $workspace.presentation).padding(.leading, 22)
                        PlannerFilterMenu()
                    }
                } else {
                    HStack(spacing: 12) {
                        TasksPresentationControl(selection: $workspace.presentation)
                        PlannerFilterMenu()
                    }.padding(.leading, 22)
                }
            }
            if !workspace.selectedIDs.isEmpty { BulkTaskActions() }
            Divider().overlay(HidigPalette.line)
            HStack(spacing: 0) {
                if taskListsVisible && contentWidth >= 900 && store.tasksPresentation != .calendar {
                    TaskNavigationColumn().frame(width: taskListsDraftWidth)
                    PanelResizeHandle(width: $taskListsDraftWidth, bounds: 170...320, onCommit: { taskListsWidth = $0 })
                }
                center
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(HidigPalette.canvas)
        .environment(\.taskCardSelectedID, store.selectedTaskID)
        .frame(minWidth: 620)
        .onAppear { taskListsDraftWidth = min(320, max(170, taskListsWidth)) }
        .onChange(of: store.taskSidebarSelection) { _ in showsCompactTaskLists = false }
        .background(Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: [.command]).hidden())
        .overlayPreferenceValue(TaskCardAnchors.self) { PlannerCardHost(anchors: $0) }
        .onDeleteCommand { if !workspace.selectedIDs.isEmpty { store.requestTaskDeletion(workspace.selectedIDs) } }
        .onExitCommand { [deletionWasPresented = !store.pendingTaskDeletion.isEmpty] in
            if deletionWasPresented { store.pendingTaskDeletion = [] }
            else { workspace.selectedIDs = []; store.selectedTaskID = nil }
        }
        .disabled(!store.pendingTaskDeletion.isEmpty)
        .overlay {
            if !store.pendingTaskDeletion.isEmpty { TaskDeletionConfirmation() }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if store.tasksPresentation != .calendar {
                Button {
                    if contentWidth < 900 { showsCompactTaskLists.toggle() }
                    else { withAnimation(reduceMotion ? nil : .easeOut(duration: PrintDesign.state)) { taskListsVisible.toggle() } }
                } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(HidigIconButtonStyle())
                    .help(contentWidth >= 900 && taskListsVisible ? "Скрыть списки" : "Показать списки")
                    .accessibilityLabel(contentWidth >= 900 && taskListsVisible ? "Скрыть списки" : "Показать списки")
                    .popover(isPresented: $showsCompactTaskLists) {
                        TaskNavigationColumn().frame(width: 250, height: 560)
                    }
            }
            Spacer()
            PlannerSearchField(focus: $searchFocused)
                .frame(minWidth: 90, maxWidth: 150)
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .foregroundStyle(HidigPalette.forest)
    }

    @ViewBuilder private var center: some View {
        switch workspace.presentation {
        case .list:
            TaskListColumn(searchText: searchText, quickTaskTitle: $quickTaskTitle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .kanban:
            TaskKanbanView(searchText: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .calendar:
            TaskCalendarView(searchText: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .matrix:
            EisenhowerMatrixView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

}

private enum TaskKanbanGrouping: String, CaseIterable, Identifiable {
    case status
    case project
    var id: String { rawValue }
    var title: String { self == .status ? "По статусу" : "По проектам" }
}

private enum TaskKanbanScope: String, CaseIterable, Identifiable {
    case active
    case archive
    case trash
    var id: String { rawValue }
    var title: String {
        switch self {
        case .active: return "Активные"
        case .archive: return "Архив"
        case .trash: return "Корзина"
        }
    }
}

private struct TaskKanbanLane: Identifiable {
    enum Target {
        case stage(TaskKanbanStage)
        case project(UUID)
        case none
    }
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
    let tasks: [ManagedTask]
    let emptyText: String
    let target: Target
    let allowsAdding: Bool
}

private struct TaskKanbanView: View {
    @Environment(\.hidigContentWidth) private var contentWidth
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: PlannerWorkspace
    let searchText: String
    @AppStorage("tasks.kanban.grouping", store: HidigRuntime.defaults) private var groupingRaw = TaskKanbanGrouping.status.rawValue
    @AppStorage("tasks.kanban.scope", store: HidigRuntime.defaults) private var scopeRaw = TaskKanbanScope.active.rawValue

    private var grouping: TaskKanbanGrouping {
        get { TaskKanbanGrouping(rawValue: groupingRaw) ?? .status }
        nonmutating set { groupingRaw = newValue.rawValue }
    }

    private var scope: TaskKanbanScope {
        get { TaskKanbanScope(rawValue: scopeRaw) ?? .active }
        nonmutating set { scopeRaw = newValue.rawValue }
    }

    private var snapshot: PlannerTaskSnapshot {
        store.plannerKanbanSnapshot(search: searchText, scope: scope.rawValue, allProjects: grouping == .project)
    }
    private var tasks: [ManagedTask] { snapshot.tasks }

    private var lanes: [TaskKanbanLane] {
        let snapshot = snapshot
        if grouping == .project { return projectLanes(snapshot) }
        switch scope {
        case .active:
            return TaskKanbanStage.allCases.map { stage in
                TaskKanbanLane(
                    id: "stage-\(stage.rawValue)", title: stage.title,
                    subtitle: stage == .done ? "После переноса задача попадёт в архив" : nil,
                    systemImage: stage.systemImage,
                    tasks: snapshot.byStage[stage] ?? [],
                    emptyText: stage == .done ? "Перетащите сюда, чтобы завершить" : "Нет задач",
                    target: .stage(stage), allowsAdding: stage != .done
                )
            }
        case .archive:
            return [
                TaskKanbanLane(id: "archive-completed", title: "Выполнено", subtitle: nil,
                    systemImage: "checkmark.circle", tasks: snapshot.byStatus[.completed] ?? [],
                    emptyText: "Нет выполненных задач", target: .none, allowsAdding: false),
                TaskKanbanLane(id: "archive-wont-do", title: "Не буду делать", subtitle: nil,
                    systemImage: "slash.circle", tasks: snapshot.byStatus[.wontDo] ?? [],
                    emptyText: "Нет отменённых задач", target: .none, allowsAdding: false)
            ]
        case .trash:
            return [TaskKanbanLane(id: "trash", title: "Корзина",
                subtitle: "Восстановление — через контекстное меню", systemImage: "trash",
                tasks: tasks, emptyText: "Корзина пуста", target: .none, allowsAdding: false)]
        }
    }

    private func projectLanes(_ snapshot: PlannerTaskSnapshot) -> [TaskKanbanLane] {
        var lists = store.taskLists
        if !lists.contains(where: { $0.id == TaskList.inboxID }) { lists.insert(.inbox, at: 0) }
        let populated = Set(snapshot.byProject.keys)
        return lists.filter { populated.contains($0.id) }.map { list in
            let folder = list.folderID.flatMap { id in store.taskFolders.first { $0.id == id }?.name }
            return TaskKanbanLane(
                id: "project-\(list.id.uuidString)", title: list.name, subtitle: folder,
                systemImage: list.id == TaskList.inboxID ? "tray" : "list.bullet",
                tasks: snapshot.byProject[list.id] ?? [], emptyText: emptyProjectText,
                target: scope == .active ? .project(list.id) : .none,
                allowsAdding: scope == .active
            )
        }
    }

    private var emptyProjectText: String {
        switch scope {
        case .active: return "В проекте нет активных задач"
        case .archive: return "В проекте нет архивных задач"
        case .trash: return "В проекте нет удалённых задач"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if contentWidth < 900 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { groupingPicker; Spacer(); scopeSummary }
                        scopePicker
                    }
                } else {
                    HStack(spacing: 12) { groupingPicker; scopePicker; Spacer(); scopeSummary }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(lanes) { lane in
                        TaskKanbanColumn(lane: lane, grouping: grouping)
                    }
                }
                .padding(14)
            }
        }
        .background(HidigPalette.canvas)
    }

    private var groupingPicker: some View {
        Picker("Группировка", selection: Binding(get: { grouping }, set: { grouping = $0 })) {
            ForEach(TaskKanbanGrouping.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented).labelsHidden().frame(width: 230)
    }
    private var scopePicker: some View {
        Picker("Раздел", selection: Binding(get: { scope }, set: { scope = $0 })) {
            ForEach(TaskKanbanScope.allCases) { Text($0.title).tag($0) }
        }.pickerStyle(.segmented).labelsHidden().frame(width: 260)
    }
    private var scopeSummary: some View {
        Text("\(grouping == .project ? "Все проекты" : "Текущий раздел") · \(RussianPluralizer.phrase(tasks.count, one: "задача", few: "задачи", many: "задач"))")
            .hidigFont(size: 10).foregroundStyle(HidigPalette.secondary).lineLimit(1)
    }
}

private struct TaskKanbanColumn: View {
    @EnvironmentObject private var store: AppStore
    let lane: TaskKanbanLane
    let grouping: TaskKanbanGrouping
    @State private var addsTask = false
    @State private var newTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: lane.systemImage)
                VStack(alignment: .leading, spacing: 1) {
                    Text(lane.title).hidigFont(size: 13, weight: .semibold).lineLimit(1)
                    if let subtitle = lane.subtitle {
                        Text(subtitle).hidigFont(size: 9).foregroundStyle(HidigPalette.secondary).lineLimit(1)
                    }
                }
                Text("\(lane.tasks.count)").hidigFont(size: 10).foregroundStyle(HidigPalette.secondary)
                Spacer()
                if lane.allowsAdding {
                    Button { addsTask.toggle() } label: { Image(systemName: "plus") }
                        .buttonStyle(HidigIconButtonStyle())
                        .help("Добавить задачу в «\(lane.title)»")
                }
            }
            .padding(10)

            if addsTask {
                HStack(spacing: 6) {
                    TextField("Название задачи", text: $newTitle)
                        .textFieldStyle(HidigTextFieldStyle())
                        .onSubmit(addTask)
                    Button("Добавить", action: addTask).buttonStyle(PrimaryButtonStyle())
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }

            Divider()
            ScrollView(.vertical) {
                LazyVStack(spacing: 8) {
                    ForEach(lane.tasks) { task in TaskKanbanCard(task: task, showsProject: grouping == .status) }
                    if lane.tasks.isEmpty {
                        Text(lane.emptyText)
                            .hidigFont(size: 11)
                            .foregroundStyle(HidigPalette.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 26)
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: .infinity)
        .background(HidigPalette.surface.opacity(0.72))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { values, _ in
            guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
            switch lane.target {
            case .stage(let stage): store.moveManagedTask(id, toKanbanStage: stage); return true
            case .project(let listID): store.moveManagedTask(id, toList: listID); return true
            case .none: return false
            }
        }
    }

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let listID: UUID
        let stage: TaskKanbanStage
        switch lane.target {
        case .project(let target): listID = target; stage = .backlog
        case .stage(let target):
            stage = target
            if case .list(let selected) = store.taskSidebarSelection { listID = selected }
            else { listID = TaskList.inboxID }
        case .none: return
        }
        let task = ManagedTask(listID: listID, title: title, kanbanStage: stage)
        guard store.createPlannerTask(task) != nil else { return }
        newTitle = ""
        addsTask = false
    }
}

private struct TaskKanbanCard: View {
    @EnvironmentObject private var store: AppStore
    let task: ManagedTask
    let showsProject: Bool
    private var tint: Color {
        Color(hex: store.taskList(id: task.listID)?.colorHex ?? "#6A9CC2")
    }
    private var projectPath: String {
        let list = store.taskList(id: task.listID) ?? .inbox
        guard let folderID = list.folderID,
              let folder = store.taskFolders.first(where: { $0.id == folderID }) else { return list.name }
        return "\(folder.name) / \(list.name)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            TaskCompletionButton(task: task, store: store)
            Button { store.selectedTaskID = task.id } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .hidigFont(size: 12, weight: .medium)
                        .strikethrough(task.status == .completed || task.status == .wontDo)
                        .lineLimit(3)
                    HStack(spacing: 6) {
                        Text(task.scheduleLabel).lineLimit(1)
                        if task.priority != .none { Image(systemName: "flag.fill").foregroundStyle(task.priority.accent) }
                    }
                    .hidigFont(size: 10)
                    .foregroundStyle(HidigPalette.secondary)
                    if showsProject {
                        Label(projectPath, systemImage: "folder")
                            .hidigFont(size: 9)
                            .foregroundStyle(HidigPalette.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(CalendarTaskPressStyle(tint: tint))
            .taskCard(task)
        }
        .padding(10)
        .background(HidigPalette.surface)
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .taskPriorityBorder(task.priority, radius: 8)
        .opacity(task.status == .completed || task.status == .wontDo ? 0.62 : 1)
        .draggable(task.id.uuidString)
        .contextMenu { TaskContextActions(task: task) }
    }
}

private struct TaskDeletionConfirmation: View {
    @EnvironmentObject private var store: AppStore
    @FocusState private var cancelFocused: Bool
    private var multiple: Bool { store.pendingTaskDeletion.count > 1 }
    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea().contentShape(Rectangle())
            VStack(alignment: .leading, spacing: 16) {
                Text(multiple ? "Удалить повторяющиеся задачи?" : "Удалить повторяющуюся задачу?")
                    .hidigFont(size: 14, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                Button(multiple ? "Только выбранные экземпляры" : "Только этот экземпляр") {
                    store.confirmTaskDeletion(entireSeries: false)
                }.buttonStyle(PrimaryButtonStyle(expands: true))
                Button(multiple ? "Все выбранные серии" : "Всю серию") {
                    store.confirmTaskDeletion(entireSeries: true)
                }.buttonStyle(SecondaryButtonStyle(expands: true))
                Button("Отмена") { store.pendingTaskDeletion = [] }
                    .buttonStyle(SecondaryButtonStyle(expands: true))
                    .focusable()
                    .focused($cancelFocused)
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(24).frame(width: 340)
            .background(HidigPalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: PrintTokens.popoverRadius))
            .shadow(color: .black.opacity(0.2), radius: 18, y: 5)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Подтверждение удаления")
        }
        .onAppear {
            DispatchQueue.main.async {
                guard !store.pendingTaskDeletion.isEmpty else { return }
                NSApp.keyWindow?.makeFirstResponder(nil)
                cancelFocused = true
            }
        }
        .onExitCommand { store.pendingTaskDeletion = [] }
    }
}

/// Typing stays local to the field; data filtering runs after a short pause.
private struct PlannerSearchField: View {
    @EnvironmentObject private var workspace: PlannerWorkspace
    @EnvironmentObject private var store: AppStore
    let focus: FocusState<Bool>.Binding
    @State private var draft = ""
    @State private var applied = ""
    var body: some View {
        TextField("Поиск", text: $draft)
            .textFieldStyle(HidigTextFieldStyle()).focused(focus)
            .help("Поиск задач. В календаре Return открывает первую найденную задачу текущего периода.")
            .onSubmit(openFirstCalendarMatch)
            .onAppear { draft = workspace.search; applied = workspace.search }
            .onChange(of: workspace.search) { value in
                if value != applied { applied = value; draft = value }
            }
            .task(id: draft) {
                do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
                guard !Task.isCancelled, workspace.search != draft else { return }
                applied = draft; workspace.search = draft
            }
            .onDisappear { if workspace.search != draft { workspace.search = draft } }
    }
    private func openFirstCalendarMatch() {
        guard workspace.presentation == .calendar,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        applied = draft; workspace.search = draft
        let calendar = PlannerCalendar.current
        var first = calendar.startOfDay(for: workspace.anchor)
        let count: Int
        switch workspace.mode {
        case .day: count = 1
        case .fourDays: count = workspace.customDayCount
        case .week: count = 7
        case .agenda: count = 29
        case .month:
            first = calendar.dateInterval(of: .month, for: first)?.start ?? first
            let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
            first = calendar.date(byAdding: .day, value: -offset, to: first) ?? first
            count = 42
        }
        for offset in 0..<count {
            guard let day = calendar.date(byAdding: .day, value: offset, to: first) else { continue }
            if let match = store.plannerDaySnapshot(on: day, search: draft).tasks.first {
                store.selectedTaskID = match.id
                return
            }
        }
    }
}

private struct TasksPresentationControl: View {
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @Binding var selection: TasksPresentation

    var body: some View {
        HStack(spacing: 3) {
            ForEach(TasksPresentation.allCases) { option in
                Button {
                    selection = option
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                        .hidigFont(size: 10, weight: selection == option ? .semibold : .medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .padding(.horizontal, 7)
                        .frame(height: 32)
                        .background(selection == option ? HidigPalette.surfaceRaised : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(HidigPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}

private enum TaskSidebarCreationTarget: Identifiable {
    case folder
    case list(folderID: UUID?, folderName: String?)

    var id: String {
        switch self {
        case .folder: return "folder"
        case .list(let folderID, _): return "list-\(folderID?.uuidString ?? "root")"
        }
    }

    var title: String {
        switch self {
        case .folder: return "Новая папка"
        case .list: return "Новый список"
        }
    }

    var placeholder: String {
        switch self {
        case .folder: return "Название папки"
        case .list: return "Название списка"
        }
    }

    var detail: String {
        switch self {
        case .folder:
            return "Папка появится в разделе списков."
        case .list(_, let folderName?):
            return "Список будет добавлен в папку «\(folderName)»."
        case .list:
            return "Список появится в общем разделе."
        }
    }
}

private enum TaskSidebarDeletionTarget: Identifiable {
    case folder(TaskFolder)
    case list(TaskList)

    var id: String {
        switch self {
        case .folder(let folder): return "folder-\(folder.id.uuidString)"
        case .list(let list): return "list-\(list.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .folder(let folder): return "Удалить папку «\(folder.name)»?"
        case .list(let list): return "Удалить список «\(list.name)»?"
        }
    }

    var message: String {
        switch self {
        case .folder:
            return "Списки из папки останутся и будут перенесены в общий раздел."
        case .list:
            return "Все задачи из списка останутся и будут перенесены во «Входящие»."
        }
    }
}

private struct TaskSidebarCreationSheet: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let target: TaskSidebarCreationTarget
    @Binding var isPresented: Bool
    let onCreate: (String) -> Void
    @State private var name = ""
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(target.title)
                .hidigFont(size: 24, weight: .bold, design: .rounded)
            Text(target.detail)
                .hidigFont(size: 12)
                .foregroundStyle(HidigPalette.secondary)
            TextField(target.placeholder, text: $name)
                .textFieldStyle(HidigTextFieldStyle())
                .focused($isNameFocused)
                .onSubmit(create)
            HStack {
                Button("Отмена") { isPresented = false }
                    .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button("Создать", action: create)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(trimmedName.isEmpty)
            }
        }
        .padding(28)
        .frame(width: 390)
        .foregroundStyle(HidigPalette.forest)
        .background(HidigPalette.canvas)
        .onAppear { isNameFocused = true }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        onCreate(trimmedName)
        isPresented = false
    }
}

private struct TaskNavigationColumn: View {
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @State private var newListName = ""
    @State private var creationTarget: TaskSidebarCreationTarget?
    @State private var deletionTarget: TaskSidebarDeletionTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                navGroup("Закреплённые", rows: [
                    ("Все", "tray.full", .all),
                    ("Сегодня", "sun.max", .today),
                    ("Завтра", "sunrise", .tomorrow),
                    ("Без даты", "calendar.badge.minus", .unscheduled),
                    ("Следующие 7 дней", "calendar", .nextSevenDays),
                    ("Входящие", "tray", .inbox)
                ])

                VStack(alignment: .leading, spacing: 4) {
                    sectionLabel("Списки")
                        .contentShape(Rectangle())
                        .contextMenu { creationMenu(folderID: nil, folderName: nil) }
                    ForEach(store.taskFolders) { folder in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: PrintDesign.state)) {
                                store.toggleTaskFolder(folder.id)
                            }
                        } label: {
                            HStack {
                                Image(systemName: folder.isCollapsed ? "chevron.right" : "chevron.down")
                                Text(folder.name).lineLimit(1)
                                Spacer()
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            creationMenu(folderID: folder.id, folderName: folder.name)
                            Divider()
                            Button(role: .destructive) {
                                deletionTarget = .folder(folder)
                            } label: {
                                Label("Удалить папку", systemImage: "trash")
                            }
                        }
                        if !folder.isCollapsed {
                            ForEach(store.taskLists.filter { $0.folderID == folder.id }) { list in
                                listRow(list).padding(.leading, 14)
                            }
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    ForEach(store.taskLists.filter { $0.folderID == nil && $0.id != TaskList.inboxID }) { list in
                        listRow(list)
                    }
                    HStack(spacing: 6) {
                        TextField("Новый список", text: $newListName)
                            .textFieldStyle(.plain)
                            .onSubmit(addList)
                        Button(action: addList) { Image(systemName: "plus") }
                            .buttonStyle(HidigIconButtonStyle())
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 34)
                    .background(HidigPalette.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                }

                navGroup("Архив", rows: [
                    ("Выполнено", "checkmark.circle", .completed),
                    ("Корзина", "trash", .trash)
                ])
            }
            .padding(12)
        }
        .background(HidigPalette.surface.opacity(0.7))
        .sheet(item: $creationTarget) { target in
            TaskSidebarCreationSheet(
                target: target,
                isPresented: Binding(
                    get: { creationTarget != nil },
                    set: { if !$0 { creationTarget = nil } }
                )
            ) { name in
                switch target {
                case .folder:
                    store.addTaskFolder(named: name)
                case .list(let folderID, _):
                    store.addTaskList(named: name, folderID: folderID)
                }
            }
            .environmentObject(store)
        }
        .alert(item: $deletionTarget) { target in
            Alert(
                title: Text(target.title),
                message: Text(target.message),
                primaryButton: .destructive(Text("Удалить")) { delete(target) },
                secondaryButton: .cancel(Text("Отмена"))
            )
        }
    }

    private func navGroup(_ title: String, rows: [(String, String, TaskSidebarSelection)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionLabel(title)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                navRow(title: row.0, icon: row.1, selection: row.2)
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .hidigFont(size: 10, weight: .bold)
            .tracking(0.8)
            .foregroundStyle(HidigPalette.secondary)
            .padding(.horizontal, 8)
    }

    private func navRow(title: String, icon: String, selection: TaskSidebarSelection) -> some View {
        Button { store.taskSidebarSelection = selection } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 15)
                Text(title).lineLimit(1)
                Spacer()
                Text("\(count(for: selection))").foregroundStyle(HidigPalette.secondary)
            }
            .hidigFont(size: 12, weight: store.taskSidebarSelection == selection ? .semibold : .regular)
            .padding(.horizontal, 8)
            .frame(height: 34)
        }
        .buttonStyle(SelectionRowButtonStyle(isSelected: store.taskSidebarSelection == selection))
    }

    private func listRow(_ list: TaskList) -> some View {
        let folderName = list.folderID.flatMap { folderID in
            store.taskFolders.first(where: { $0.id == folderID })?.name
        }
        return navRow(title: list.name, icon: list.isPinned ? "pin.fill" : "list.bullet", selection: .list(list.id))
            .draggable("list:\(list.id)")
            .dropDestination(for: String.self) { values, _ in
                guard let raw = values.first, raw.hasPrefix("list:"), let id = UUID(uuidString: String(raw.dropFirst(5))) else { return false }
                store.reorderList(id, before: list.id); return true
            }
            .contextMenu {
                creationMenu(folderID: list.folderID, folderName: folderName)
                Divider()
                Button(role: .destructive) {
                    deletionTarget = .list(list)
                } label: {
                    Label("Удалить список", systemImage: "trash")
                }
            }
    }

    @ViewBuilder private func creationMenu(folderID: UUID?, folderName: String?) -> some View {
        Button {
            creationTarget = .list(folderID: folderID, folderName: folderName)
        } label: {
            Label(folderID == nil ? "Новый список" : "Новый список в папке", systemImage: "plus")
        }
        Button {
            creationTarget = .folder
        } label: {
            Label("Новая папка", systemImage: "folder.badge.plus")
        }
    }

    private func delete(_ target: TaskSidebarDeletionTarget) {
        switch target {
        case .folder(let folder): store.removeTaskFolder(folder.id)
        case .list(let list): store.removeTaskList(list.id)
        }
    }

    private func count(for selection: TaskSidebarSelection) -> Int {
        switch selection {
        case .all, .tomorrow, .unscheduled: return store.visibleCount(selection: selection)
        case .today:
            return store.visibleCount(selection: .today)
        case .nextSevenDays:
            return store.visibleCount(selection: .nextSevenDays)
        case .inbox:
            return store.visibleCount(selection: .inbox)
        case .list(let id):
            return store.visibleCount(selection: .list(id))
        case .completed:
            return store.visibleCount(selection: .completed)
        case .trash:
            return store.visibleCount(selection: .trash)
        }
    }

    private func addList() {
        store.addTaskList(named: newListName)
        newListName = ""
    }
}

private struct TaskListColumn: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let searchText: String
    @Binding var quickTaskTitle: String

    @EnvironmentObject private var workspace: PlannerWorkspace
    var body: some View {
        let snapshot = store.plannerListSnapshot(search: searchText, collapsed: workspace.collapsedTaskIDs)
        let visibleTasks = snapshot.tasks
        let groupedRows = snapshot.groupedRows
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Быстро добавить задачу", text: $quickTaskTitle)
                    .textFieldStyle(HidigTextFieldStyle())
                    .onSubmit(addTask)
                Button("Добавить", action: addTask)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(16)

            let parsed = QuickTaskInput.parse(quickTaskTitle)
            if let date = parsed.date {
                Text("Будет создано: \(parsed.title) · \(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
            }
            if visibleTasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .hidigFont(size: 30)
                        .foregroundStyle(HidigPalette.secondary)
                    Text("Задач нет").hidigFont(size: 15, weight: .semibold)
                    Text(workspace.filter.isActive || !searchText.isEmpty ? "Измените поиск или сбросьте фильтры." : "Создайте задачу или выберите другой раздел.")
                        .hidigFont(size: 12)
                        .foregroundStyle(HidigPalette.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(workspace.sort == .date ? ["Просрочено", "Сегодня", "Предстоящие", "Без срока"] : ["Задачи"], id: \.self) { section in
                            let rows = groupedRows[section] ?? []
                            if !rows.isEmpty {
                                HStack {
                                    Text(section).hidigFont(size: 12, weight: .semibold)
                                    Text("\(rows.count)").hidigFont(size: 10)
                                    Spacer()
                                }.foregroundStyle(section == "Просрочено" ? HidigPalette.warning : HidigPalette.secondary)
                                    .padding(.top, 10)
                                ForEach(rows) { row in
                                    HStack(spacing: 4) {
                                        if row.hasChildren {
                                            TaskHierarchyDisclosure(isExpanded: !workspace.collapsedTaskIDs.contains(row.id)) {
                                                if workspace.collapsedTaskIDs.contains(row.id) { workspace.collapsedTaskIDs.remove(row.id) }
                                                else { workspace.collapsedTaskIDs.insert(row.id) }
                                            }
                                        } else { Color.clear.frame(width: PrintTokens.buttonHeight) }
                                        TaskRow(task: row.task)
                                    }
                                        .padding(.leading, CGFloat(row.depth) * 20)
                                        .dropDestination(for: String.self) { ids, _ in
                                            guard workspace.sort == .manual, let id = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
                                            store.reorderTask(id, before: row.task.id); return true
                                        }
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(PlannerScrollPosition(key: "list.\(store.taskSidebarSelection)", workspace: workspace))
                }
            }
        }
    }

    private func addTask() {
        let parsed = QuickTaskInput.parse(quickTaskTitle)
        let list: UUID
        if case .list(let id) = store.taskSidebarSelection { list = id } else { list = TaskList.inboxID }
        let draft = ManagedTask(listID: list, title: parsed.title, startDate: parsed.date, isAllDay: parsed.date != nil && !quickTaskTitle.contains(":"))
        guard store.createPlannerTask(draft) != nil else { return }
        quickTaskTitle = ""
    }
}

private struct TaskRow: View {
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @EnvironmentObject private var workspace: PlannerWorkspace
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let task: ManagedTask
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Button { toggleSelection() } label: { Image(systemName: workspace.selectedIDs.contains(task.id) ? "checkmark.circle.fill" : "circle") }
                .buttonStyle(.plain).help("Выбрать задачу").accessibilityLabel("Выбрать \(task.title)")
                .accessibilityValue(workspace.selectedIDs.contains(task.id) ? "Выбрана" : "Не выбрана")
            TaskCompletionButton(task: task, store: store)
            Button {
                if NSEvent.modifierFlags.contains(.command) { toggleSelection() }
                else if NSEvent.modifierFlags.contains(.shift), let last = workspace.lastSelectedID {
                    let ids = workspace.filter.sorted(store.visibleManagedTasks, by: workspace.sort).map(\.id)
                    if let a = ids.firstIndex(of: last), let b = ids.firstIndex(of: task.id) { workspace.selectedIDs.formUnion(ids[min(a,b)...max(a,b)]) }
                } else { workspace.lastSelectedID = task.id; store.selectedTaskID = task.id }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title).strikethrough(task.status == .completed || task.status == .wontDo)
                        .hidigFont(size: 14, weight: .medium).lineLimit(2)
                    HStack(spacing: 10) {
                        Label(task.scheduleLabel, systemImage: "calendar")
                            .foregroundStyle(task.isOverdue ? HidigPalette.warning : HidigPalette.secondary)
                        Text(store.taskList(id: task.listID)?.name ?? "Входящие")
                            .foregroundStyle(HidigPalette.secondary)
                        if task.status == .wontDo { Text(task.sourceName == "TickTick" ? "Отменена в TickTick" : "Не буду делать") }
                        if task.repeatRule != nil { Image(systemName: "repeat") }
                    }.hidigFont(size: 11)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(CalendarTaskPressStyle(tint: HidigPalette.controlFill))
            .taskCard(task)
            if task.priority != .none {
                Image(systemName: "flag.fill").foregroundStyle(task.priority.accent).accessibilityLabel("Приоритет: \(task.priority.title)")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(workspace.selectedIDs.contains(task.id) ? HidigPalette.surfaceRaised : isHovered ? HidigPalette.hover : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(HidigPalette.line.opacity(0.55)).frame(height: 1) }
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.hover), value: isHovered)
        .draggable(task.id.uuidString)
        .contextMenu { TaskContextActions(task: task) }
    }
    private func toggleSelection() {
        if workspace.selectedIDs.contains(task.id) { workspace.selectedIDs.remove(task.id) }
        else { workspace.selectedIDs.insert(task.id) }
        workspace.lastSelectedID = task.id
    }

}

struct TaskCompletionButton: View {
    let task: ManagedTask
    var size: CGFloat = 16
    var calendarSurface = false
    let store: AppStore
    private var actionTitle: String {
        switch task.status {
        case .trashed: return "Восстановить задачу"
        case .completed, .wontDo: return "Вернуть в активные"
        default: return "Выполнить задачу"
        }
    }
    private func perform() {
        if task.status == .trashed { store.restoreManagedTask(task.id) }
        else if task.status == .wontDo { store.setManagedTaskWontDo(task.id, skipped: false) }
        else { store.setManagedTaskCompleted(task.id, completed: task.status != .completed) }
    }
    private var mark: some View {
        Group {
            if task.status == .wontDo {
                Image(systemName: "xmark.square.fill").font(.system(size: size))
                    .foregroundStyle(HidigPalette.secondary).frame(width: size, height: size)
            } else { HidigCheckmarkBox(isChecked: task.status == .completed, size: size) }
        }.padding(2).contentShape(Rectangle())
    }
    @ViewBuilder var body: some View {
        if calendarSurface {
            mark.onTapGesture(perform: perform)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(actionTitle): \(task.title)")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { perform() }
                .help(actionTitle)
        } else {
            Button(action: perform) { mark }.buttonStyle(.plain)
                .help(actionTitle).accessibilityLabel("\(actionTitle): \(task.title)")
        }
    }
}

private struct TaskCardSelectionKey: EnvironmentKey {
    static let defaultValue: UUID? = nil
}
private extension EnvironmentValues {
    var taskCardSelectedID: UUID? {
        get { self[TaskCardSelectionKey.self] }
        set { self[TaskCardSelectionKey.self] = newValue }
    }
}
private struct TaskCardAnchors: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) {
        let next = nextValue()
        guard !next.isEmpty else { return }
        value.merge(next, uniquingKeysWith: { _, latest in latest })
    }
}
private struct TaskCardModifier: ViewModifier {
    @Environment(\.taskCardSelectedID) private var selectedID
    let task: ManagedTask
    func body(content: Content) -> some View {
        content.anchorPreference(key: TaskCardAnchors.self, value: .bounds) {
            selectedID == task.id ? [task.id: $0] : [:]
        }
    }
}
private struct PlannerCardHost: View {
    @EnvironmentObject private var store: AppStore
    let anchors: [UUID: Anchor<CGRect>]
    @State private var lastRect: CGRect?
    @State private var showsDetails = false
    @State private var isListPickerPresented = false
    var body: some View {
        GeometryReader { geometry in
            if let id = store.selectedTaskID, let task = store.task(id: id) {
                let rect = anchors[id].map { geometry[$0] } ?? lastRect ?? CGRect(x: geometry.size.width / 2, y: geometry.size.height / 2, width: 0, height: 0)
                let placement = TaskCardPlacement.frame(anchor: rect,
                    bounds: CGRect(origin: .zero, size: geometry.size),
                    size: CGSize(width: 400, height: showsDetails || !task.checklist.isEmpty || !store.subtasks(of: id).isEmpty ? 530 : 400))
                ZStack(alignment: .topLeading) {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { store.selectedTaskID = nil }
                        .accessibilityHidden(true)
                    TaskDetailView(task: task, showsDetails: $showsDetails, isListPickerPresented: $isListPickerPresented, cardSize: placement.size).id(id)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 18, y: 5)
                        .background(TaskCardEscapeMonitor(shouldDismissOnPointer: { store.pendingTaskDeletion.isEmpty }) {
                            if !store.pendingTaskDeletion.isEmpty { store.pendingTaskDeletion = [] }
                            else if isListPickerPresented { isListPickerPresented = false }
                            else { store.selectedTaskID = nil }
                        })
                        .position(x: placement.midX, y: placement.midY)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Карточка задачи")
                }.frame(width: geometry.size.width, height: geometry.size.height)
                    .onAppear { lastRect = rect }
                    .onChange(of: rect) { if anchors[id] != nil { lastRect = $0 } }
            }
        }
        .onChange(of: store.selectedTaskID) { id in
            showsDetails = false
            isListPickerPresented = false
            if id == nil { lastRect = nil }
        }
    }
}

extension View {
    func taskCard(_ task: ManagedTask) -> some View { modifier(TaskCardModifier(task: task)) }
}

struct TaskContextActions: View {
    @EnvironmentObject private var store: AppStore
    let task: ManagedTask

    var body: some View {
        Menu {
            Button("Сегодня", systemImage: "sun.max") { move(to: Date()) }
            Button("Завтра", systemImage: "sunrise") {
                if let date = PlannerCalendar.current.date(byAdding: .day, value: 1, to: Date()) { move(to: date) }
            }
            Button("Без даты", systemImage: "calendar.badge.minus") {
                store.scheduleManagedTask(task.id, at: nil)
            }
        } label: { Label("Дата", systemImage: "calendar") }

        Menu {
            ForEach(TaskPriority.allCases) { priority in
                Button {
                    edit { $0.priority = priority }
                } label: {
                    Label(priority.title, systemImage: task.priority == priority ? "checkmark" : "flag")
                }
            }
        } label: { Label("Приоритет", systemImage: "flag") }

        Menu {
            ForEach(store.taskLists) { list in
                Button {
                    edit { $0.listID = list.id }
                } label: {
                    Label(list.name, systemImage: task.listID == list.id ? "checkmark" : "list.bullet")
                }
            }
        } label: { Label("Переместить в", systemImage: "folder") }

        Menu {
            ForEach(Array(Set(store.state.managedTasks.flatMap(\.tags))).sorted(), id: \.self) { tag in
                Button {
                    edit { value in
                        if value.tags.contains(tag) { value.tags.removeAll { $0 == tag } }
                        else { value.tags.append(tag) }
                    }
                } label: {
                    Label(tag, systemImage: task.tags.contains(tag) ? "checkmark" : "tag")
                }
            }
            Button("Изменить метки…") { store.selectedTaskID = task.id }
        } label: { Label("Метки", systemImage: "tag") }

        Divider()
        Button("Фокусироваться", systemImage: "timer") { store.startPomodoro(for: task.id) }
        Button("Дублировать", systemImage: "plus.square.on.square") { store.duplicateManagedTask(task.id) }
        if task.status == .wontDo {
            Button("Вернуть в активные", systemImage: "arrow.uturn.backward") {
                store.setManagedTaskWontDo(task.id, skipped: false)
            }
        } else {
            Button("Не буду делать", systemImage: "xmark.square") {
                store.setManagedTaskWontDo(task.id, skipped: true)
            }
        }
        Divider()
        Button("Удалить", systemImage: "trash", role: .destructive) { store.requestTaskDeletion([task.id]) }
    }

    private func edit(_ change: (inout ManagedTask) -> Void) {
        guard var current = store.task(id: task.id) else { return }
        change(&current)
        store.updateManagedTask(current)
    }

    private func move(to day: Date) {
        let calendar = PlannerCalendar.current
        let date = task.isAllDay ? calendar.startOfDay(for: day) : {
            let time = calendar.dateComponents([.hour, .minute], from: task.startDate ?? Date())
            return calendar.date(bySettingHour: time.hour ?? 9, minute: time.minute ?? 0, second: 0, of: day)
                ?? calendar.startOfDay(for: day)
        }()
        store.scheduleManagedTask(task.id, at: date)
    }
}

private struct CalendarTaskPressStyle: ButtonStyle {
    @Environment(\.hidigReduceMotion) private var reduceMotion
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(tint.opacity(configuration.isPressed ? 0.18 : 0))
            .animation(reduceMotion ? nil : .easeOut(duration: PrintDesign.hover), value: configuration.isPressed)
    }
}

private struct CalendarSlidingStrip<Content: View>: View {
    @ObservedObject var pan: CalendarPanState
    let columnWidth: CGFloat
    let visibleWidth: CGFloat
    let leadingColumns: Int
    let content: Content

    init(pan: CalendarPanState, columnWidth: CGFloat, visibleWidth: CGFloat, leadingColumns: Int = 1, @ViewBuilder content: () -> Content) {
        self.pan = pan
        self.columnWidth = columnWidth
        self.visibleWidth = visibleWidth
        self.leadingColumns = leadingColumns
        self.content = content()
    }

    var body: some View {
        content
            .modifier(CalendarObservedOffset(value: pan.offset, leading: columnWidth * CGFloat(leadingColumns), pan: pan, token: pan.presentationToken))
            .frame(width: visibleWidth, alignment: .leading)
            // Clipping pixels alone leaves neighboring days able to intercept sidebar clicks.
            .contentShape(Rectangle())
            .clipped()
    }
}

private struct TaskCalendarView: View {
    @EnvironmentObject private var workspace: PlannerWorkspace
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @State private var draftTask: ManagedTask?
    @StateObject private var dragScroller = CalendarDragScroller()
    @State private var allDayRegion = CalendarAllDayDropRegion()
    @State private var allDayPreview = CalendarAllDayPreview()
    @State private var allDayDropDay: Date?
    @State private var allDayColumnWidth: CGFloat = 0
    @State private var interactionController = CalendarInteractionController()
    @EnvironmentObject private var store: AppStore
    let searchText: String
    @AppStorage("calendarHourHeight", store: HidigRuntime.defaults) private var persistedHourHeight = PrintTokens.calendarHourHeight
    @State private var zoom = CalendarZoomSession()
    @GestureState private var isMagnifying = false
    private var hourHeight: Double { zoom.preview ?? CalendarZoom.clamp(persistedHourHeight) }
    // Frame updates are observed by the strips, not by the calendar content.
    @State private var pan = CalendarPanState()
    @State private var timelineViewport = CalendarTimelineViewport()
    @State private var movingTaskID: UUID?
    @State private var interactionAnchor: Date?
    @State private var lockedAllDayHeight: CGFloat?
    @State private var navigation = CalendarNavigationQueue()
    private let calendar = PlannerCalendar.current

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { navigate(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Предыдущий период")
                Button("Сегодня") {
                    navigation.cancel()
                    pan.reset(); interactionAnchor = nil; lockedAllDayHeight = nil; workspace.anchor = Date()
                }
                Button { navigate(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Следующий период")
                HidigDateButton(date: Binding(get: { workspace.anchor }, set: { date in
                    navigation.cancel(); pan.reset(); interactionAnchor = nil; lockedAllDayHeight = nil
                    workspace.anchor = date
                }))
                if workspace.preparingCalendar { ProgressView().controlSize(.small).help("Подготовка повторений") }
                Spacer()
                Button { draftTask = ManagedTask(title: "", startDate: calendar.startOfDay(for: workspace.anchor), isAllDay: true) } label: { Image(systemName: "plus") }.help("Новая задача")
                calendarModeMenu
            }.buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 8)
            calendarBody.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CalendarHorizontalScrollMonitor(isEnabled: workspace.presentation == .calendar && !isMagnifying && movingTaskID == nil && (store.selectedSection == .tasks || store.selectedSection == .calendar) && workspace.mode != .agenda, onBegin: {
                    handleHorizontalScroll(delta: 0, ended: false, cancelled: false, momentum: false, newGesture: true)
                    return interactionAnchor != nil || lockedAllDayHeight != nil || abs(pan.visibleOffset) > 0.1
                }) { delta, ended, cancelled, momentum in
                    handleHorizontalScroll(delta: delta, ended: ended, cancelled: cancelled, momentum: momentum)
                })
        }
        .environment(\.calendarAutoscroll, interactionController.autoscrollActions)
        .environment(\.calendarAllDayDrag, interactionController.allDayDragActions)
        .overlay { CalendarAllDayDragOverlay(preview: allDayPreview) }
        .onPreferenceChange(CalendarAllDayBounds.self) { allDayRegion.bounds = $0 }
        .sheet(item: $draftTask) { draft in CalendarTaskCreation(draft: draft) { draftTask = nil } }
        .onAppear { bindCalendarActions(); store.prepareCalendarIndex() }
        .onChange(of: ObjectIdentifier(workspace)) { _ in bindCalendarActions() }
        .onChange(of: isMagnifying) { active in
            if active { navigation.cancel(); pan.interrupt() }
            else {
                finishMagnification()
                if interactionAnchor != nil || lockedAllDayHeight != nil || abs(pan.visibleOffset) > 0.1 {
                    handleHorizontalScroll(delta: 0, ended: true, cancelled: false, momentum: false)
                }
            }
        }
        .onChange(of: reduceMotion) { value in if value { pan.completeImmediately() } }
        .onDisappear { finishMagnification(); navigation.cancel(); pan.reset(); _ = dragScroller.update(nil); interactionController.unbind() }
        .onChange(of: workspace.presentation) { presentation in
            guard presentation != .calendar else { store.prepareCalendarIndex(); return }
            workspace.cancellationToken += 1
            navigation.cancel()
            pan.reset(); interactionAnchor = nil; lockedAllDayHeight = nil
            movingTaskID = nil; _ = dragScroller.update(nil); _ = updateAllDayDrag(nil, nil)
        }
        .onChange(of: workspace.anchor) { _ in
            if interactionAnchor == nil { store.prepareCalendarIndex() }
        }
        .onChange(of: workspace.mode) { _ in navigation.cancel(); pan.reset(); interactionAnchor = nil; lockedAllDayHeight = nil; store.prepareCalendarIndex(force: true) }
        .onChange(of: workspace.customDayCount) { value in
            let clamped = CalendarDayCount.clamp(value)
            if clamped != value { workspace.customDayCount = clamped; return }
            guard workspace.mode == .fourDays else { return }
            navigation.cancel()
            pan.reset(); interactionAnchor = nil; lockedAllDayHeight = nil
            store.prepareCalendarIndex(force: true)
        }
        .onExitCommand { [deletionWasPresented = !store.pendingTaskDeletion.isEmpty] in
            if deletionWasPresented { store.pendingTaskDeletion = []; return }
            workspace.cancellationToken += 1; navigation.cancel(); pan.reset(); interactionAnchor = nil; lockedAllDayHeight = nil; movingTaskID = nil; _ = dragScroller.update(nil)
        }
        .onChange(of: movingTaskID) { id in
            navigation.cancel()
            if id == nil {
                pan.reset(); commitInteraction(); lockedAllDayHeight = nil
                _ = dragScroller.update(nil); _ = updateAllDayDrag(nil, nil)
            } else { pan.interrupt() }
        }
    }
    private func bindCalendarActions() {
        interactionController.bind(scroller: dragScroller, pan: pan, workspace: workspace,
            preview: allDayPreview, region: $allDayRegion, dropDay: $allDayDropDay,
            columnWidth: $allDayColumnWidth, interactionAnchor: $interactionAnchor)
    }

    private func updateAllDayDrag(_ point: CGPoint?, _ task: ManagedTask?) -> Date? {
        interactionController.updateAllDayDrag(point, task)
    }

    private func navigate(_ direction: Int) {
        let direction = direction < 0 ? -1 : 1
        if navigation.enqueueIfBusy(direction) { return }
        let currentAnchor = interactionAnchor ?? workspace.anchor
        if interactionAnchor != nil { workspace.anchor = currentAnchor; interactionAnchor = nil }
        let count = workspace.mode == .week ? 7 : (workspace.mode == .fourDays ? workspace.customDayCount : 1)
        let slides = workspace.mode == .day || workspace.mode == .fourDays || workspace.mode == .week
        let target = calendar.date(byAdding: workspace.mode == .month ? .month : .day,
                                   value: direction * count, to: currentAnchor) ?? currentAnchor
        guard slides, !reduceMotion else {
            pan.reset()
            workspace.anchor = target
            lockedAllDayHeight = nil
            return
        }
        navigation.start()
        lockedAllDayHeight = pan.allDayHeight
        // Move the already-mounted neighboring period. Rebuilding the anchor first is what
        // made the old implementation pause and then jump before its animation began.
        pan.animate(to: -CGFloat(direction * count) * max(1, pan.dayWidth), reduceMotion: false) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                workspace.anchor = target
                pan.reset()
                lockedAllDayHeight = nil
                navigation.finish()
            }
            drainNavigationQueue()
        }
    }

    private func drainNavigationQueue() {
        guard navigation.pending != 0 else { return }
        let epoch = navigation.epoch
        // Let the disabled-animation anchor/reset transaction commit before the
        // next native interpolation, while rejecting work cancelled by input.
        DispatchQueue.main.async {
            guard navigation.epoch == epoch, !navigation.inFlight,
                  let direction = navigation.next() else { return }
            navigate(direction)
        }
    }

    private var calendarModeMenu: some View {
        CalendarModePicker(mode: $workspace.mode, dayCount: $workspace.customDayCount)
            .frame(width: 128)
    }

    private func matches(_ task: ManagedTask) -> Bool { store.plannerMatches(task, search: searchText) }

    @ViewBuilder private var calendarBody: some View {
        switch store.taskCalendarMode {
        case .month: TaskMonthView(anchor: store.taskCalendarAnchor, searchText: searchText)
        case .agenda: TaskAgendaView(anchor: store.taskCalendarAnchor, searchText: searchText)
        case .day, .fourDays, .week:
            GeometryReader { geometry in
                let count = store.taskCalendarMode == .day ? 1 : (store.taskCalendarMode == .fourDays ? workspace.customDayCount : 7)
                let start = calendar.startOfDay(for: interactionAnchor ?? store.taskCalendarAnchor)
                let periodEnd = calendar.date(byAdding: .day, value: count, to: start) ?? .distantFuture
                let neighbors = max(7, count)
                let days = (-neighbors...(count + neighbors - 1)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
                let gutterWidth: CGFloat = 52
                let minimumDayWidth: CGFloat = count > 7 ? 40 : 76
                let width = max(minimumDayWidth, (geometry.size.width - gutterWidth) / CGFloat(count))
                let visibleWidth = width * CGFloat(count)
                let renderWindow = CalendarRenderWindow.preloadedPeriods(visibleDays: count)
                let maximumAllDayCount = days.map { day in
                    store.plannerDaySnapshot(on: day, search: searchText).allDayTasks.count + store.plannerDaySnapshot(on: day, search: searchText).allDayEvents.count
                }.max() ?? 0
                let visibleAllDayRows = min(5, maximumAllDayCount)
                let measuredAllDayHeight = max(36, CGFloat(visibleAllDayRows) * 25 + 4)
                let allDayHeight = lockedAllDayHeight ?? measuredAllDayHeight
                VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: gutterWidth, height: 38)
                            CalendarSlidingStrip(pan: pan, columnWidth: width, visibleWidth: visibleWidth, leadingColumns: neighbors) {
                                HStack(spacing: 0) {
                                    ForEach(days, id: \.self) { day in
                                        VStack(spacing: 1) {
                                            Text(day.formatted(.dateTime.weekday(.abbreviated)))
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(HidigPalette.secondary)
                                            Text(day.formatted(.dateTime.day()))
                                                .font(.system(size: 13, weight: .semibold))
                                                .foregroundStyle(calendar.isDateInToday(day) ? HidigPalette.controlFill : HidigPalette.forest)
                                        }
                                        .frame(width: width, height: 38)
                                        .accessibilityHidden(day < start || day >= periodEnd)
                                    }
                                }
                            }
                            .frame(height: 38)
                        }
                        Divider()
                        HStack(spacing: 0) {
                            Text("Весь день")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(HidigPalette.secondary)
                                .frame(width: gutterWidth - 7, alignment: .trailing)
                                .padding(.trailing, 7)
                            CalendarSlidingStrip(pan: pan, columnWidth: width, visibleWidth: visibleWidth, leadingColumns: neighbors) {
                                HStack(spacing: 0) {
                                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                                        if renderWindow.contains(index - neighbors) {
                                        let allDayTasks = store.plannerDaySnapshot(on: day, search: searchText).allDayTasks
                                        ScrollView(.vertical) {
                                            LazyVStack(spacing: 2) {
                                                ForEach(allDayTasks) { CalendarCompactTask(task: $0) }
                                                ForEach(store.plannerDaySnapshot(on: day, search: searchText).allDayEvents, id: \.identity) { event in
                                                    Text(event.title).font(.system(size: 10)).lineLimit(1)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .background(HidigPalette.lettuce.opacity(0.5))
                                                }
                                            }
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 2)
                                        }
                                        .accessibilityLabel("Задачи на весь день, \(day.formatted(date: .complete, time: .omitted))")
                                        .accessibilityHidden(index < neighbors || index >= neighbors + count)
                                        .frame(width: width, height: allDayHeight, alignment: .top)
                                        .background(allDayDropDay == day ? HidigPalette.controlFill.opacity(0.18) : .clear)
                                        .overlay { if allDayDropDay == day {
                                            RoundedRectangle(cornerRadius: 4).stroke(HidigPalette.controlFill, lineWidth: 1.5)
                                                .allowsHitTesting(false)
                                        } }
                                        .overlay(alignment: .trailing) { Divider().opacity(0.65) }
                                        .dropDestination(for: String.self) { values, _ in
                                            guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                                            store.scheduleManagedTask(id, at: day, allDay: true)
                                            allDayDropDay = nil
                                            return true
                                        } isTargeted: { targeted in
                                            if targeted { allDayDropDay = day }
                                            else if allDayDropDay == day { allDayDropDay = nil }
                                        }
                                        } else {
                                            Color.clear.frame(width: width, height: allDayHeight).allowsHitTesting(false)
                                        }
                                    }
                                }
                            }
                            .frame(height: allDayHeight)
                            .background(GeometryReader { bounds in
                                Color.clear.preference(key: CalendarAllDayBounds.self, value: bounds.frame(in: .global))
                            })
                        }
                        Divider()
                        ScrollViewReader { reader in
                            ScrollView(.vertical) {
                                HStack(alignment: .top, spacing: 0) {
                                    VStack(spacing: 0) {
                                        ForEach(0..<24, id: \.self) { hour in
                                            Text(String(format: "%02d:00", hour)).font(.system(size: 10))
                                                .foregroundStyle(HidigPalette.secondary)
                                                .frame(width: gutterWidth - 7, height: CGFloat(hourHeight), alignment: .topTrailing)
                                                .padding(.trailing, 7)
                                                .id(hour)
                                        }
                                    }
                                    CalendarSlidingStrip(pan: pan, columnWidth: width, visibleWidth: visibleWidth, leadingColumns: neighbors) {
                                        HStack(alignment: .top, spacing: 0) {
                                            ForEach(Array(days.enumerated()), id: \.element) { index, day in
                                                let carriesDrag = movingTaskID.map { id in store.calendarTasks(on: day).contains { $0.id == id } } ?? false
                                                if renderWindow.contains(index - neighbors) || carriesDrag {
                                                    DayTimelineColumn(day: day, width: width, searchText: searchText, hourHeight: CGFloat(hourHeight), viewport: timelineViewport, movingTaskID: $movingTaskID, draftTask: $draftTask)
                                                        .accessibilityHidden(index < neighbors || index >= neighbors + count)
                                                        .zIndex(carriesDrag ? 1 : 0)
                                                } else {
                                                    Color.clear.frame(width: width, height: CGFloat(hourHeight) * 24).allowsHitTesting(false)
                                                }
                                            }
                                        }
                                    }
                                }
                                .background(PlannerScrollPosition(key: "calendar.timeline", workspace: workspace, initialY: CGFloat(hourHeight) * 6))
                                .background(CalendarScrollBinding(scroller: dragScroller))
                                .background(CalendarTimelineViewportBinding(viewport: timelineViewport, hourHeight: CGFloat(hourHeight)))
                            }
                            .overlay(alignment: .topLeading) { Color.clear.frame(width: 0, height: 0) }
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .updating($isMagnifying) { _, active, transaction in
                                        active = true; transaction.disablesAnimations = true
                                    }
                                    .onChanged { value in
                                        let oldHeight = hourHeight
                                        zoom.update(magnification: Double(value), persisted: persistedHourHeight)
                                        dragScroller.preserveZoom(from: oldHeight, to: hourHeight)
                                    }
                                    .onEnded { _ in finishMagnification() }
                            )
                            .transaction { transaction in
                                if isMagnifying { transaction.animation = nil }
                            }
                            .background(CalendarScrollBinding(scroller: dragScroller))
                            .onAppear {
                                dragScroller.changeDay = { [weak dragScroller, pan] direction in
                                    guard let dragScroller else { return }
                                    let currentWidth = max(1, dragScroller.dayWidth)
                                    if abs(pan.offset) < currentWidth * 6 { pan.offset -= CGFloat(direction) * currentWidth }
                                }
                            }
                        }
                }
                .frame(width: gutterWidth + width * CGFloat(count))
                .onAppear { updateCalendarDayWidth(width); pan.allDayHeight = allDayHeight }
                .onChange(of: allDayHeight) { pan.allDayHeight = $0 }
                .onChange(of: width) { newWidth in
                    updateCalendarDayWidth(newWidth)
                }
                .onChange(of: store.taskCalendarMode) { _ in
                    pan.offset = 0
                }
            }
        }
    }

    /// Input, autoscroll and all-day hit testing share the rendered column width.
    /// Use the observed value directly; a captured layout value can belong to the
    /// previous window size when macOS restores or resizes the window.
    private func updateCalendarDayWidth(_ width: CGFloat) {
        guard width.isFinite, width > 0 else { return }
        if pan.dayWidth != width { pan.resizeDayWidth(to: width) }
        dragScroller.dayWidth = width
        if allDayColumnWidth != width { allDayColumnWidth = width }
    }

    private func finishMagnification() {
        dragScroller.finishZoom()
        if let value = zoom.finish(), value != persistedHourHeight { persistedHourHeight = value }
    }

    private func settleCalendar(commitAnchor: Bool = false) {
        pan.settle(reduceMotion: reduceMotion) {
            if commitAnchor { commitInteraction() }
            // Resize only after horizontal movement finishes, keeping the time grid still.
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                lockedAllDayHeight = nil
            }
        }
    }
    private func commitInteraction() {
        if let anchor = interactionAnchor {
            workspace.anchor = anchor
            interactionAnchor = nil
        }
    }
    private func handleHorizontalScroll(delta: CGFloat, ended: Bool, cancelled: Bool, momentum: Bool, newGesture: Bool = false) {
        guard !isMagnifying else { return }
        // A gesture takes ownership from button navigation. Clear its queue too;
        // the interrupted completion is deliberately never invoked.
        navigation.cancel()
        pan.beginInput(momentum: momentum, newGesture: newGesture)
        if cancelled { settleCalendar(commitAnchor: true); return }
        let width = max(1, pan.dayWidth)
        let slides = workspace.mode == .day || workspace.mode == .fourDays || workspace.mode == .week
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if delta != 0 || (slides && abs(pan.offset) >= width) {
                if slides && interactionAnchor == nil {
                    interactionAnchor = workspace.anchor
                    lockedAllDayHeight = pan.allDayHeight
                }
                let nextOffset = pan.offset + delta
                if slides {
                    let rebased = CalendarNavigation.rebasedSwipe(offset: nextOffset, dayWidth: width)
                    if rebased.dayShift != 0 {
                        let anchor = calendar.date(byAdding: .day, value: rebased.dayShift,
                            to: interactionAnchor ?? workspace.anchor) ?? interactionAnchor
                        if let anchor { interactionAnchor = anchor }
                        // Warm projected tasks for the date now visible under the pointer.
                        store.prepareCalendarIndex(around: interactionAnchor)
                    }
                    pan.offset = rebased.remainingOffset
                } else {
                    pan.offset = min(width, max(-width, nextOffset))
                }
            }
            if ended {
                if let settled = CalendarNavigation.settledSwipe(offset: pan.offset, dayWidth: width) {
                    let next = CalendarNavigation.swipedAnchor(from: interactionAnchor ?? workspace.anchor,
                        mode: workspace.mode, direction: settled.direction, calendar: calendar)
                    if slides { interactionAnchor = next }
                    else { workspace.anchor = next }
                    pan.offset = settled.remainingOffset
                }
            }
        }
        if ended { settleCalendar(commitAnchor: true) }
    }

}

private struct CalendarModePicker: View {
    @Environment(\.hidigReduceMotion) private var reduceMotion
    @Binding var mode: TaskCalendarMode
    @Binding var dayCount: Int
    @State private var isPresented = false
    @State private var draft = ""

    private var title: String {
        mode == .fourDays ? CalendarDayCount.title(dayCount) : mode.title
    }

    var body: some View {
        Button { draft = "\(dayCount)"; isPresented.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.systemImage).frame(width: 15)
                Text(title).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(HidigPalette.secondary)
            }
            .hidigFont(size: 11, weight: .semibold)
            .padding(.horizontal, 11)
            .frame(minHeight: 34)
            .background(HidigPalette.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .top) {
            VStack(spacing: 3) {
                ForEach([TaskCalendarMode.day, .week, .month, .agenda]) { option in
                    optionButton(option)
                }
                Divider().padding(.vertical, 4)
                Button { select(.fourDays) } label: {
                    HStack(spacing: 9) {
                        Image(systemName: TaskCalendarMode.fourDays.systemImage).frame(width: 16)
                        Text("Несколько дней")
                        Spacer(minLength: 12)
                        if mode == .fourDays { Image(systemName: "checkmark").foregroundStyle(HidigPalette.controlFill) }
                    }
                    .hidigFont(size: 12, weight: mode == .fourDays ? .semibold : .regular)
                    .padding(.horizontal, 11)
                    .frame(height: 36)
                    .background(mode == .fourDays ? HidigPalette.lettuce.opacity(0.55) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 7) {
                    Button { changeDayCount(-1) } label: { Image(systemName: "minus") }
                        .buttonStyle(HidigIconButtonStyle())
                        .disabled(dayCount <= CalendarDayCount.bounds.lowerBound)
                        .accessibilityLabel("Уменьшить число дней")
                    TextField("Дни", text: $draft)
                        .textFieldStyle(HidigTextFieldStyle())
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                        .onTapGesture { mode = .fourDays }
                        .onSubmit(commitDraft)
                    Button { changeDayCount(1) } label: { Image(systemName: "plus") }
                        .buttonStyle(HidigIconButtonStyle())
                        .disabled(dayCount >= CalendarDayCount.bounds.upperBound)
                        .accessibilityLabel("Увеличить число дней")
                    Text("дней").hidigFont(size: 11).foregroundStyle(HidigPalette.secondary)
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 6)
                Text("От 2 до 14")
                    .hidigFont(size: 10)
                    .foregroundStyle(HidigPalette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 11)
            }
            .padding(7)
            .frame(width: 230)
            .background(HidigPalette.surface)
            .onDisappear { if mode == .fourDays { commitDraft() } }
        }
    }

    private func optionButton(_ option: TaskCalendarMode) -> some View {
        Button { select(option) } label: {
            HStack(spacing: 9) {
                Image(systemName: option.systemImage).frame(width: 16)
                Text(option.title)
                Spacer(minLength: 12)
                if option == mode { Image(systemName: "checkmark").foregroundStyle(HidigPalette.controlFill) }
            }
            .hidigFont(size: 12, weight: option == mode ? .semibold : .regular)
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(option == mode ? HidigPalette.lettuce.opacity(0.55) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func select(_ value: TaskCalendarMode) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { mode = value }
        if value != .fourDays { isPresented = false }
    }

    private func changeDayCount(_ delta: Int) {
        dayCount = CalendarDayCount.clamp(dayCount + delta)
        draft = "\(dayCount)"
        mode = .fourDays
    }

    private func commitDraft() {
        guard let value = Int(draft.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            draft = "\(dayCount)"
            return
        }
        dayCount = CalendarDayCount.clamp(value)
        draft = "\(dayCount)"
        mode = .fourDays
    }
}

private struct CalendarHorizontalScrollMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onBegin: () -> Bool
    let onScroll: (CGFloat, Bool, Bool, Bool) -> Void
    func makeCoordinator() -> CalendarHorizontalScrollCoordinator { CalendarHorizontalScrollCoordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); context.coordinator.view = view; context.coordinator.attach(); return view
    }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.onBegin = onBegin; context.coordinator.onScroll = onScroll; context.coordinator.setEnabled(isEnabled) }
    static func dismantleNSView(_ view: NSView, coordinator: CalendarHorizontalScrollCoordinator) { coordinator.detach() }

}

private struct CalendarCompactTask: View {
    @EnvironmentObject private var store: AppStore
    let task: ManagedTask
    private var tint: Color {
        Color(hex: store.taskList(id: task.listID)?.colorHex ?? "#6A9CC2")
    }
    var body: some View {
        HStack(spacing: 4) {
            TaskCompletionButton(task: task, store: store)
            Button { store.selectedTaskID = task.id } label: {
                Text(task.title).hidigFont(size: 12, weight: .medium).lineLimit(1)
                    .strikethrough(task.status == .completed || task.status == .wontDo)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(CalendarTaskPressStyle(tint: tint))
            .taskCard(task)
            .draggable(task.id.uuidString)
            if task.priority != .none { Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(task.priority.accent) }
        }
        .padding(.horizontal, 5)
        .frame(minHeight: 23)
        .background(tint.opacity(task.status == .completed ? 0.07 : 0.18))
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .taskPriorityBorder(task.priority, radius: 3)
        .opacity(task.status == .completed || task.status == .wontDo ? 0.55 : 1)
        .contextMenu { TaskContextActions(task: task) }
    }
}

private struct DayTimelineColumn: View {
    @EnvironmentObject private var workspace: PlannerWorkspace
    @State private var selectionStart: CGFloat?
    @State private var selectionEnd: CGFloat?
    @EnvironmentObject private var store: AppStore
    let day: Date
    let width: CGFloat
    let searchText: String
    let hourHeight: CGFloat
    @ObservedObject var viewport: CalendarTimelineViewport
    @Binding var movingTaskID: UUID?
    @Binding var draftTask: ManagedTask?
    private var dayEnd: Date { PlannerCalendar.current.date(byAdding: .day, value: 1, to: day)! }
    private func minute(_ date: Date) -> Double {
        if date <= day { return 0 }
        if date >= dayEnd { return 1440 }
        return Double(PlannerCalendar.current.component(.hour, from: date) * 60 + PlannerCalendar.current.component(.minute, from: date))
    }
    var body: some View {
        let snapshot = store.plannerDaySnapshot(on: day, search: searchText)
        let dayTasks = snapshot.timedTasks
        let dayEvents = snapshot.timedEvents
        let visible = viewport.visibleMinutes(hourHeight: hourHeight)
        let placements = snapshot.placements
        let visibleTasks = dayTasks.filter { task in
            guard let slot = snapshot.intervals[task.id.uuidString] else { return false }
            return visible.renders(id: task.id, start: slot.start, end: slot.end,
                movingID: movingTaskID, selectedID: store.selectedTaskID)
        }
        let visibleEvents = dayEvents.filter {
            guard let slot = snapshot.intervals[$0.identity] else { return false }
            return slot.start < visible.upper && slot.end > visible.lower
        }
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                var lines = Path()
                for hour in 0..<24 {
                    let y = CGFloat(hour) * hourHeight
                    lines.move(to: CGPoint(x: 0, y: y))
                    lines.addLine(to: CGPoint(x: width, y: y))
                }
                context.stroke(lines, with: .color(HidigPalette.line), lineWidth: 0.5)
            }
            .frame(width: width, height: hourHeight * 24)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(count: 2).onEnded { value in createDraft(y: value.location.y, endY: nil) })
            .simultaneousGesture(DragGesture(minimumDistance: 8)
                .onChanged { value in selectionStart = value.startLocation.y; selectionEnd = value.location.y }
                .onEnded { value in createDraft(y: min(value.startLocation.y, value.location.y), endY: max(value.startLocation.y, value.location.y)); selectionStart = nil; selectionEnd = nil })
            if let a = selectionStart, let b = selectionEnd {
                Rectangle().fill(HidigPalette.controlFill.opacity(0.2))
                    .frame(width: width, height: max(2, abs(b-a))).offset(y: min(a,b)).allowsHitTesting(false)
            }
            if CalendarDenseLayout.usesCanvas(taskCount: dayTasks.count,
                override: HidigRuntime.isIsolated ? HidigRuntime.environment["HIDIGFOCUS_CALENDAR_RENDERER"] : nil) {
                let items = visibleTasks.compactMap { task -> CalendarDenseItem? in
                    guard let interval = snapshot.intervals[task.id.uuidString] else { return nil }
                    return CalendarDenseItem(task: task, interval: interval,
                        placement: placements[task.id.uuidString] ?? PlannerPlacement(lane: 0, laneCount: 1),
                        width: width, hourHeight: hourHeight)
                }
                CalendarDenseTimeline(day: day, items: items, width: width, hourHeight: hourHeight, visible: visible,
                    movingTaskID: $movingTaskID, createDraft: createDraft)
            } else {
            ForEach(visibleTasks) { task in
                let slot = snapshot.intervals[task.id.uuidString] ?? PlannerInterval(id: task.id.uuidString, start: 0, end: 1)
                let placement = placements[task.id.uuidString] ?? PlannerPlacement(lane: 0, laneCount: 1)
                let laneWidth = (width - 4) / CGFloat(placement.laneCount)
                CalendarTaskBlock(task: task, store: store, workspace: workspace,
                    listColorHex: store.taskList(id: task.listID)?.colorHex ?? "#6A9CC2",
                    listName: store.taskList(id: task.listID)?.name ?? "Без списка", width: max(1, laneWidth * CGFloat(placement.span) - 3), height: CGFloat(slot.end - slot.start) / 60 * hourHeight, hourHeight: hourHeight, dayWidth: width, movingTaskID: $movingTaskID)
                    .offset(x: 2 + CGFloat(placement.lane) * laneWidth, y: CGFloat(slot.start) / 60 * hourHeight)
                    .zIndex(movingTaskID == task.id ? 10 : 0)
            }
            }
            ForEach(visibleEvents, id: \.identity) { event in
                eventBlock(event, interval: snapshot.intervals[event.identity], placement: placements[event.identity] ?? PlannerPlacement(lane: 0, laneCount: 1))
            }
            if PlannerCalendar.current.isDateInToday(day) {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Rectangle().fill(Color.red).frame(height: 1)
                        .offset(y: CGFloat(minute(context.date)) / 60 * hourHeight).allowsHitTesting(false)
                }
            }
        }.frame(width: width, height: hourHeight * 24)
            .overlay(alignment: .trailing) { Divider().opacity(0.7) }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { values, location in
                guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                let date = TaskEngine.calendarDropDate(on: day, yOffset: location.y, hourHeight: hourHeight, firstHour: 0, calendar: .current)
                store.scheduleManagedTask(id, at: date, allDay: false)
                return true
            }
    }
    private func eventBlock(_ event: GoogleCalendarEventSnapshot, interval: PlannerInterval?, placement: PlannerPlacement) -> some View {
        let laneWidth = (width - 4) / CGFloat(placement.laneCount)
        let eventWidth = max(1, laneWidth * CGFloat(placement.span) - 3)
        let eventHeight = max(1, CGFloat((interval?.end ?? minute(event.endDate)) - (interval?.start ?? minute(event.startDate))) / 60 * hourHeight)
        let x = 2 + CGFloat(placement.lane) * laneWidth
        let y = CGFloat(interval?.start ?? minute(event.startDate)) / 60 * hourHeight
        return Text(event.title).font(.system(size: 11)).padding(4)
            .frame(width: eventWidth, height: eventHeight, alignment: .topLeading)
            .background(HidigPalette.lettuce.opacity(0.72)).clipShape(RoundedRectangle(cornerRadius: 7))
            .offset(x: x, y: y)
    }

    private func createDraft(y: CGFloat, endY: CGFloat?) {
        let start = TaskEngine.calendarDropDate(on: day, yOffset: y, hourHeight: hourHeight, firstHour: 0)
        let finish = endY.map { TaskEngine.calendarDropDate(on: day, yOffset: $0, hourHeight: hourHeight, firstHour: 0) }
        let duration = max(15, Int((finish?.timeIntervalSince(start) ?? 1800) / 60))
        draftTask = ManagedTask(title: "", startDate: start, plannedEndDate: start.addingTimeInterval(Double(duration * 60)), durationMinutes: duration)
    }

}

private struct CalendarTaskBlock: View {
    @State private var isHovered = false
    @Environment(\.hidigTextScale) private var textScale
    @Environment(\.hidigFontPreference) private var fontPreference
    @Environment(\.calendarAutoscroll) private var autoscroll
    @Environment(\.calendarAllDayDrag) private var allDayDrag
    @State private var hoveringAllDay: Date?
    @State private var scrollTranslation = CGSize.zero
    @State private var gestureToken: Int?

    let task: ManagedTask
    let store: AppStore
    let workspace: PlannerWorkspace
    let listColorHex: String
    let listName: String
    let width: CGFloat
    let height: CGFloat
    let hourHeight: CGFloat
    let dayWidth: CGFloat
    @Binding var movingTaskID: UUID?
    @GestureState private var moveTranslation: CGSize = .zero
    @GestureState private var resizeTranslation: CGFloat = 0
    @GestureState private var topResizeTranslation: CGFloat = 0
    private var start: Date { task.startDate ?? task.dueDate ?? Date() }
    private var previewStart: Date {
        if moveTranslation != .zero {
            return TaskEngine.calendarMoveDate(
                from: start, translation: CGSize(width: moveTranslation.width + scrollTranslation.width, height: moveTranslation.height + scrollTranslation.height), dayWidth: dayWidth, hourHeight: hourHeight)
        }
        guard topResizeTranslation != 0 else { return start }
        let minutes = CalendarTaskResize.topOffset(originalDuration: task.durationMinutes,
            translation: topResizeTranslation + scrollTranslation.height, hourHeight: hourHeight)
        return PlannerCalendar.current.date(byAdding: .minute, value: minutes, to: start) ?? start
    }
    private var previewDuration: Int {
        if topResizeTranslation != 0 {
            return task.durationMinutes - CalendarTaskResize.topOffset(originalDuration: task.durationMinutes,
                translation: topResizeTranslation + scrollTranslation.height, hourHeight: hourHeight)
        }
        return resizeTranslation == 0 ? task.durationMinutes : CalendarTaskResize.duration(
            original: task.durationMinutes, translation: resizeTranslation + scrollTranslation.height, hourHeight: hourHeight)
    }
    private var displayedHeight: CGFloat {
        if topResizeTranslation != 0 {
            return CalendarTaskResize.topHeight(original: height, translation: topResizeTranslation + scrollTranslation.height, hourHeight: hourHeight)
        }
        return CalendarTaskResize.height(original: height, translation: resizeTranslation + scrollTranslation.height, hourHeight: hourHeight)
    }
    private var topVisualOffset: CGFloat {
        topResizeTranslation == 0 ? 0 : CalendarTaskResize.topVisualOffset(
            originalHeight: height, translation: topResizeTranslation + scrollTranslation.height, hourHeight: hourHeight)
    }
    private var tint: Color {
        Color(hex: listColorHex)
    }
    var body: some View {
        let layout = CalendarCardLayout(height: displayedHeight, width: width, scale: textScale,
            font: fontPreference, hasPriority: task.priority != .none)
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 3) {
                TaskCompletionButton(task: task, size: layout.completionSize, calendarSurface: true, store: store)
                VStack(alignment: .leading, spacing: layout.gap) {
                    Text(task.title).hidigFont(size: layout.titleFontSize, weight: .medium)
                        .lineLimit(layout.titleLines)
                        .fixedSize(horizontal: false, vertical: true)
                        .strikethrough(task.status == .completed || task.status == .wontDo)
                    if layout.showsTime {
                        let end = previewStart.addingTimeInterval(Double(previewDuration * 60))
                        Text("\(PlannerCalendar.time(previewStart))–\(PlannerCalendar.time(end))")
                            .hidigFont(size: layout.metadataFontSize).monospacedDigit()
                            .lineLimit(1).fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(HidigPalette.forest.opacity(0.82))
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { store.selectedTaskID = task.id }
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { store.selectedTaskID = task.id }
                .accessibilityLabel("Открыть задачу \(task.title), \(start.formatted(date: .complete, time: .omitted)), \(PlannerCalendar.time(start)), \(task.durationMinutes) минут")
                .accessibilityIdentifier("calendar.task.\(task.id.uuidString)")
                .simultaneousGesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .updating($moveTranslation) { value, state, _ in state = value.translation }
                    .onChanged { value in
                        if gestureToken == nil { gestureToken = workspace.cancellationToken }
                        guard gestureToken == workspace.cancellationToken else { return }
                        if movingTaskID != task.id { movingTaskID = task.id }
                        hoveringAllDay = allDayDrag.update(value.location, task)
                        if hoveringAllDay == nil { scrollTranslation = autoscroll(value.location, onChange: { scrollTranslation = $0 }) }
                    }
                    .onEnded { value in
                        defer { gestureToken = nil; movingTaskID = nil; scrollTranslation = .zero; hoveringAllDay = nil; _ = autoscroll(nil); _ = allDayDrag.update(nil, nil) }
                        guard gestureToken == workspace.cancellationToken else { return }
                        if let day = allDayDrag.update(value.location, task) {
                            store.scheduleManagedTask(task.id, at: day, allDay: true)
                            return
                        }
                        let latestScroll = autoscroll(value.location)
                        let translation = CGSize(width: value.translation.width + latestScroll.width, height: value.translation.height + latestScroll.height)
                        let date = TaskEngine.calendarMoveDate(from: start, translation: translation, dayWidth: dayWidth, hourHeight: hourHeight)
                        store.scheduleManagedTask(task.id, at: date, allDay: false)
                    })
                if task.priority != .none && width > 65 { Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(task.priority.accent).accessibilityLabel("Приоритет: \(task.priority.title)") }
            }.padding(layout.padding)
                .padding(.vertical, displayedHeight >= 28 ? 2 : 0)
        }
        .frame(width: width, height: displayedHeight, alignment: .topLeading)
        .clipped()
        .help("\(task.title)\n\(PlannerCalendar.time(start))–\(PlannerCalendar.time(start.addingTimeInterval(Double(task.durationMinutes * 60)))) · \(listName)")
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                Color.clear
                Capsule().fill(tint.opacity(isHovered || movingTaskID == task.id ? 0.65 : 0)).frame(width: min(26, width / 3), height: 3)
            }
            // The left 28 points belong to the completion button, even on a 15-minute block.
            .frame(width: max(0, width - 28), height: min(6, displayedHeight / 4))
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .updating($resizeTranslation) { value, state, transaction in
                    transaction.animation = nil
                    state = value.translation.height
                }
                .onChanged { value in
                    if gestureToken == nil { gestureToken = workspace.cancellationToken }
                    guard gestureToken == workspace.cancellationToken else { return }
                    if movingTaskID != task.id { movingTaskID = task.id }
                    scrollTranslation = autoscroll(value.location, horizontal: false, onChange: { scrollTranslation = $0 })
                }
                .onEnded { value in
                    defer { gestureToken = nil; movingTaskID = nil; scrollTranslation = .zero; _ = autoscroll(nil) }
                    guard gestureToken == workspace.cancellationToken else { return }
                    let duration = CalendarTaskResize.duration(original: task.durationMinutes,
                        translation: value.translation.height + autoscroll(value.location, horizontal: false).height, hourHeight: hourHeight)
                    if duration != task.durationMinutes {
                        store.scheduleManagedTask(task.id, at: start, durationMinutes: duration)
                    }
                })
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .onTapGesture { store.selectedTaskID = task.id }
            .help("Потяните нижний край: длительность с шагом 15 минут")
            .accessibilityHidden(true)
        }
        .overlay(alignment: .topTrailing) {
            ZStack {
                Color.clear
                Capsule().fill(tint.opacity(isHovered || movingTaskID == task.id ? 0.65 : 0)).frame(width: min(26, width / 3), height: 3)
            }
            .frame(width: max(0, width - 28), height: min(6, displayedHeight / 4))
            .contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .updating($topResizeTranslation) { value, state, transaction in
                    transaction.animation = nil
                    state = value.translation.height
                }
                .onChanged { value in
                    if gestureToken == nil { gestureToken = workspace.cancellationToken }
                    guard gestureToken == workspace.cancellationToken else { return }
                    if movingTaskID != task.id { movingTaskID = task.id }
                    scrollTranslation = autoscroll(value.location, horizontal: false, onChange: { scrollTranslation = $0 })
                }
                .onEnded { value in
                    defer { gestureToken = nil; movingTaskID = nil; scrollTranslation = .zero; _ = autoscroll(nil) }
                    guard gestureToken == workspace.cancellationToken else { return }
                    let offset = CalendarTaskResize.topOffset(originalDuration: task.durationMinutes,
                        translation: value.translation.height + autoscroll(value.location, horizontal: false).height, hourHeight: hourHeight)
                    guard offset != 0,
                          let newStart = PlannerCalendar.current.date(byAdding: .minute, value: offset, to: start) else { return }
                    store.scheduleManagedTask(task.id, at: newStart,
                        durationMinutes: task.durationMinutes - offset)
                })
            .onHover { hovering in
                if hovering { NSCursor.resizeUpDown.set() } else { NSCursor.arrow.set() }
            }
            .help("Потяните верхний край: изменить начало с шагом 15 минут")
            .accessibilityHidden(true)
        }
        .background(tint.opacity(movingTaskID == task.id ? 0.35 : 0.20))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(tint.opacity(0.55), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .taskPriorityBorder(task.priority, radius: 4)
        .shadow(color: .black.opacity(movingTaskID == task.id ? 0.2 : 0), radius: 6, y: 3)
        .overlay(alignment: .topLeading) {
            if moveTranslation != .zero || resizeTranslation != 0 || topResizeTranslation != 0 {
                let end = previewStart.addingTimeInterval(Double(previewDuration * 60))
                Text("\(PlannerCalendar.time(previewStart))–\(PlannerCalendar.time(end))")
                    .font(.system(size: 11, weight: .semibold)).fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(HidigPalette.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .offset(y: -27).allowsHitTesting(false)
            }
        }
        .offset(CGSize(width: moveTranslation.width,
            height: moveTranslation.height + (moveTranslation == .zero ? 0 : scrollTranslation.height) + topVisualOffset))
        .onChange(of: moveTranslation) { value in
            if value == .zero, movingTaskID == task.id { movingTaskID = nil; hoveringAllDay = nil; _ = autoscroll(nil); _ = allDayDrag.update(nil, nil) }
        }
        .onChange(of: resizeTranslation) { value in
            if value == 0, movingTaskID == task.id { movingTaskID = nil; scrollTranslation = .zero; _ = autoscroll(nil) }
        }
        .onChange(of: topResizeTranslation) { value in
            if value == 0, movingTaskID == task.id { movingTaskID = nil; scrollTranslation = .zero; _ = autoscroll(nil) }
        }
        .transaction { $0.animation = nil }
        .onHover { isHovered = $0 }
        .opacity(hoveringAllDay != nil ? 0 : 1)
        .taskCard(task)
        .contextMenu { TaskContextActions(task: task) }
    }

}
private struct TaskMonthView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let anchor: Date
    let searchText: String
    var body: some View {
        let interval = PlannerCalendar.current.dateInterval(of: .month, for: anchor)
        let days = interval.map { Date.dates(from: $0.start, to: $0.end) } ?? []
        let leading = interval.map { (PlannerCalendar.current.component(.weekday, from: $0.start) - PlannerCalendar.current.firstWeekday + 7) % 7 } ?? 0
        ScrollView { LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
            ForEach(0..<7, id: \.self) { index in
                Text(PlannerCalendar.current.shortWeekdaySymbols[(PlannerCalendar.current.firstWeekday - 1 + index) % 7])
                    .hidigFont(size: 10, weight: .semibold)
            }
            ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 90) }
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.formatted(.dateTime.day())).hidigFont(size: 11, weight: .bold)
                    ForEach(store.plannerCalendarTasks(on: day, search: searchText).prefix(3)) { task in
                        Button { store.selectedTaskID = task.id } label: {
                            HStack(spacing: 3) {
                                if task.priority != .none { Image(systemName: "flag.fill").foregroundStyle(task.priority.accent) }
                                Text(task.title).hidigFont(size: 9).lineLimit(1)
                            }.padding(3).frame(maxWidth: .infinity, alignment: .leading)
                                .taskPriorityBorder(task.priority, radius: 3)
                        }
                        .buttonStyle(CalendarTaskPressStyle(tint: HidigPalette.controlFill))
                        .taskCard(task)
                        .draggable(task.id.uuidString)
                        .contextMenu { TaskContextActions(task: task) }
                    }
                    ForEach(store.plannerEvents(on: day, search: searchText).prefix(2), id: \.id) { Text($0.title).font(.system(size: 10)).lineLimit(1).foregroundStyle(.secondary) }
                    if store.plannerCalendarTasks(on: day, search: searchText).count > 3 {
                        Button("Ещё \(store.plannerCalendarTasks(on: day, search: searchText).count - 3)") {
                            store.taskCalendarAnchor = day
                            store.taskCalendarMode = .day
                        }.buttonStyle(.plain).hidigFont(size: 9)
                    }
                    Spacer()
                }
                .padding(6)
                .frame(minHeight: 90)
                .background(HidigPalette.surface)
                .dropDestination(for: String.self) { values, _ in
                    guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                    store.scheduleManagedTask(id, at: day, allDay: true)
                    return true
                }
            }
        }
        .padding(12) }
    }
}

private struct TaskAgendaView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let anchor: Date
    let searchText: String
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(0..<30, id: \.self) { offset in
                    let day = PlannerCalendar.current.date(byAdding: .day, value: offset, to: PlannerCalendar.current.startOfDay(for: anchor)) ?? anchor
                    let tasks = store.plannerCalendarTasks(on: day, search: searchText)
                    let events = store.plannerEvents(on: day, search: searchText)
                    if !tasks.isEmpty || !events.isEmpty {
                        Text(day.formatted(date: .complete, time: .omitted)).font(.headline).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                        ForEach(tasks) { TaskRow(task: $0) }
                        ForEach(events, id: \.identity) { event in
                            Text("\(event.title) · \(event.isAllDay ? "Весь день" : PlannerCalendar.time(event.startDate))").frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }.padding(14)
        }
    }
}

private struct EisenhowerMatrixView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    quadrantView(.urgentImportant)
                    quadrantView(.important)
                }
                HStack(alignment: .top, spacing: 12) {
                    quadrantView(.urgent)
                    quadrantView(.neither)
                }
            }.padding(14)
        }
    }

    private func quadrantView(_ quadrant: EisenhowerQuadrant) -> some View {
        let tasks = store.matrixTasks(in: quadrant)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(quadrant.title).hidigFont(size: 14, weight: .bold)
                Text("\(tasks.count)")
                    .hidigFont(size: 12, weight: .medium)
                    .foregroundStyle(HidigPalette.secondary)
            }
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(tasks) { task in
                    TaskRow(task: task)
                        .onDrag { NSItemProvider(object: task.id.uuidString as NSString) }
                }
            }
            Spacer(minLength: 40)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
        .background(HidigPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .dropDestination(for: String.self) { values, _ in
            guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
            store.setTaskQuadrant(id, quadrant)
            return true
        }
    }
}

private struct TaskDetailView: View {
    @EnvironmentObject private var store: AppStore
    @State private var draft: ManagedTask
    @State private var baseline: ManagedTask
    @State private var showsDate = false
    @State private var editsNotes: Bool
    @State private var pendingSave: Task<Void, Never>?
    @State private var showsSubtasksEditor = false
    @FocusState private var titleFocused: Bool
    @State private var editScope: TaskEditScope = .occurrence
    @State private var replaceExceptions = false
    private var isRecurring: Bool { store.seriesRoot(for: baseline) != nil }
    private var missingSeriesDate: Bool {
        isRecurring && editScope != .occurrence && draft.repeatRule != nil && draft.startDate == nil && draft.dueDate == nil
    }
    @Binding private var showsDetails: Bool
    @Binding private var isListPickerPresented: Bool
    private let cardSize: CGSize
    init(task: ManagedTask, showsDetails: Binding<Bool>, isListPickerPresented: Binding<Bool>, cardSize: CGSize) {
        self._showsDetails = showsDetails
        self._isListPickerPresented = isListPickerPresented
        self.cardSize = cardSize
        _draft = State(initialValue: task)
        _baseline = State(initialValue: task)
        _editsNotes = State(initialValue: task.description.isEmpty && !task.notes.isEmpty)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                TaskCompletionButton(task: store.resolvedTask(id: draft.id) ?? draft, store: store)
                Divider().frame(height: 16)
                Button { showsDate = true } label: {
                    Label(draft.scheduleLabel, systemImage: "calendar")
                        .hidigFont(size: 12).lineLimit(1)
                        .foregroundStyle(draft.isOverdue ? HidigPalette.warning : HidigPalette.forest)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).help(draft.scheduleLabel)
                    .popover(isPresented: $showsDate, arrowEdge: .bottom) {
                        TaskDateEditor(task: $draft, allowsRepeat: !isRecurring || editScope != .occurrence) { showsDate = false }
                    }
                TaskPriorityPicker(priority: $draft.priority)
                Button { if !isRecurring { save() }; store.selectedTaskID = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 12)).frame(width: 24, height: 28)
                }.buttonStyle(.plain).foregroundStyle(HidigPalette.secondary).help("Закрыть карточку")
                    .accessibilityLabel("Закрыть карточку")
            }.padding(.horizontal, 18).padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let parentID = draft.parentTaskID, let parent = store.task(id: parentID) {
                        Button { save(); store.selectedTaskID = parentID } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left").font(.system(size: 9))
                                Text(parent.title).lineLimit(1)
                            }.hidigFont(size: 12).foregroundStyle(HidigPalette.secondary)
                        }.buttonStyle(.plain).help("Открыть родительскую задачу")
                    }
                    if isRecurring {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("Изменить", selection: $editScope) {
                                ForEach(TaskEditScope.allCases) { scope in Text(scope.title).tag(scope) }
                            }.accessibilityIdentifier("task.editScope")
                            if editScope != .occurrence {
                                Toggle("Заменить индивидуальные правки", isOn: $replaceExceptions)
                                    .accessibilityIdentifier("task.replaceExceptions")
                                Text("Выполненные и пропущенные экземпляры сохраняются. Индивидуальные правки сохраняются, кроме открытого экземпляра.")
                                    .font(.caption).foregroundStyle(HidigPalette.secondary)
                            }
                            if let rule = store.seriesRule(for: baseline), RecurrenceProjection.supportedRule(rule) == nil {
                                Text("Это правило TickTick не поддерживает расчёт будущих экземпляров. Выберите локальное правило повторения для серии.")
                                    .font(.caption).foregroundStyle(HidigPalette.warning)
                            }
                            if draft.sourceName == "TickTick" {
                                Text("Только в hidigFocus: серия и исключения не отправляются в TickTick. Локальная версия серии имеет приоритет над изменениями TickTick; задачи с другим ID импортируются отдельно.")
                                    .font(.caption).foregroundStyle(HidigPalette.secondary)
                            }
                        }
                    }
                    if missingSeriesDate {
                        Text("Укажите дату начала серии или отключите повторение.").font(.caption).foregroundStyle(HidigPalette.warning)
                    }
                    TextField("Название задачи", text: $draft.title, axis: .vertical)
                        .hidigFont(size: 19, weight: .semibold).lineLimit(1...5).textFieldStyle(.plain)
                        .accessibilityLabel("Название задачи")
                        .focused($titleFocused)
                    let children = store.subtasks(of: draft.id)
                    let hasSubtasks = !children.isEmpty || showsSubtasksEditor
                    TaskNotesEditor(text: editsNotes ? $draft.notes : $draft.description)
                        .frame(height: draft.description.isEmpty && draft.notes.isEmpty ? 36 : (hasSubtasks || showsDetails ? 90 : 110))
                    if hasSubtasks {
                        TaskSubtasksSection(parentID: draft.id, beforeOpening: save)
                    }
                    TaskChecklistSection(task: $draft)
                    if showsDetails {
                        TaskDetailExtras(task: $draft)
                        TaskSection(title: "Заметки и метки") {
                            TextField("Дополнительные заметки", text: editsNotes ? $draft.description : $draft.notes, axis: .vertical)
                                .textFieldStyle(HidigTextFieldStyle())
                            TextField("Метки через запятую", text: Binding(get: { draft.tags.joined(separator: ", ") },
                                set: { draft.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }))
                                .textFieldStyle(HidigTextFieldStyle())
                        }
                        if draft.sourceName == "TickTick" {
                            Text("Изменения сохраняются в hidigFocus.").hidigFont(size: 10).foregroundStyle(HidigPalette.secondary)
                        }
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            }
            if isRecurring {
                Divider()
                HStack {
                    Button("Отмена") { store.selectedTaskID = nil }.buttonStyle(SecondaryButtonStyle())
                    Spacer()
                    Button("Сохранить изменения") { save(); store.selectedTaskID = nil }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.return, modifiers: .command)
                        .accessibilityIdentifier("task.saveSeriesEdits")
                        .disabled(draft == baseline || missingSeriesDate || draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(.horizontal, 18).padding(.vertical, 9)
            }
            Divider()
            HStack(spacing: 8) {
                TaskListPicker(folders: store.taskFolders, lists: store.taskLists, selection: $draft.listID, isPresented: $isListPickerPresented)
                    .frame(maxWidth: 180)
                Spacer(minLength: 4)
                Button { showsDetails.toggle() } label: {
                    Image(systemName: "list.bullet").foregroundStyle(showsDetails ? HidigPalette.controlFill : HidigPalette.secondary)
                        .frame(width: 28, height: 28)
                }.buttonStyle(.plain).help(showsDetails ? "Скрыть подробности" : "Подробности задачи")
                    .accessibilityLabel(showsDetails ? "Скрыть подробности" : "Подробности задачи")
                Menu {
                    Button("Добавить подзадачу", systemImage: "plus") { showsSubtasksEditor = true; showsDetails = true }
                    Button("В корзину", systemImage: "trash", role: .destructive) { save(); store.requestTaskDeletion([draft.id]) }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
                    .menuStyle(.borderlessButton).fixedSize().help("Действия с задачей").accessibilityLabel("Действия с задачей")
                SaveStatusView()
            }.padding(.horizontal, 15).padding(.vertical, 9)
        }.frame(width: cardSize.width, height: cardSize.height)
            .hidigFont(size: 13)
            .background(HidigPalette.surface)
            .taskPriorityBorder(draft.priority, radius: 14)
            .onAppear {
                titleFocused = true
                if isRecurring { let rule = store.seriesRule(for: baseline); baseline.repeatRule = rule; draft.repeatRule = rule }
            }
            .onExitCommand { [deletionWasPresented = !store.pendingTaskDeletion.isEmpty] in
                if deletionWasPresented { store.pendingTaskDeletion = [] }
                else if isListPickerPresented { isListPickerPresented = false }
                else { if !isRecurring { save() }; store.selectedTaskID = nil }
            }
            .onChange(of: editScope) { scope in
                if scope == .occurrence { draft.repeatRule = baseline.repeatRule }
            }
            .onChange(of: draft) { _ in
                pendingSave?.cancel()
                guard !isRecurring else { return }
                pendingSave = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
                    save()
                }
            }
            .onDisappear { pendingSave?.cancel(); if !isRecurring { save() } }
    }
    private func save() {
        guard draft != baseline else { return }
        if isRecurring && editScope != .occurrence {
            store.updateSeriesEdits(from: baseline, to: draft, scope: editScope, replaceExceptions: replaceExceptions)
        } else {
            store.updateManagedTaskEdits(from: baseline, to: draft)
        }
        baseline = draft
    }
}

struct TaskRepeatEditor: View {
    @Binding var rule: TaskRepeatRule?
    let start: Date
    private var frequency: Binding<String> {
        Binding(get: { rule?.frequency.rawValue ?? "none" }, set: { raw in
            rule = TaskRepeatFrequency(rawValue: raw).map { TaskRepeatRule(frequency: $0) }
        })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HidigMenuPicker(
                options: [HidigMenuOption(id: "none", title: "Не повторять", systemImage: "repeat")]
                    + TaskRepeatFrequency.allCases.map { HidigMenuOption(id: $0.rawValue, title: $0.title, systemImage: "repeat") },
                selection: frequency)
            if let value = rule {
                HStack {
                    Text("Интервал: \(value.interval)").hidigFont(size: 12)
                    Spacer()
                    Button { rule?.interval = max(1, value.interval - 1); rule?.sourceRule = nil } label: { Image(systemName: "minus") }
                        .buttonStyle(HidigIconButtonStyle()).disabled(value.interval <= 1).help("Уменьшить интервал")
                    Button { rule?.interval = min(99, value.interval + 1); rule?.sourceRule = nil } label: { Image(systemName: "plus") }
                        .buttonStyle(HidigIconButtonStyle()).disabled(value.interval >= 99).help("Увеличить интервал")
                }
                if value.frequency == .weekly {
                    HStack(spacing: 3) {
                        ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { day in
                            ChoicePill(title: PlannerCalendar.current.shortWeekdaySymbols[day - 1], isSelected: value.weekdays.contains(day)) {
                                if rule?.weekdays.contains(day) == true { rule?.weekdays.remove(day) }
                                else { rule?.weekdays.insert(day) }
                                rule?.sourceRule = nil
                            }
                        }
                    }
                }
                Toggle("Дата окончания повторений", isOn: Binding(
                    get: { rule?.endDate != nil },
                    set: { rule?.endDate = $0 ? max(start, Date()) : nil; rule?.sourceRule = nil })).toggleStyle(TaskCheckboxStyle())
                if value.endDate != nil {
                    HidigDateButton(date: Binding(get: { rule?.endDate ?? start },
                        set: { rule?.endDate = $0; rule?.sourceRule = nil }), compact: true)
                }
                Text(value.sourceRule == nil
                     ? "Будущие повторения отображаются в календаре. Каждый экземпляр можно изменить отдельно."
                     : "Повторение импортировано из TickTick. Выберите правило для локального повторения.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.font(.system(size: 11))
    }
}

struct PomodoroControls: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let active: ActivePomodoro

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = max(0, Int((active.pausedAt ?? context.date).timeIntervalSince(active.startedAt)) - active.accumulatedPauseSeconds)
            let remaining = max(0, active.targetSeconds - elapsed)
            VStack(spacing: 8) {
                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                    .hidigFont(size: 28, weight: .bold, design: .rounded)
                HStack {
                    if active.pausedAt == nil {
                        Button("Пауза") { store.pausePomodoro() }.buttonStyle(SecondaryButtonStyle())
                    } else {
                        Button("Продолжить") { store.resumePomodoro() }.buttonStyle(SecondaryButtonStyle())
                    }
                    Button("Завершить") { store.finishPomodoro() }.buttonStyle(PrimaryButtonStyle())
                    Button("Отмена") { store.finishPomodoro(completed: false) }.buttonStyle(GhostButtonStyle())
                }
            }
        }
    }
}

private extension Int {
    func roundedToNearest(_ multiple: Int) -> Int {
        guard multiple > 0 else { return self }
        return Int((Double(self) / Double(multiple)).rounded()) * multiple
    }
}

private extension Date {
    static func dates(from start: Date, to end: Date) -> [Date] {
        var values: [Date] = []
        var cursor = start
        while cursor < end {
            values.append(cursor)
            cursor = PlannerCalendar.current.date(byAdding: .day, value: 1, to: cursor) ?? end
        }
        return values
    }
}

private struct CalendarTaskCreation: View {
    @EnvironmentObject private var store: AppStore
    @State var draft: ManagedTask
    let dismiss: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Новая задача").font(.headline)
            TextField("Название", text: $draft.title).textFieldStyle(.roundedBorder)
            Text(draft.scheduleLabel).font(.caption)
            HStack {
                Button("Отмена", action: dismiss).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Создать") {
                    guard store.createPlannerTask(draft) != nil else { return }; dismiss()
                }.disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).keyboardShortcut(.defaultAction)
            }
        }.padding(20).frame(width: 400).background(HidigPalette.surface)
    }
}
