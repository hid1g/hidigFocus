import AppKit
import SwiftUI
import UniformTypeIdentifiers
import QuartzCore

struct TasksView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @State private var quickTaskTitle = ""
    @EnvironmentObject private var workspace: PlannerWorkspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    private var searchText: String { workspace.search }
    @AppStorage("taskListsVisible") private var taskListsVisible = false
    @AppStorage("taskListsWidth") private var taskListsWidth = 210.0

    var body: some View {
        VStack(spacing: 0) {
            header
            PlannerFilterMenu()
            if !workspace.selectedIDs.isEmpty { BulkTaskActions() }
            Divider().overlay(HidigPalette.line)
            HStack(spacing: 0) {
                if taskListsVisible && store.tasksPresentation != .calendar {
                    TaskNavigationColumn().frame(width: taskListsWidth)
                    PanelResizeHandle(width: $taskListsWidth, bounds: 170...320)
                }
                center
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(HidigPalette.canvas)
        .frame(minWidth: 620)
        .background(Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: [.command]).hidden())
        .overlayPreferenceValue(TaskCardAnchors.self) { PlannerCardHost(anchors: $0) }
        .onDeleteCommand { if !workspace.selectedIDs.isEmpty { store.bulkTrash(workspace.selectedIDs) } }
        .onExitCommand { workspace.selectedIDs = []; store.selectedTaskID = nil }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if store.tasksPresentation != .calendar {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { taskListsVisible.toggle() }
                } label: { Image(systemName: "sidebar.left") }
                    .buttonStyle(HidigIconButtonStyle())
                    .help(taskListsVisible ? "Скрыть списки" : "Показать списки")
                    .accessibilityLabel(taskListsVisible ? "Скрыть списки" : "Показать списки")
            }
            Text(store.tasksPresentation == .calendar
                 ? store.taskCalendarAnchor.formatted(.dateTime.month(.wide).year()) : "Задачи")
                .hidigFont(size: 19, weight: .semibold)
            Spacer()
            PlannerSearchField(focus: $searchFocused)
                .frame(minWidth: 90, maxWidth: 150)
            SyncButton(showTitle: false)
            TasksPresentationControl(selection: $workspace.presentation)
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 10)
        .foregroundStyle(HidigPalette.forest)
    }

    @ViewBuilder
    private var center: some View {
        Group {
            switch store.tasksPresentation {
            case .list:
                TaskListColumn(searchText: searchText, quickTaskTitle: $quickTaskTitle)
            case .calendar:
                TaskCalendarView(searchText: searchText)
            case .matrix:
                EisenhowerMatrixView()
            }
        }
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: store.tasksPresentation)
    }

}

/// Typing stays local to the field; data filtering runs after a short pause.
private struct PlannerSearchField: View {
    @EnvironmentObject private var workspace: PlannerWorkspace
    let focus: FocusState<Bool>.Binding
    @State private var draft = ""
    @State private var applied = ""
    var body: some View {
        TextField("Поиск", text: $draft)
            .textFieldStyle(HidigTextFieldStyle()).focused(focus)
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
}

private struct TasksPresentationControl: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var selection: TasksPresentation

    var body: some View {
        HStack(spacing: 3) {
            ForEach(TasksPresentation.allCases) { option in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { selection = option }
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                        .hidigFont(size: 10, weight: selection == option ? .semibold : .medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .padding(.horizontal, 7)
                        .frame(height: 32)
                        .background(selection == option ? HidigPalette.surfaceRaised : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(HidigPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 11))
    }
}

private struct TaskNavigationColumn: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @State private var newListName = ""

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
                    ForEach(store.taskFolders) { folder in
                        Button {
                            withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.9)) {
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
                        if !folder.isCollapsed {
                            ForEach(store.taskLists.filter { $0.folderID == folder.id }) { list in
                                listRow(list).padding(.leading, 14)
                            }
                            .transition(.opacity.combined(with: .move(edge: .top)))
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
        navRow(title: list.name, icon: list.isPinned ? "pin.fill" : "list.bullet", selection: .list(list.id))
            .draggable("list:\(list.id)")
            .dropDestination(for: String.self) { values, _ in
                guard let raw = values.first, raw.hasPrefix("list:"), let id = UUID(uuidString: String(raw.dropFirst(5))) else { return false }
                store.reorderList(id, before: list.id); return true
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
    private var tasks: [ManagedTask] {
        var matching = store.visibleManagedTasks.filter {
            store.plannerMatches($0, search: searchText, includeTrash: store.taskSidebarSelection == .trash, includeCompleted: store.taskSidebarSelection == .completed)
        }
        var included = Set(matching.map(\.id))
        // Abandoned source parents provide context for their still-visible children.
        for child in matching {
            var parentID = child.parentTaskID
            while let id = parentID, let parent = store.task(id: id), parent.status == .wontDo, included.insert(id).inserted {
                matching.append(parent); parentID = parent.parentTaskID
            }
        }
        return workspace.filter.sorted(matching, by: workspace.sort)
    }

    var body: some View {
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
            if tasks.isEmpty {
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
                        let tree = PlannerTaskTree.rows(tasks, collapsed: workspace.collapsedTaskIDs)
                        ForEach(workspace.sort == .date ? ["Просрочено", "Сегодня", "Предстоящие", "Без срока"] : ["Задачи"], id: \.self) { section in
                            let rows = section == "Задачи" ? tree : tree.filter { group(for: $0.root) == section }
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
                                            Button {
                                                if workspace.collapsedTaskIDs.contains(row.id) { workspace.collapsedTaskIDs.remove(row.id) }
                                                else { workspace.collapsedTaskIDs.insert(row.id) }
                                            } label: {
                                                Image(systemName: workspace.collapsedTaskIDs.contains(row.id) ? "chevron.right" : "chevron.down")
                                            }.buttonStyle(.plain).accessibilityLabel(workspace.collapsedTaskIDs.contains(row.id) ? "Развернуть подзадачи" : "Свернуть подзадачи")
                                        } else { Color.clear.frame(width: 12) }
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

    private func group(for task: ManagedTask) -> String {
        guard let date = task.dueDate ?? task.startDate else { return "Без срока" }
        let today = PlannerCalendar.current.startOfDay(for: Date())
        if task.status == .active && task.dueDate != nil && (task.isAllDay ? date < today : date < Date()) { return "Просрочено" }
        return PlannerCalendar.current.isDateInToday(date) ? "Сегодня" : "Предстоящие"
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
    @EnvironmentObject private var workspace: PlannerWorkspace
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let task: ManagedTask

    var body: some View {
        HStack(spacing: 10) {
            Button { toggleSelection() } label: { Image(systemName: workspace.selectedIDs.contains(task.id) ? "checkmark.circle.fill" : "circle") }
                .buttonStyle(.plain).help("Выбрать задачу").accessibilityLabel("Выбрать \(task.title)")
            TaskCompletionButton(task: task)
            Button {
                if NSEvent.modifierFlags.contains(.command) { toggleSelection() }
                else if NSEvent.modifierFlags.contains(.shift), let last = workspace.lastSelectedID {
                    let ids = workspace.filter.sorted(store.visibleManagedTasks, by: workspace.sort).map(\.id)
                    if let a = ids.firstIndex(of: last), let b = ids.firstIndex(of: task.id) { workspace.selectedIDs.formUnion(ids[min(a,b)...max(a,b)]) }
                } else { workspace.lastSelectedID = task.id; store.selectedTaskID = task.id }
            } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title).strikethrough(task.status == .completed)
                        .hidigFont(size: 14, weight: .medium).lineLimit(2)
                    HStack(spacing: 10) {
                        Label(task.scheduleLabel, systemImage: "calendar")
                            .foregroundStyle(task.isOverdue ? HidigPalette.warning : HidigPalette.secondary)
                        Text(store.taskList(id: task.listID)?.name ?? "Входящие")
                            .foregroundStyle(HidigPalette.secondary)
                        if task.status == .wontDo { Text("Отменена в TickTick") }
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
        .background(workspace.selectedIDs.contains(task.id) ? HidigPalette.surfaceRaised : HidigPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .taskPriorityBorder(task.priority, radius: 8)
        .draggable(task.id.uuidString)
        .contextMenu { TaskContextActions(task: task) }
    }
    private func toggleSelection() {
        if workspace.selectedIDs.contains(task.id) { workspace.selectedIDs.remove(task.id) }
        else { workspace.selectedIDs.insert(task.id) }
        workspace.lastSelectedID = task.id
    }

}

private struct TaskCompletionButton: View {
    @EnvironmentObject private var store: AppStore
    let task: ManagedTask
    var body: some View {
        Button {
            if task.status == .trashed { store.restoreManagedTask(task.id) }
            else { store.setManagedTaskCompleted(task.id, completed: task.status != .completed) }
        } label: {
            HidigCheckmarkBox(isChecked: task.status == .completed, size: 16)
                .padding(2).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(task.status == .completed ? "Вернуть в активные" : "Выполнить задачу")
        .accessibilityLabel(task.status == .completed ? "Вернуть в активные" : "Выполнить задачу")
    }
}

private struct TaskCardAnchors: PreferenceKey {
    static var defaultValue: [UUID: Anchor<CGRect>] = [:]
    static func reduce(value: inout [UUID: Anchor<CGRect>], nextValue: () -> [UUID: Anchor<CGRect>]) { value.merge(nextValue(), uniquingKeysWith: { _, latest in latest }) }
}
private struct TaskCardModifier: ViewModifier {
    let task: ManagedTask
    func body(content: Content) -> some View {
        content.anchorPreference(key: TaskCardAnchors.self, value: .bounds) { [task.id: $0] }
    }
}
private struct PlannerCardHost: View {
    @EnvironmentObject private var store: AppStore
    let anchors: [UUID: Anchor<CGRect>]
    @State private var lastRect: CGRect?
    @State private var showsDetails = false
    var body: some View {
        GeometryReader { geometry in
            if let id = store.selectedTaskID, let task = store.task(id: id) {
                let rect = anchors[id].map { geometry[$0] } ?? lastRect ?? CGRect(x: geometry.size.width / 2, y: geometry.size.height / 2, width: 0, height: 0)
                let placement = TaskCardPlacement.frame(anchor: rect,
                    bounds: CGRect(origin: .zero, size: geometry.size),
                    size: CGSize(width: 400, height: showsDetails ? 530 : 310))
                ZStack(alignment: .topLeading) {
                    Color.clear.contentShape(Rectangle())
                        .onTapGesture { store.selectedTaskID = nil }
                        .accessibilityHidden(true)
                    TaskDetailView(task: task, showsDetails: $showsDetails, cardSize: placement.size).id(id)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .shadow(color: .black.opacity(0.16), radius: 18, y: 5)
                        .position(x: placement.midX, y: placement.midY)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Карточка задачи")
                        .background(TaskCardEscapeMonitor { store.selectedTaskID = nil })
                }.frame(width: geometry.size.width, height: geometry.size.height)
                    .onAppear { lastRect = rect }
                    .onChange(of: rect) { if anchors[id] != nil { lastRect = $0 } }
            }
        }
        .onChange(of: store.selectedTaskID) { id in
            showsDetails = false
            if id == nil { lastRect = nil }
        }
    }
}

private extension View {
    func taskCard(_ task: ManagedTask) -> some View { modifier(TaskCardModifier(task: task)) }
}

private struct TaskContextActions: View {
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
        Button("Не буду делать", systemImage: "xmark.square") {
            edit { $0.status = .wontDo }
        }
        Divider()
        Button("Удалить", systemImage: "trash", role: .destructive) { store.trashManagedTask(task.id) }
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
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(tint.opacity(configuration.isPressed ? 0.18 : 0))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private final class CalendarPanState: ObservableObject {
    @Published var offset: CGFloat = 0
    var dayWidth: CGFloat = 200
    var allDayHeight: CGFloat = 36
    private var timer: Timer?
    func interrupt() { timer?.invalidate(); timer = nil }
    func settle(reduceMotion: Bool, completion: (() -> Void)? = nil) {
        interrupt()
        guard !reduceMotion, abs(offset) > 0.1 else { offset = 0; completion?(); return }
        let start = offset, began = CACurrentMediaTime()
        let rate = Double(NSScreen.main?.maximumFramesPerSecond ?? 60)
        let timer = Timer(timeInterval: 1 / max(60, rate), repeats: true) { [weak self] _ in
            guard let self else { return }
            let fraction = min(1, (CACurrentMediaTime() - began) / 0.28)
            self.offset = start * CGFloat(pow(1 - fraction, 3))
            if fraction >= 1 { self.interrupt(); self.offset = 0; completion?() }
        }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    deinit { timer?.invalidate() }
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
            .offset(x: pan.offset - columnWidth * CGFloat(leadingColumns))
            .frame(width: visibleWidth, alignment: .leading)
            .clipped()
    }
}

private struct TaskCalendarView: View {
    @EnvironmentObject private var workspace: PlannerWorkspace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedDay: Date?
    @State private var draftTask: ManagedTask?
    @StateObject private var dragScroller = CalendarDragScroller()
    @EnvironmentObject private var store: AppStore
    let searchText: String
    @AppStorage("calendarHourHeight") private var hourHeight = 72.0
    @State private var magnificationStart: Double?
    @State private var isMagnifying = false
    // Frame updates are observed by the strips, not by the calendar content.
    @State private var pan = CalendarPanState()
    @State private var movingTaskID: UUID?
    @State private var interactionAnchor: Date?
    @State private var lockedAllDayHeight: CGFloat?
    private let calendar = PlannerCalendar.current

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { navigate(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Предыдущий период")
                Button("Сегодня") { pan.interrupt(); pan.offset = 0; interactionAnchor = nil; lockedAllDayHeight = nil; workspace.anchor = Date() }
                Button { navigate(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Следующий период")
                HidigDateButton(date: $workspace.anchor)
                if workspace.preparingCalendar { ProgressView().controlSize(.small).help("Подготовка повторений") }
                Spacer()
                Button { draftTask = ManagedTask(title: "", startDate: calendar.startOfDay(for: workspace.anchor), isAllDay: true) } label: { Image(systemName: "plus") }.help("Новая задача")
                calendarModeMenu
            }.buttonStyle(.borderless).padding(.horizontal, 16).padding(.vertical, 8)
            calendarBody.frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CalendarHorizontalScrollMonitor(isEnabled: !isMagnifying && movingTaskID == nil && (store.selectedSection == .tasks || store.selectedSection == .calendar) && workspace.mode != .agenda) { delta, ended, cancelled in
                    handleHorizontalScroll(delta: delta, ended: ended, cancelled: cancelled)
                })
        }
        .environment(\.calendarAutoscroll, { point in dragScroller.update(point) })
        .sheet(item: $draftTask) { draft in CalendarTaskCreation(draft: draft) { draftTask = nil } }
        .popover(isPresented: Binding(get: { expandedDay != nil }, set: { if !$0 { expandedDay = nil } })) {
            if let day = expandedDay {
                ScrollView { VStack(alignment: .leading, spacing: 6) {
                    Text(day.formatted(date: .complete, time: .omitted)).font(.headline)
                    ForEach(store.calendarTasks(on: day).filter(matches)) { CalendarCompactTask(task: $0) }
                    ForEach(store.plannerEvents(on: day, search: searchText).filter { $0.isAllDay }, id: \.identity) { Text($0.title) }
                }.padding(16) }.frame(width: 360, height: 360).background(HidigPalette.surface)
            }
        }
        .onAppear { store.prepareCalendarIndex() }
        .onChange(of: workspace.anchor) { _ in store.prepareCalendarIndex() }
        .onChange(of: workspace.mode) { _ in pan.interrupt(); pan.offset = 0; interactionAnchor = nil; lockedAllDayHeight = nil; store.prepareCalendarIndex(force: true) }
        .onExitCommand { workspace.cancellationToken += 1; pan.interrupt(); pan.offset = 0; interactionAnchor = nil; lockedAllDayHeight = nil; movingTaskID = nil; _ = dragScroller.update(nil) }
        .onChange(of: movingTaskID) { id in if id == nil { pan.offset = 0; _ = dragScroller.update(nil) } }
    }
    private func navigate(_ direction: Int) {
        pan.interrupt()
        let currentAnchor = interactionAnchor ?? workspace.anchor
        interactionAnchor = nil
        lockedAllDayHeight = pan.allDayHeight
        let count = workspace.mode == .week ? 7 : (workspace.mode == .fourDays ? 4 : 1)
        let slides = workspace.mode == .day || workspace.mode == .fourDays || workspace.mode == .week
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) {
            workspace.anchor = calendar.date(byAdding: workspace.mode == .month ? .month : .day, value: direction * count, to: currentAnchor) ?? workspace.anchor
            pan.offset = slides && !reduceMotion ? pan.offset + CGFloat(direction * count) * pan.dayWidth : 0
        }
        if slides { settleCalendar() } else { lockedAllDayHeight = nil }
    }

    private var calendarModeMenu: some View {
        HidigMenuPicker(
            options: TaskCalendarMode.allCases.map {
                HidigMenuOption(id: $0.rawValue, title: $0.title, systemImage: $0.systemImage)
            },
            selection: Binding(
                get: { store.taskCalendarMode.rawValue },
                set: { raw in
                    guard let mode = TaskCalendarMode(rawValue: raw) else { return }
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { store.taskCalendarMode = mode }
                }
            )
        )
        .frame(width: 118)
    }

    private func matches(_ task: ManagedTask) -> Bool { store.plannerMatches(task, search: searchText) }

    @ViewBuilder private var calendarBody: some View {
        switch store.taskCalendarMode {
        case .month: TaskMonthView(anchor: store.taskCalendarAnchor, searchText: searchText)
        case .agenda: TaskAgendaView(anchor: store.taskCalendarAnchor, searchText: searchText)
        case .day, .fourDays, .week:
            GeometryReader { geometry in
                let count = store.taskCalendarMode == .day ? 1 : (store.taskCalendarMode == .fourDays ? 4 : 7)
                let start = calendar.startOfDay(for: interactionAnchor ?? store.taskCalendarAnchor)
                let neighbors = 7
                let days = (-neighbors...(count + neighbors - 1)).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
                let gutterWidth: CGFloat = 52
                let width = max(76, (geometry.size.width - gutterWidth) / CGFloat(count))
                let visibleWidth = width * CGFloat(count)
                let renderWindow = CalendarRenderWindow.days(offset: pan.offset, dayWidth: width, visibleDays: count)
                let maximumAllDayCount = days.map { day in
                    store.calendarTasks(on: day).filter { ($0.isAllDay || $0.startDate == nil) && matches($0) }.count + store.plannerEvents(on: day, search: searchText).filter { $0.isAllDay }.count
                }.max() ?? 0
                let visibleAllDayRows = min(5, maximumAllDayCount)
                let measuredAllDayHeight = max(36, CGFloat(visibleAllDayRows) * 25 + (maximumAllDayCount > 5 ? 18 : 4))
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
                                        let allDayTasks = store.calendarTasks(on: day).filter { ($0.isAllDay || $0.startDate == nil) && matches($0) }
                                        VStack(spacing: 2) {
                                            ForEach(allDayTasks.prefix(5)) {
                                                CalendarCompactTask(task: $0)
                                            }
                                            if allDayTasks.count > 5 {
                                                Button("Ещё \(allDayTasks.count - 5)") { expandedDay = day }.buttonStyle(.plain)
                                                    .font(.system(size: 9, weight: .medium))
                                                    .foregroundStyle(HidigPalette.secondary)
                                                    .frame(maxWidth: .infinity, alignment: .leading)
                                                    .padding(.horizontal, 5)
                                            }
                                            ForEach(store.plannerEvents(on: day, search: searchText).filter { $0.isAllDay }.prefix(2), id: \.identity) { event in
                                                Text(event.title).font(.system(size: 10)).lineLimit(1)
                                                    .frame(maxWidth: .infinity, alignment: .leading).background(HidigPalette.lettuce.opacity(0.5))
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 3)
                                        .padding(.vertical, 2)
                                        .frame(width: width, height: allDayHeight, alignment: .top)
                                        .overlay(alignment: .trailing) { Divider().opacity(0.65) }
                                        .dropDestination(for: String.self) { values, _ in
                                            guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                                            store.scheduleManagedTask(id, at: day, allDay: true)
                                            return true
                                        }
                                        } else {
                                            Color.clear.frame(width: width, height: allDayHeight).allowsHitTesting(false)
                                        }
                                    }
                                }
                            }
                            .frame(height: allDayHeight)
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
                                                    DayTimelineColumn(day: day, width: width, searchText: searchText, hourHeight: CGFloat(hourHeight), movingTaskID: $movingTaskID, create: { draftTask = $0 })
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
                            }
                            .overlay(alignment: .topLeading) { Color.clear.frame(width: 0, height: 0) }
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        if magnificationStart == nil {
                                            magnificationStart = hourHeight
                                            isMagnifying = true
                                        }
                                        hourHeight = CalendarZoom.clamp((magnificationStart ?? hourHeight) * Double(value))
                                    }
                                    .onEnded { _ in
                                        magnificationStart = nil
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                                            isMagnifying = false
                                        }
                                    }
                            )
                            .transaction { transaction in
                                if isMagnifying { transaction.animation = nil }
                            }
                            .background(CalendarScrollBinding(scroller: dragScroller))
                            .onAppear { dragScroller.dayWidth = width; dragScroller.changeDay = { direction in if abs(pan.offset) < width * 6 { pan.offset -= CGFloat(direction) * width } } }
                        }
                }
                .frame(width: gutterWidth + width * CGFloat(count))
                .onAppear { pan.dayWidth = width; pan.allDayHeight = allDayHeight }
                .onChange(of: allDayHeight) { pan.allDayHeight = $0 }
                .onChange(of: geometry.size.width) { _ in
                    pan.interrupt(); pan.offset *= width / max(1, pan.dayWidth); pan.dayWidth = width; dragScroller.dayWidth = width
                }
                .onChange(of: store.taskCalendarMode) { _ in
                    pan.dayWidth = width
                    pan.offset = 0
                }
            }
        }
    }

    private func settleCalendar() {
        pan.settle(reduceMotion: reduceMotion) {
            // Resize only after horizontal movement finishes, keeping the time grid still.
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                lockedAllDayHeight = nil
            }
        }
    }
    private func commitInteraction() {
        if let anchor = interactionAnchor {
            interactionAnchor = nil
            workspace.anchor = anchor
        }
    }
    private func handleHorizontalScroll(delta: CGFloat, ended: Bool, cancelled: Bool) {
        guard !isMagnifying else { return }
        pan.interrupt()
        if cancelled { commitInteraction(); settleCalendar(); return }
        let width = max(1, pan.dayWidth)
        let slides = workspace.mode == .day || workspace.mode == .fourDays || workspace.mode == .week
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if delta != 0 {
                if slides && interactionAnchor == nil {
                    interactionAnchor = workspace.anchor
                    lockedAllDayHeight = pan.allDayHeight
                }
                let nextOffset = pan.offset + delta
                if slides {
                    let rebased = CalendarNavigation.rebasedSwipe(offset: nextOffset, dayWidth: width)
                    if rebased.dayShift != 0 {
                        interactionAnchor = calendar.date(byAdding: .day, value: rebased.dayShift,
                            to: interactionAnchor ?? workspace.anchor) ?? interactionAnchor
                        // Warm the next dates without publishing a new global anchor every day.
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
                    if slides { interactionAnchor = next } else { workspace.anchor = next }
                    pan.offset = settled.remainingOffset
                }
                commitInteraction()
            }
        }
        if ended { settleCalendar() }
    }

}

private struct CalendarHorizontalScrollMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onScroll: (CGFloat, Bool, Bool) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView(); context.coordinator.view = view; context.coordinator.attach(); return view
    }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.isEnabled = isEnabled; context.coordinator.onScroll = onScroll }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.detach() }
    final class Coordinator {
        weak var view: NSView?
        var isEnabled = false
        var onScroll: ((CGFloat, Bool, Bool) -> Void)?
        var axis = CalendarAxisLock()
        var startedInside = false
        var monitor: Any?
        var finish: DispatchWorkItem?
        func attach() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) == true ? nil : event
            }
        }
        func detach() { finish?.cancel(); if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { detach() }
        func handle(_ event: NSEvent) -> Bool {
            guard isEnabled, let view, event.window === view.window else { return false }
            let point = view.convert(event.locationInWindow, from: nil)
            if event.phase.contains(.began) || (event.phase.isEmpty && event.momentumPhase.isEmpty && finish == nil) {
                axis.reset()
                startedInside = view.bounds.contains(point)
                guard startedInside else { return false }
            }
            guard startedInside, view.bounds.contains(point) || axis.axis == .horizontal else { return false }
            if event.phase.contains(.cancelled) {
                finish?.cancel(); finish = nil
                if axis.axis == .horizontal { onScroll?(0, true, true) }; axis.reset(); return false
            }
            let accepted = axis.accept(dx: event.scrollingDeltaX, dy: event.scrollingDeltaY)
            guard accepted else { return false }
            finish?.cancel()
            if event.scrollingDeltaX != 0 { onScroll?(event.scrollingDeltaX, false, false) }
            let ended = event.momentumPhase.contains(.ended)
            let work = DispatchWorkItem { [weak self] in
                self?.onScroll?(0, true, false); self?.axis.reset(); self?.finish = nil
            }
            finish = work
            // A brief grace period lets macOS momentum begin after the touch phase ends.
            DispatchQueue.main.asyncAfter(deadline: .now() + (ended ? 0 : 0.12), execute: work)
            return true
        }
    }
}

private struct CalendarCompactTask: View {
    @EnvironmentObject private var store: AppStore
    let task: ManagedTask
    private var tint: Color {
        Color(hex: store.taskList(id: task.listID)?.colorHex ?? "#6A9CC2")
    }
    var body: some View {
        HStack(spacing: 4) {
            TaskCompletionButton(task: task)
            Button { store.selectedTaskID = task.id } label: {
                Text(task.title).hidigFont(size: 12, weight: .medium).lineLimit(1)
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
        .opacity(task.status == .completed ? 0.55 : 1)
        .contextMenu { TaskContextActions(task: task) }
    }
}

private struct DayTimelineColumn: View {
    @EnvironmentObject private var workspace: PlannerWorkspace
    @State private var placementCache = PlannerPlacementCache()
    @State private var selectionStart: CGFloat?
    @State private var selectionEnd: CGFloat?
    @EnvironmentObject private var store: AppStore
    let day: Date
    let width: CGFloat
    let searchText: String
    let hourHeight: CGFloat
    @Binding var movingTaskID: UUID?
    let create: (ManagedTask) -> Void
    private var dayEnd: Date { PlannerCalendar.current.date(byAdding: .day, value: 1, to: day)! }
    private var tasks: [ManagedTask] {
        store.calendarTasks(on: day).filter { !$0.isAllDay && $0.startDate != nil && store.plannerMatches($0, search: searchText) }
    }
    private var events: [GoogleCalendarEventSnapshot] {
        store.plannerEvents(on: day, search: searchText).filter { !$0.isAllDay }
    }
    private func minute(_ date: Date) -> Double {
        if date <= day { return 0 }
        if date >= dayEnd { return 1440 }
        return Double(PlannerCalendar.current.component(.hour, from: date) * 60 + PlannerCalendar.current.component(.minute, from: date))
    }
    private func interval(_ task: ManagedTask) -> PlannerInterval {
        let start = task.startDate ?? task.dueDate ?? day
        return PlannerInterval(id: task.id.uuidString, start: minute(start),
            end: min(1440, max(minute(start) + 1, minute(task.calendarEndDate ?? start.addingTimeInterval(Double(task.durationMinutes * 60))))))
    }
    var body: some View {
        let intervals = tasks.map(interval) + events.map {
            PlannerInterval(id: $0.identity, start: minute($0.startDate), end: max(minute($0.startDate) + 1, minute($0.endDate)))
        }
        let placements = placementCache.placements(intervals)
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
            ForEach(tasks) { task in
                let slot = interval(task)
                let placement = placements[task.id.uuidString] ?? PlannerPlacement(lane: 0, laneCount: 1)
                let laneWidth = (width - 4) / CGFloat(placement.laneCount)
                CalendarTaskBlock(task: task, width: laneWidth - 3, height: CGFloat(slot.end - slot.start) / 60 * hourHeight, hourHeight: hourHeight, dayWidth: width, movingTaskID: $movingTaskID)
                    .offset(x: 2 + CGFloat(placement.lane) * laneWidth, y: CGFloat(slot.start) / 60 * hourHeight)
                    .zIndex(movingTaskID == task.id ? 10 : 0)
            }
            ForEach(events, id: \.identity) { event in
                let placement = placements[event.identity] ?? PlannerPlacement(lane: 0, laneCount: 1)
                let laneWidth = (width - 4) / CGFloat(placement.laneCount)
                Text(event.title).font(.system(size: 11)).padding(4)
                    .frame(width: laneWidth - 3, height: max(1, CGFloat(minute(event.endDate) - minute(event.startDate)) / 60 * hourHeight), alignment: .topLeading)
                        .background(HidigPalette.lettuce.opacity(0.72)).clipShape(RoundedRectangle(cornerRadius: 7))
                    .offset(x: 2 + CGFloat(placement.lane) * laneWidth, y: CGFloat(minute(event.startDate)) / 60 * hourHeight)
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
    private func createDraft(y: CGFloat, endY: CGFloat?) {
        let start = TaskEngine.calendarDropDate(on: day, yOffset: y, hourHeight: hourHeight, firstHour: 0)
        let finish = endY.map { TaskEngine.calendarDropDate(on: day, yOffset: $0, hourHeight: hourHeight, firstHour: 0) }
        let duration = max(15, Int((finish?.timeIntervalSince(start) ?? 1800) / 60))
        create(ManagedTask(title: "", startDate: start, plannedEndDate: start.addingTimeInterval(Double(duration * 60)), durationMinutes: duration))
    }

}

private struct CalendarTaskBlock: View {
    @EnvironmentObject private var workspace: PlannerWorkspace
    @Environment(\.calendarAutoscroll) private var autoscroll
    @State private var scrollTranslation = CGSize.zero
    @State private var gestureToken: Int?

    @EnvironmentObject private var store: AppStore
    let task: ManagedTask
    let width: CGFloat
    let height: CGFloat
    let hourHeight: CGFloat
    let dayWidth: CGFloat
    @Binding var movingTaskID: UUID?
    @GestureState private var moveTranslation: CGSize = .zero
    @GestureState private var resizeTranslation: CGFloat = 0
    private var start: Date { task.startDate ?? task.dueDate ?? Date() }
    private var previewStart: Date {
        moveTranslation == .zero ? start : TaskEngine.calendarMoveDate(
            from: start, translation: CGSize(width: moveTranslation.width + scrollTranslation.width, height: moveTranslation.height + scrollTranslation.height), dayWidth: dayWidth, hourHeight: hourHeight)
    }
    private var previewDuration: Int {
        max(15, task.durationMinutes + Int((resizeTranslation / hourHeight * 60 / 15).rounded()) * 15)
    }
    private var tint: Color {
        Color(hex: store.taskList(id: task.listID)?.colorHex ?? "#6A9CC2")
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 3) {
                TaskCompletionButton(task: task)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title).hidigFont(size: 12, weight: .medium).lineLimit(width < 100 ? 1 : (height > 50 ? 2 : 1))
                    if height > 36 && width >= 100 {
                        let end = previewStart.addingTimeInterval(Double(previewDuration * 60))
                        Text("\(PlannerCalendar.time(previewStart))–\(PlannerCalendar.time(end))")
                            .font(.system(size: 10)).foregroundStyle(HidigPalette.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { store.selectedTaskID = task.id }
                .gesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                    .updating($moveTranslation) { value, state, _ in state = value.translation }
                    .onChanged { value in
                        if gestureToken == nil { gestureToken = workspace.cancellationToken }
                        guard gestureToken == workspace.cancellationToken else { return }
                        movingTaskID = task.id; scrollTranslation = autoscroll(value.location)
                    }
                    .onEnded { value in
                        defer { gestureToken = nil; movingTaskID = nil; scrollTranslation = .zero; _ = autoscroll(nil) }
                        guard gestureToken == workspace.cancellationToken else { return }
                        let translation = CGSize(width: value.translation.width + scrollTranslation.width, height: value.translation.height + scrollTranslation.height)
                        let date = TaskEngine.calendarMoveDate(from: start, translation: translation, dayWidth: dayWidth, hourHeight: hourHeight)
                        store.scheduleManagedTask(task.id, at: date, allDay: false)
                    })
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { store.selectedTaskID = task.id }
                if task.priority != .none && width > 65 { Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(task.priority.accent).accessibilityLabel("Приоритет: \(task.priority.title)") }
            }.padding(4)
            Rectangle().fill(tint.opacity(0.25)).frame(height: 10)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .updating($resizeTranslation) { value, state, _ in state = value.translation.height }
                    .onChanged { _ in if gestureToken == nil { gestureToken = workspace.cancellationToken } }
                    .onEnded { value in
                        defer { gestureToken = nil }
                        guard gestureToken == workspace.cancellationToken else { return }
                        let duration = max(15, task.durationMinutes + Int((value.translation.height / hourHeight * 60 / 15).rounded()) * 15)
                        store.scheduleManagedTask(task.id, at: start, durationMinutes: duration)
                    })
                .help("Изменить длительность с шагом 15 минут")
        }
        .frame(width: width, height: max(15 * hourHeight / 60, height + CGFloat(previewDuration - task.durationMinutes) / 60 * hourHeight))
        .background(tint.opacity(movingTaskID == task.id ? 0.35 : 0.20))
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .taskPriorityBorder(task.priority, radius: 4)
        .shadow(color: .black.opacity(movingTaskID == task.id ? 0.2 : 0), radius: 6, y: 3)
        .overlay(alignment: .topLeading) {
            if moveTranslation != .zero || resizeTranslation != 0 {
                let end = previewStart.addingTimeInterval(Double(previewDuration * 60))
                Text("\(PlannerCalendar.time(previewStart))–\(PlannerCalendar.time(end))")
                    .font(.system(size: 11, weight: .semibold)).fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 4)
                    .background(HidigPalette.surfaceRaised)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .offset(y: -27).allowsHitTesting(false)
            }
        }
        .offset(CGSize(width: moveTranslation.width, height: moveTranslation.height + scrollTranslation.height))
        .onChange(of: moveTranslation) { value in
            if value == .zero, movingTaskID == task.id { movingTaskID = nil; _ = autoscroll(nil) }
        }
        .opacity(task.status == .completed ? 0.5 : 1)
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
                    ForEach(store.calendarTasks(on: day).filter { store.plannerMatches($0, search: searchText) }.prefix(3)) { task in
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
                    if store.calendarTasks(on: day).filter({ store.plannerMatches($0, search: searchText) }).count > 3 {
                        Button("Ещё \(store.calendarTasks(on: day).filter { store.plannerMatches($0, search: searchText) }.count - 3)") {
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
                    let tasks = store.calendarTasks(on: day).filter { store.plannerMatches($0, search: searchText) }
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
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(EisenhowerQuadrant.allCases) { quadrant in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(quadrant.title).hidigFont(size: 14, weight: .bold)
                        ForEach(store.matrixTasks(in: quadrant).filter { store.plannerMatches($0, search: store.planner.search) }) { task in
                            TaskRow(task: task)
                                .onDrag { NSItemProvider(object: task.id.uuidString as NSString) }
                        }
                        Spacer(minLength: 40)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
                    .background(HidigPalette.surface)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(HidigPalette.line))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .dropDestination(for: String.self) { values, _ in
                        guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                        store.setTaskQuadrant(id, quadrant)
                        return true
                    }
                }
            }
            .padding(14)
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
    @State private var editEntireSeries = false
    @State private var showsScope = false
    @Binding private var showsDetails: Bool
    private let cardSize: CGSize
    init(task: ManagedTask, showsDetails: Binding<Bool>, cardSize: CGSize) {
        self._showsDetails = showsDetails
        self.cardSize = cardSize
        _draft = State(initialValue: task)
        _baseline = State(initialValue: task)
        _editsNotes = State(initialValue: task.description.isEmpty && !task.notes.isEmpty)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                TaskCompletionButton(task: store.resolvedTask(id: draft.id) ?? draft)
                Divider().frame(height: 16)
                Button { showsDate = true } label: {
                    Label(draft.scheduleLabel, systemImage: "calendar")
                        .hidigFont(size: 12).lineLimit(1)
                        .foregroundStyle(draft.isOverdue ? HidigPalette.warning : HidigPalette.forest)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).help(draft.scheduleLabel)
                    .popover(isPresented: $showsDate) {
                        TaskDateEditor(task: $draft, allowsRepeat: editEntireSeries || draft.seriesRootID == nil) { showsDate = false }
                    }
                TaskPriorityPicker(priority: $draft.priority)
                Button { save(); store.selectedTaskID = nil } label: {
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
                                Text(parent.title).lineLimit(1)
                                Image(systemName: "chevron.right").font(.system(size: 9))
                            }.hidigFont(size: 12).foregroundStyle(HidigPalette.secondary)
                        }.buttonStyle(.plain).help("Открыть родительскую задачу")
                    }
                    TextField("Название задачи", text: $draft.title, axis: .vertical)
                        .hidigFont(size: 19, weight: .semibold).lineLimit(1...5).textFieldStyle(.plain)
                        .accessibilityLabel("Название задачи")
                    TaskNotesEditor(text: editsNotes ? $draft.notes : $draft.description)
                        .frame(height: showsDetails ? 90 : 110)
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
            Divider()
            HStack(spacing: 8) {
                HidigMenuPicker(
                    options: store.taskLists.map { HidigMenuOption(id: $0.id.uuidString, title: $0.name, systemImage: "list.bullet") },
                    selection: Binding(get: { draft.listID.uuidString }, set: { if let id = UUID(uuidString: $0) { draft.listID = id } }),
                    leadingIcon: "list.bullet", compact: true
                ).frame(maxWidth: 180)
                Spacer(minLength: 4)
                Button { showsDetails.toggle() } label: {
                    Image(systemName: "list.bullet").foregroundStyle(showsDetails ? HidigPalette.controlFill : HidigPalette.secondary)
                        .frame(width: 28, height: 28)
                }.buttonStyle(.plain).help(showsDetails ? "Скрыть подробности" : "Подробности задачи")
                    .accessibilityLabel(showsDetails ? "Скрыть подробности" : "Подробности задачи")
                Menu {
                    Button("В корзину", systemImage: "trash", role: .destructive) { store.trashManagedTask(draft.id) }
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 28) }
                    .menuStyle(.borderlessButton).fixedSize().help("Действия с задачей")
                SaveStatusView()
            }.padding(.horizontal, 15).padding(.vertical, 9)
        }.frame(width: cardSize.width, height: cardSize.height)
            .hidigFont(size: 13)
            .background(HidigPalette.surface)
            .taskPriorityBorder(draft.priority, radius: 14)
            .onExitCommand { save(); store.selectedTaskID = nil }
            .onAppear { showsScope = draft.seriesRootID != nil || draft.repeatRule != nil }
            .confirmationDialog("Изменить повторение", isPresented: $showsScope, titleVisibility: .visible) {
                Button("Этот экземпляр") { editEntireSeries = false }
                Button("Всю серию") {
                    editEntireSeries = true
                    if let root = store.task(id: draft.seriesRootID ?? draft.id) {
                        draft.repeatRule = root.repeatRule; baseline.repeatRule = root.repeatRule
                    }
                }
            }

            .onChange(of: draft) { _ in
                pendingSave?.cancel()
                pendingSave = Task { @MainActor in
                    do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
                    save()
                }
            }
            .onDisappear { pendingSave?.cancel(); save() }
    }
    private func save() {
        guard draft != baseline else { return }
        if editEntireSeries { store.updateSeriesEdits(from: baseline, to: draft) }
        else { store.updateManagedTaskEdits(from: baseline, to: draft) }
        baseline = draft
    }
}

private struct TaskDateEditor: View {
    @Binding var task: ManagedTask
    let dismiss: () -> Void
    let allowsRepeat: Bool
    @State private var durationMode: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool
    @State private var zone: String
    @State private var repeatRule: TaskRepeatRule?
    init(task: Binding<ManagedTask>, allowsRepeat: Bool = true, dismiss: @escaping () -> Void) {
        _task = task
        self.dismiss = dismiss
        self.allowsRepeat = allowsRepeat
        let value = task.wrappedValue
        let date = value.startDate ?? value.dueDate ?? Date()
        _start = State(initialValue: date)
        _end = State(initialValue: value.calendarEndDate ?? date.addingTimeInterval(1800))
        _allDay = State(initialValue: value.isAllDay)
        _zone = State(initialValue: value.timeZoneID)
        _repeatRule = State(initialValue: value.repeatRule)
        _durationMode = State(initialValue: !value.isAllDay)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ChoicePill(title: "Дата", isSelected: !durationMode) {
                    withAnimation(.easeInOut(duration: 0.18)) { durationMode = false }
                }
                ChoicePill(title: "Длительность", isSelected: durationMode) {
                    withAnimation(.easeInOut(duration: 0.18)) { durationMode = true }
                }
            }
            .frame(maxWidth: .infinity)

            dateRow(durationMode ? "Начать" : "Дата", date: $start)
            if durationMode {
                dateRow("Закончить", date: $end)
            }
            HStack {
                Text("Весь день").hidigFont(size: 12, weight: .medium)
                Spacer()
                Toggle("", isOn: $allDay).labelsHidden().toggleStyle(TaskCheckboxStyle())
            }
            HidigMenuPicker(
                options: zones.map { HidigMenuOption(id: $0, title: $0, systemImage: "globe") },
                selection: $zone,
                leadingIcon: "globe"
            )
            TaskRepeatEditor(rule: $repeatRule, start: start).disabled(!allowsRepeat)
            if !allowsRepeat { Text("Правило повторения меняется для всей серии.").font(.caption).foregroundStyle(.secondary) }
            if durationMode && end <= start && !allDay {
                Text("Окончание должно быть позже начала.").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Снять плановую дату") { task.startDate = nil; task.plannedEndDate = nil; dismiss() }
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                Button("Готово") {
                    var calendar = PlannerCalendar.current
                    calendar.timeZone = TimeZone(identifier: zone) ?? .current
                    let first = allDay ? calendar.startOfDay(for: start) : start
                    task.startDate = first
                    task.plannedEndDate = durationMode && !allDay ? end : first.addingTimeInterval(1800)
                    task.durationMinutes = durationMode ? max(15, Int(end.timeIntervalSince(first) / 60)) : 30
                    task.isAllDay = allDay
                    task.timeZoneID = zone
                    task.repeatRule = repeatRule
                    dismiss()
                }.buttonStyle(PrimaryButtonStyle()).disabled(durationMode && end <= start && !allDay)
            }
        }.padding(18).frame(width: 390)
            .environment(\.timeZone, TimeZone(identifier: zone) ?? .current)
    }

    private var zones: [String] {
        Array(Set([zone, TimeZone.current.identifier, "Europe/Moscow", "Europe/London", "Europe/Berlin", "Asia/Dubai", "America/New_York"])).sorted()
    }

    private func dateRow(_ title: String, date: Binding<Date>) -> some View {
        HStack(spacing: 9) {
            Text(title)
                .hidigFont(size: 12, weight: .medium)
                .foregroundStyle(HidigPalette.secondary)
                .frame(width: 72, alignment: .leading)
            HidigDateButton(date: date, compact: true)
            if !allDay { HidigTimeButton(date: date, compact: true) }
        }
    }
}

private struct TaskRepeatEditor: View {
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
