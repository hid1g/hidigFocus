import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TasksView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @State private var quickTaskTitle = ""
    @State private var searchText = ""
    @AppStorage("taskListsVisible") private var taskListsVisible = false
    @AppStorage("taskListsWidth") private var taskListsWidth = 210.0

    var body: some View {
        VStack(spacing: 0) {
            header
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
            TextField("Поиск", text: $searchText)
                .textFieldStyle(HidigTextFieldStyle())
                .frame(minWidth: 90, maxWidth: 150)
            SyncButton(showTitle: false)
            TasksPresentationControl(selection: $store.tasksPresentation)
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
        .transition(.opacity.combined(with: .move(edge: .bottom)))
        .animation(.easeInOut(duration: 0.22), value: store.tasksPresentation)
    }

}

private struct TasksPresentationControl: View {
    @Binding var selection: TasksPresentation

    var body: some View {
        HStack(spacing: 3) {
            ForEach(TasksPresentation.allCases) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selection = option }
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                        .hidigFont(size: 10, weight: selection == option ? .semibold : .medium)
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                        .padding(.horizontal, 7)
                        .frame(height: 32)
                        .background(selection == option ? HidigPalette.surfaceRaised : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                    ("Сегодня", "sun.max", .today),
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
    }

    private func count(for selection: TaskSidebarSelection) -> Int {
        switch selection {
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

    private var tasks: [ManagedTask] {
        guard !searchText.isEmpty else { return store.visibleManagedTasks }
        return store.state.managedTasks.filter {
            $0.status != .trashed &&
            (
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.description.localizedCaseInsensitiveContains(searchText)
                || $0.notes.localizedCaseInsensitiveContains(searchText)
            )
        }
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

            if tasks.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .hidigFont(size: 30)
                        .foregroundStyle(HidigPalette.secondary)
                    Text("Задач нет").hidigFont(size: 15, weight: .semibold)
                    Text("Создайте задачу или выберите другой раздел.")
                        .hidigFont(size: 12)
                        .foregroundStyle(HidigPalette.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(["Просрочено", "Сегодня", "Предстоящие", "Без срока"], id: \.self) { section in
                            let rows = tasks.filter { group(for: $0) == section }
                            if !rows.isEmpty {
                                HStack {
                                    Text(section).hidigFont(size: 12, weight: .semibold)
                                    Text("\(rows.count)").hidigFont(size: 10)
                                    Spacer()
                                }.foregroundStyle(section == "Просрочено" ? HidigPalette.warning : HidigPalette.secondary)
                                    .padding(.top, 10)
                                ForEach(rows) { task in TaskRow(task: task) }
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func group(for task: ManagedTask) -> String {
        guard let date = task.dueDate ?? task.startDate else { return "Без срока" }
        let today = Calendar.current.startOfDay(for: Date())
        if task.status == .active && task.dueDate != nil && (task.isAllDay ? date < today : date < Date()) { return "Просрочено" }
        return Calendar.current.isDateInToday(date) ? "Сегодня" : "Предстоящие"
    }

    private func addTask() {
        guard store.addManagedTask(named: quickTaskTitle) != nil else { return }
        quickTaskTitle = ""
    }
}

private struct TaskRow: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let task: ManagedTask

    var body: some View {
        HStack(spacing: 10) {
            TaskCompletionButton(task: task)
            Button { store.selectedTaskID = task.id } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title).strikethrough(task.status == .completed)
                        .hidigFont(size: 14, weight: .medium).lineLimit(2)
                    HStack(spacing: 10) {
                        Label(task.scheduleLabel, systemImage: "calendar")
                            .foregroundStyle(task.isOverdue ? HidigPalette.warning : HidigPalette.secondary)
                        Text(store.taskLists.first { $0.id == task.listID }?.name ?? "Входящие")
                            .foregroundStyle(HidigPalette.secondary)
                        if task.repeatRule != nil { Image(systemName: "repeat") }
                    }.hidigFont(size: 11)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(CalendarTaskPressStyle(tint: HidigPalette.controlFill))
            .taskCard(task)
            if task.priority != .none {
                Image(systemName: "flag.fill").foregroundStyle(task.priority == .high ? Color.red : HidigPalette.controlFill)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(HidigPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .draggable(task.id.uuidString)
        .contextMenu { TaskContextActions(task: task) }
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
            Image(systemName: task.status == .completed ? "checkmark.square.fill" : "square")
                .font(.system(size: 14))
                .foregroundStyle(task.status == .completed ? HidigPalette.controlFill : HidigPalette.secondary)
        }
        .buttonStyle(.plain)
        .help(task.status == .completed ? "Вернуть в активные" : "Выполнить задачу")
        .accessibilityLabel(task.status == .completed ? "Вернуть в активные" : "Выполнить задачу")
    }
}

private struct TaskCardModifier: ViewModifier {
    @EnvironmentObject private var store: AppStore
    let task: ManagedTask
    func body(content: Content) -> some View {
        content.popover(isPresented: Binding(
            get: { store.selectedTaskID == task.id },
            set: { if !$0 && store.selectedTaskID == task.id { store.selectedTaskID = nil } }
        ), arrowEdge: .trailing) {
            TaskDetailView(task: store.state.managedTasks.first { $0.id == task.id } ?? task)
                .environmentObject(store)
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
                if let date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) { move(to: date) }
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
        guard var current = store.state.managedTasks.first(where: { $0.id == task.id }) else { return }
        change(&current)
        store.updateManagedTask(current)
    }

    private func move(to day: Date) {
        let calendar = Calendar.current
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

private struct TaskCalendarView: View {
    @EnvironmentObject private var store: AppStore
    let searchText: String
    @AppStorage("calendarHourHeight") private var hourHeight = 72.0
    @State private var magnificationStart: Double?
    @State private var isMagnifying = false
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Spacer()
                Button {
                    if let id = store.addManagedTask(named: "Новая задача") {
                        store.scheduleManagedTask(id, at: Calendar.current.startOfDay(for: store.taskCalendarAnchor), allDay: true)
                    }
                } label: { Image(systemName: "plus") }
                    .buttonStyle(HidigIconButtonStyle()).help("Новая задача")
                calendarModeMenu
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            calendarBody
        }
        .animation(.easeInOut(duration: 0.18), value: store.taskCalendarMode)
        .background(CalendarHorizontalScrollMonitor(isEnabled: !isMagnifying) { stepCalendar($0) })
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
                    withAnimation(.easeInOut(duration: 0.22)) { store.taskCalendarMode = mode }
                }
            )
        )
        .frame(width: 118)
    }

    private func matches(_ task: ManagedTask) -> Bool {
        guard searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText) else { return false }
        if case .list(let id) = store.taskSidebarSelection { return task.listID == id }
        return true
    }

    @ViewBuilder private var calendarBody: some View {
        switch store.taskCalendarMode {
        case .month: TaskMonthView(anchor: store.taskCalendarAnchor)
        case .agenda: TaskAgendaView(anchor: store.taskCalendarAnchor)
        case .day, .fourDays, .week:
            GeometryReader { geometry in
                let count = store.taskCalendarMode == .day ? 1 : (store.taskCalendarMode == .fourDays ? 4 : 7)
                let start = store.taskCalendarMode == .week
                    ? (calendar.dateInterval(of: .weekOfYear, for: store.taskCalendarAnchor)?.start ?? store.taskCalendarAnchor)
                    : calendar.startOfDay(for: store.taskCalendarAnchor)
                let days = (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
                let gutterWidth: CGFloat = 52
                let width = max(76, (geometry.size.width - gutterWidth) / CGFloat(count))
                let maximumAllDayCount = days.map { day in
                    store.calendarTasks(on: day).filter { $0.isAllDay && matches($0) }.count
                }.max() ?? 0
                let visibleAllDayRows = min(5, maximumAllDayCount)
                let allDayHeight = max(36, CGFloat(visibleAllDayRows) * 25 + (maximumAllDayCount > 5 ? 18 : 4))
                VStack(spacing: 0) {
                        HStack(spacing: 0) {
                            Color.clear.frame(width: gutterWidth, height: 38)
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
                        Divider()
                        HStack(spacing: 0) {
                            Text("Весь день")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(HidigPalette.secondary)
                                .frame(width: gutterWidth - 7, alignment: .trailing)
                                .padding(.trailing, 7)
                            ForEach(days, id: \.self) { day in
                                let allDayTasks = store.calendarTasks(on: day).filter { $0.isAllDay && matches($0) }
                                VStack(spacing: 2) {
                                    ForEach(allDayTasks.prefix(5)) {
                                        CalendarCompactTask(task: $0)
                                    }
                                    if allDayTasks.count > 5 {
                                        Text("Ещё \(allDayTasks.count - 5)")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(HidigPalette.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(.horizontal, 5)
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
                            }
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
                                    ForEach(days, id: \.self) { day in
                                        DayTimelineColumn(day: day, width: width, searchText: searchText, hourHeight: CGFloat(hourHeight))
                                    }
                                }
                            }
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
                            .onAppear { reader.scrollTo(6, anchor: .top) }
                        }
                }
                .frame(width: gutterWidth + width * CGFloat(count))
            }
        }
    }

    private func stepCalendar(_ direction: Int) {
        guard !isMagnifying else { return }
        store.taskCalendarAnchor = CalendarNavigation.swipedAnchor(
            from: store.taskCalendarAnchor,
            mode: store.taskCalendarMode,
            direction: direction,
            calendar: calendar
        )
    }
}

private struct CalendarHorizontalScrollMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let onStep: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(isEnabled: isEnabled, onStep: onStep) }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onStep = onStep
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator {
        var isEnabled: Bool
        var onStep: (Int) -> Void
        weak var view: NSView?
        private var monitor: Any?
        private var accumulatedX: CGFloat = 0
        private var handledGesture = false

        init(isEnabled: Bool, onStep: @escaping (Int) -> Void) {
            self.isEnabled = isEnabled
            self.onStep = onStep
        }

        func attach(to view: NSView) {
            self.view = view
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event)
                return event
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        deinit { detach() }

        private func handle(_ event: NSEvent) {
            guard isEnabled, let view, event.window === view.window else {
                accumulatedX = 0
                return
            }
            if event.phase.contains(.began) {
                accumulatedX = 0
                handledGesture = false
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                if !handledGesture && abs(accumulatedX) >= 28 { step(accumulatedX) }
                accumulatedX = 0
                handledGesture = false
                return
            }
            guard event.momentumPhase.isEmpty, !handledGesture else { return }
            let horizontal = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : event.deltaX
            let vertical = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : event.deltaY
            guard abs(horizontal) > 0.5,
                  abs(horizontal) > abs(vertical) * 1.25 else { return }
            accumulatedX += horizontal
            guard abs(accumulatedX) >= 55 else { return }
            step(accumulatedX)
            handledGesture = !event.phase.isEmpty
            accumulatedX = 0
        }

        private func step(_ delta: CGFloat) {
            let direction = delta < 0 ? 1 : -1
            DispatchQueue.main.async { [onStep] in onStep(direction) }
        }
    }
}

private struct CalendarCompactTask: View {
    @EnvironmentObject private var store: AppStore
    let task: ManagedTask
    private var tint: Color {
        Color(hex: store.taskLists.first { $0.id == task.listID }?.colorHex ?? "#6A9CC2")
    }
    var body: some View {
        HStack(spacing: 4) {
            TaskCompletionButton(task: task)
            Button { store.selectedTaskID = task.id } label: {
                Text(task.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(CalendarTaskPressStyle(tint: tint))
            .taskCard(task)
            .draggable(task.id.uuidString)
        }
        .padding(.horizontal, 5)
        .frame(minHeight: 23)
        .background(tint.opacity(task.status == .completed ? 0.07 : 0.18))
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .opacity(task.status == .completed ? 0.55 : 1)
        .contextMenu { TaskContextActions(task: task) }
    }
}

private struct DayTimelineColumn: View {
    @EnvironmentObject private var store: AppStore
    let day: Date
    let width: CGFloat
    let searchText: String
    let hourHeight: CGFloat
    private var dayEnd: Date { Calendar.current.date(byAdding: .day, value: 1, to: day)! }
    private var tasks: [ManagedTask] {
        store.calendarTasks(on: day).filter {
            guard !$0.isAllDay && (searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)) else { return false }
            if case .list(let id) = store.taskSidebarSelection { return $0.listID == id }
            return true
        }
    }
    private var events: [GoogleCalendarEventSnapshot] {
        store.googleCalendarEvents.filter { !$0.isAllDay && $0.startDate < dayEnd && $0.endDate > day }
    }
    private func minute(_ date: Date) -> Double {
        if date <= day { return 0 }
        if date >= dayEnd { return 1440 }
        return Double(Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date))
    }
    private func interval(_ task: ManagedTask) -> PlannerInterval {
        let start = task.startDate ?? task.dueDate ?? day
        return PlannerInterval(id: task.id.uuidString, start: minute(start),
            end: min(1440, max(minute(start) + 1, minute(task.calendarEndDate ?? start.addingTimeInterval(Double(task.durationMinutes * 60))))))
    }
    var body: some View {
        let intervals = tasks.map(interval) + events.map {
            PlannerInterval(id: $0.id, start: minute($0.startDate), end: max(minute($0.startDate) + 1, minute($0.endDate)))
        }
        let placements = PlannerLayout.placements(intervals)
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
            .allowsHitTesting(false)
            ForEach(tasks) { task in
                let slot = interval(task)
                let placement = placements[task.id.uuidString] ?? PlannerPlacement(lane: 0, laneCount: 1)
                let laneWidth = (width - 4) / CGFloat(placement.laneCount)
                CalendarTaskBlock(task: task, width: laneWidth - 3, height: CGFloat(slot.end - slot.start) / 60 * hourHeight, hourHeight: hourHeight)
                    .offset(x: 2 + CGFloat(placement.lane) * laneWidth, y: CGFloat(slot.start) / 60 * hourHeight)
            }
            ForEach(events, id: \.id) { event in
                let placement = placements[event.id] ?? PlannerPlacement(lane: 0, laneCount: 1)
                let laneWidth = (width - 4) / CGFloat(placement.laneCount)
                Text(event.title).font(.system(size: 11)).padding(4)
                    .frame(width: laneWidth - 3, height: max(1, CGFloat(minute(event.endDate) - minute(event.startDate)) / 60 * hourHeight), alignment: .topLeading)
                        .background(HidigPalette.lettuce.opacity(0.72)).clipShape(RoundedRectangle(cornerRadius: 7))
                    .offset(x: 2 + CGFloat(placement.lane) * laneWidth, y: CGFloat(minute(event.startDate)) / 60 * hourHeight)
            }
            if Calendar.current.isDateInToday(day) {
                Rectangle().fill(Color.red).frame(height: 1)
                    .offset(y: CGFloat(minute(Date())) / 60 * hourHeight).allowsHitTesting(false)
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
}

private struct CalendarTaskBlock: View {
    @EnvironmentObject private var store: AppStore
    let task: ManagedTask
    let width: CGFloat
    let height: CGFloat
    let hourHeight: CGFloat
    @State private var resizeDelta: CGFloat = 0
    private var tint: Color {
        Color(hex: store.taskLists.first { $0.id == task.listID }?.colorHex ?? "#6A9CC2")
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 3) {
                TaskCompletionButton(task: task)
                Button { store.selectedTaskID = task.id } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title).font(.system(size: 12, weight: .medium)).lineLimit(height > 50 ? 2 : 1)
                        if height > 36, let start = task.startDate, let end = task.calendarEndDate {
                            Text("\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
                                .font(.system(size: 10)).foregroundStyle(HidigPalette.secondary)
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).contentShape(Rectangle())
                }
                .buttonStyle(CalendarTaskPressStyle(tint: tint))
                .taskCard(task)
                .draggable(task.id.uuidString)
            }.padding(4)
            Rectangle().fill(Color.clear).frame(height: 4)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2).onChanged { resizeDelta = $0.translation.height }
                    .onEnded {
                        store.scheduleManagedTask(task.id, at: task.startDate, durationMinutes: task.durationMinutes + Int($0.translation.height / hourHeight * 60).roundedToNearest(15))
                        resizeDelta = 0
                    })
        }.frame(width: width, height: max(1, height + resizeDelta))
            .background(tint.opacity(0.20))
            .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 2) }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .opacity(task.status == .completed ? 0.5 : 1)
            .animation(.easeOut(duration: 0.14), value: resizeDelta)
            .contextMenu { TaskContextActions(task: task) }
    }
}
private struct TaskMonthView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let anchor: Date
    var body: some View {
        let interval = Calendar.current.dateInterval(of: .month, for: anchor)
        let days = interval.map { Date.dates(from: $0.start, to: $0.end) } ?? []
        let leading = interval.map { (Calendar.current.component(.weekday, from: $0.start) - Calendar.current.firstWeekday + 7) % 7 } ?? 0
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
            ForEach(0..<7, id: \.self) { index in
                Text(Calendar.current.shortWeekdaySymbols[(Calendar.current.firstWeekday - 1 + index) % 7])
                    .hidigFont(size: 10, weight: .semibold)
            }
            ForEach(0..<leading, id: \.self) { _ in Color.clear.frame(height: 90) }
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.formatted(.dateTime.day())).hidigFont(size: 11, weight: .bold)
                    ForEach(store.calendarTasks(on: day).prefix(3)) { task in
                        Button { store.selectedTaskID = task.id } label: {
                            Text(task.title).hidigFont(size: 9).lineLimit(1)
                        }
                        .buttonStyle(CalendarTaskPressStyle(tint: HidigPalette.controlFill))
                        .taskCard(task)
                        .draggable(task.id.uuidString)
                        .contextMenu { TaskContextActions(task: task) }
                    }
                    if store.calendarTasks(on: day).count > 3 {
                        Button("Ещё \(store.calendarTasks(on: day).count - 3)") {
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
        .padding(12)
    }
}

private struct TaskAgendaView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let anchor: Date
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(store.scheduledManagedTasks) { TaskRow(task: $0) }
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
                        ForEach(store.matrixTasks(in: quadrant)) { task in
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
    init(task: ManagedTask) {
        _draft = State(initialValue: task)
        _baseline = State(initialValue: task)
        _editsNotes = State(initialValue: task.description.isEmpty && !task.notes.isEmpty)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TaskCompletionButton(task: store.state.managedTasks.first { $0.id == draft.id } ?? draft)
                Button { showsDate = true } label: {
                    Label(draft.scheduleLabel, systemImage: "calendar").lineLimit(2)
                }.buttonStyle(.borderless)
                    .popover(isPresented: $showsDate) {
                        TaskDateEditor(task: $draft) { showsDate = false }
                    }
                Spacer(minLength: 0)
                HidigMenuPicker(
                    options: TaskPriority.allCases.map {
                        HidigMenuOption(id: String($0.rawValue), title: $0.title, systemImage: "flag")
                    },
                    selection: Binding(
                        get: { String(draft.priority.rawValue) },
                        set: { if let raw = Int($0), let value = TaskPriority(rawValue: raw) { draft.priority = value } }
                    ),
                    leadingIcon: "flag"
                )
                .frame(width: 142)
                Button { store.selectedTaskID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }
            Divider()
            TextField("Название задачи", text: $draft.title, axis: .vertical)
                .font(.system(size: 20, weight: .semibold)).textFieldStyle(.plain)
                .accessibilityLabel("Название задачи")
            ZStack(alignment: .topLeading) {
                if (editsNotes ? draft.notes : draft.description).isEmpty {
                    Text("Описание").foregroundStyle(.secondary).padding(.leading, 5).padding(.top, 8).allowsHitTesting(false)
                }
                TextEditor(text: editsNotes ? $draft.notes : $draft.description).scrollContentBackground(.hidden)
                    .font(.system(size: 13)).accessibilityLabel("Описание задачи")
            }.frame(minHeight: 130, maxHeight: 220)
            if !draft.checklist.isEmpty {
                ForEach($draft.checklist) { $item in
                    Toggle(item.title, isOn: $item.isCompleted).toggleStyle(.checkbox)
                }
            }
            DisclosureGroup("Заметки и метки") {
                TextField("Дополнительные заметки", text: editsNotes ? $draft.description : $draft.notes, axis: .vertical).textFieldStyle(.roundedBorder)
                TextField("Метки через запятую", text: Binding(get: { draft.tags.joined(separator: ", ") },
                    set: { draft.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }))
                    .textFieldStyle(.roundedBorder)
            }.font(.system(size: 11))
            Divider()
            HStack {
                HidigMenuPicker(
                    options: store.taskLists.map { HidigMenuOption(id: $0.id.uuidString, title: $0.name, systemImage: "list.bullet") },
                    selection: Binding(
                        get: { draft.listID.uuidString },
                        set: { if let id = UUID(uuidString: $0) { draft.listID = id } }
                    ),
                    leadingIcon: "list.bullet"
                )
                .frame(maxWidth: 230)
                Spacer()
                Button { store.trashManagedTask(draft.id) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("В корзину")
            }
            if draft.sourceName == "TickTick" {
                Text("Изменения карточки сохраняются в hidigFocus.")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.padding(20).frame(width: 420)
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
        store.updateManagedTaskEdits(from: baseline, to: draft)
        baseline = draft
    }
}

private struct TaskDateEditor: View {
    @Binding var task: ManagedTask
    let dismiss: () -> Void
    @State private var durationMode: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var allDay: Bool
    @State private var zone: String
    init(task: Binding<ManagedTask>, dismiss: @escaping () -> Void) {
        _task = task
        self.dismiss = dismiss
        let value = task.wrappedValue
        let date = value.startDate ?? value.dueDate ?? Date()
        _start = State(initialValue: date)
        _end = State(initialValue: value.calendarEndDate ?? date.addingTimeInterval(1800))
        _allDay = State(initialValue: value.isAllDay)
        _zone = State(initialValue: value.timeZoneID)
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
                Toggle("", isOn: $allDay).labelsHidden().toggleStyle(.switch)
            }
            HidigMenuPicker(
                options: zones.map { HidigMenuOption(id: $0, title: $0, systemImage: "globe") },
                selection: $zone,
                leadingIcon: "globe"
            )
            if let rule = task.repeatRule {
                Label(rule.displayTitle, systemImage: "repeat")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }
            if durationMode && end <= start && !allDay {
                Text("Окончание должно быть позже начала.").font(.caption).foregroundStyle(.red)
            }
            HStack {
                Button("Очистить") { task.startDate = nil; task.dueDate = nil; dismiss() }
                    .buttonStyle(GhostButtonStyle())
                Spacer()
                Button("Готово") {
                    var calendar = Calendar.current
                    calendar.timeZone = TimeZone(identifier: zone) ?? .current
                    let first = allDay ? calendar.startOfDay(for: start) : start
                    task.startDate = first
                    task.dueDate = durationMode ? max(first, end) : first
                    task.durationMinutes = durationMode ? max(15, Int(end.timeIntervalSince(first) / 60)) : 30
                    task.isAllDay = allDay
                    task.timeZoneID = zone
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
            HidigDateButton(date: date)
            if !allDay { HidigTimeButton(date: date) }
        }
    }
}

private struct PomodoroControls: View {
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
            cursor = Calendar.current.date(byAdding: .day, value: 1, to: cursor) ?? end
        }
        return values
    }
}
