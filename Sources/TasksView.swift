import SwiftUI
import UniformTypeIdentifiers

struct TasksView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @State private var quickTaskTitle = ""
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(HidigPalette.line)
            HStack(spacing: 0) {
                TaskNavigationColumn()
                    .frame(width: 190)
                Divider().overlay(HidigPalette.line)
                center
                Divider().overlay(HidigPalette.line)
                detail
                    .frame(width: 310)
            }
        }
        .background(HidigPalette.canvas)
        .frame(minWidth: 1000)
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                SectionEyebrow(text: "Планирование")
                Text("Задачи")
                    .hidigFont(size: 25, weight: .bold, design: .rounded)
            }
            Spacer()
            TextField("Поиск", text: $searchText)
                .textFieldStyle(HidigTextFieldStyle())
                .frame(width: 210)
            Picker("Представление", selection: $store.tasksPresentation) {
                ForEach(TasksPresentation.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 260)
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
        .padding(.bottom, 16)
        .foregroundStyle(HidigPalette.forest)
    }

    @ViewBuilder
    private var center: some View {
        switch store.tasksPresentation {
        case .list:
            TaskListColumn(searchText: searchText, quickTaskTitle: $quickTaskTitle)
        case .calendar:
            TaskCalendarView()
        case .matrix:
            EisenhowerMatrixView()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let task = store.selectedManagedTask {
            TaskDetailView(task: task).id("\(task.id.uuidString)-\(task.modifiedAt.timeIntervalSince1970)")
        } else {
            VStack(spacing: 12) {
                Image(systemName: "rectangle.and.pencil.and.ellipsis")
                    .hidigFont(size: 30)
                    .foregroundStyle(HidigPalette.secondary)
                Text("Выберите задачу")
                    .hidigFont(size: 15, weight: .semibold)
                Text("Карточка задачи откроется здесь.")
                    .hidigFont(size: 12)
                    .foregroundStyle(HidigPalette.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
                        Button { store.toggleTaskFolder(folder.id) } label: {
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
        return store.visibleManagedTasks.filter {
            $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.description.localizedCaseInsensitiveContains(searchText)
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
        Button { store.selectedTaskID = task.id } label: {
            HStack(spacing: 10) {
                Button {
                    if task.status == .trashed { store.restoreManagedTask(task.id) }
                    else { store.setManagedTaskCompleted(task.id, completed: task.status != .completed) }
                } label: {
                    Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                        .hidigFont(size: 17)
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .strikethrough(task.status == .completed)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let start = task.startDate {
                            Label(start.formatted(date: .abbreviated, time: task.isAllDay ? .omitted : .shortened), systemImage: "calendar")
                        } else {
                            Text("Без даты")
                        }
                        if let due = task.dueDate {
                            Text("Срок: \(due.formatted(date: .abbreviated, time: task.isAllDay ? .omitted : .shortened))")
                                .foregroundStyle(task.status == .active && (task.isAllDay ? due < Calendar.current.startOfDay(for: Date()) : due < Date()) ? HidigPalette.warning : HidigPalette.secondary)
                        }
                        if task.priority != .none { Text(task.priority.title) }
                        if task.completedPomodoros > 0 { Text("\(task.completedPomodoros) pomodoro") }
                    }
                    .hidigFont(size: 10)
                    .foregroundStyle(HidigPalette.secondary)
                }
                Spacer()
                Button { store.startPomodoro(for: task.id) } label: { Image(systemName: "timer") }
                    .buttonStyle(HidigIconButtonStyle())
                    .disabled(task.status != .active || store.activePomodoro != nil)
            }
            .padding(11)
            .background(HidigPalette.surface)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(HidigPalette.line))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDrag { NSItemProvider(object: task.id.uuidString as NSString) }
    }
}

private struct TaskCalendarView: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    private let calendar = Calendar.current

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Режим", selection: $store.taskCalendarMode) {
                    ForEach(TaskCalendarMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                Spacer()
                Button { movePeriod(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(HidigIconButtonStyle())
                Button("Сегодня") { store.taskCalendarAnchor = Date() }.buttonStyle(SecondaryButtonStyle())
                Button { movePeriod(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(HidigIconButtonStyle())
            }
            .padding(12)
            HStack(spacing: 0) {
                unscheduled.frame(width: 170)
                Divider().overlay(HidigPalette.line)
                calendarBody
            }
        }
    }

    private var unscheduled: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("НЕРАСПРЕДЕЛЁННЫЕ")
                .hidigFont(size: 10, weight: .bold)
                .foregroundStyle(HidigPalette.secondary)
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.unscheduledManagedTasks) { task in
                        Button {
                            store.selectedTaskID = task.id
                        } label: {
                            UnscheduledTaskCard(title: task.title)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Нераспределённая задача: \(task.title)")
                        .accessibilityIdentifier("unscheduled-task-\(task.id.uuidString)")
                        .draggable(task.id.uuidString)
                    }
                }
            }
        }
        .padding(10)
        .dropDestination(for: String.self) { values, _ in
            guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
            store.scheduleManagedTask(id, at: nil)
            return true
        }
    }

    @ViewBuilder
    private var calendarBody: some View {
        switch store.taskCalendarMode {
        case .day:
            timeline(days: [calendar.startOfDay(for: store.taskCalendarAnchor)])
        case .week:
            timeline(days: weekDays)
        case .month:
            TaskMonthView(anchor: store.taskCalendarAnchor)
        case .agenda:
            TaskAgendaView(anchor: store.taskCalendarAnchor)
        }
    }

    private var weekDays: [Date] {
        let interval = calendar.dateInterval(of: .weekOfYear, for: store.taskCalendarAnchor)
        let start = interval?.start ?? calendar.startOfDay(for: store.taskCalendarAnchor)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private func timeline(days: [Date]) -> some View {
        ScrollView([.vertical, .horizontal]) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 126)
                    ForEach(0..<24, id: \.self) { hour in
                        Text(String(format: "%02d:00", hour))
                            .hidigFont(size: 9)
                            .foregroundStyle(HidigPalette.secondary)
                            .frame(width: 42, height: 64, alignment: .top)
                    }
                }
                ForEach(days, id: \.self) { day in
                    DayTimelineColumn(day: day, width: days.count == 1 ? 420 : 118)
                }
            }
        }
    }

    private func movePeriod(_ direction: Int) {
        let component: Calendar.Component = store.taskCalendarMode == .month ? .month : (store.taskCalendarMode == .day ? .day : .weekOfYear)
        store.taskCalendarAnchor = calendar.date(byAdding: component, value: direction, to: store.taskCalendarAnchor) ?? store.taskCalendarAnchor
    }
}

private struct UnscheduledTaskCard: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    let title: String

    var body: some View {
        Text(title)
            .hidigFont(size: 11, weight: .medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(HidigPalette.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct DayTimelineColumn: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let day: Date
    let width: CGFloat
    private let calendar = Calendar.current
    private let hourHeight: CGFloat = 64

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(day.formatted(.dateTime.weekday(.abbreviated))).textCase(.uppercase)
                Text(day.formatted(.dateTime.day())).hidigFont(size: 17, weight: .bold)
            }
            .hidigFont(size: 9, weight: .semibold)
            .frame(width: width, height: 42)
            .background(calendar.isDateInToday(day) ? HidigPalette.lettuce : HidigPalette.surface)

            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(store.calendarTasks(on: day).filter { $0.isAllDay }) { task in
                        Button { store.selectedTaskID = task.id } label: {
                            Text(task.title).lineLimit(1).hidigFont(size: 10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(4).background(HidigPalette.lettuce)
                        }.buttonStyle(.plain).draggable(task.id.uuidString)
                    }
                    Text("Весь день").hidigFont(size: 9).foregroundStyle(HidigPalette.secondary)
                }.padding(4)
            }
            .frame(width: width, height: 84)
            .dropDestination(for: String.self) { values, _ in
                guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                store.scheduleManagedTask(id, at: day, allDay: true)
                return true
            }
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { _ in
                        Rectangle().fill(Color.clear)
                            .frame(width: width, height: hourHeight)
                            .overlay(alignment: .top) { Divider().overlay(HidigPalette.line) }
                    }
                }
                ForEach(tasks) { task in
                    CalendarTaskBlock(task: task, width: width - 8, hourHeight: hourHeight)
                        .offset(x: 4, y: yOffset(for: task))
                }
                ForEach(googleEvents, id: \.id) { event in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).hidigFont(size: 9, weight: .semibold).lineLimit(2)
                        Text("Google Calendar").hidigFont(size: 8)
                    }
                    .padding(5)
                    .foregroundStyle(HidigPalette.forest)
                    .frame(width: width - 12, height: max(20, CGFloat(event.endDate.timeIntervalSince(event.startDate) / 3600) * hourHeight), alignment: .topLeading)
                    .background(HidigPalette.lettuce.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .offset(x: 6, y: yOffset(for: event.startDate))
                }
            }
            .frame(width: width, height: hourHeight * 24)
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { values, location in
                guard let id = values.first.flatMap(UUID.init(uuidString:)) else { return false }
                let date = TaskEngine.calendarDropDate(
                    on: day,
                    yOffset: location.y,
                    hourHeight: hourHeight,
                    firstHour: 0,
                    calendar: calendar
                )
                store.scheduleManagedTask(id, at: date, allDay: false)
                return true
            }
        }
        .overlay(alignment: .trailing) { Rectangle().fill(HidigPalette.line).frame(width: 1) }
    }

    private var tasks: [ManagedTask] {
        store.calendarTasks(on: day).filter { !$0.isAllDay }
    }

    private var googleEvents: [GoogleCalendarEventSnapshot] {
        store.googleCalendarEvents.filter { Calendar.current.isDate($0.startDate, inSameDayAs: day) && !$0.isAllDay }
    }

    private func yOffset(for task: ManagedTask) -> CGFloat {
        guard let date = task.startDate else { return 0 }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return CGFloat(max(0, minute)) / 60 * hourHeight
    }


    private func yOffset(for date: Date) -> CGFloat {
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        return CGFloat(max(0, minute)) / 60 * hourHeight
    }
}

private struct CalendarTaskBlock: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    let task: ManagedTask
    let width: CGFloat
    let hourHeight: CGFloat
    @State private var resizeDelta: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title).hidigFont(size: 10, weight: .semibold).lineLimit(2)
            if let date = task.startDate { Text(date.formatted(date: .omitted, time: .shortened)).hidigFont(size: 9) }
            Spacer(minLength: 0)
            Capsule().fill(Color.white.opacity(0.7)).frame(width: 24, height: 3).frame(maxWidth: .infinity)
                .gesture(DragGesture(minimumDistance: 2)
                    .onChanged { resizeDelta = $0.translation.height }
                    .onEnded { value in
                        let deltaMinutes = Int(value.translation.height / hourHeight * 60).roundedToNearest(15)
                        store.scheduleManagedTask(task.id, at: task.startDate, durationMinutes: task.durationMinutes + deltaMinutes)
                        resizeDelta = 0
                    })
        }
        .padding(6)
        .foregroundStyle(Color.white)
        .frame(width: width, height: max(20, CGFloat(task.durationMinutes) / 60 * hourHeight + resizeDelta))
        .background(task.status == .completed ? HidigPalette.secondary : HidigPalette.controlFill)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .onTapGesture { store.selectedTaskID = task.id }
        .draggable(task.id.uuidString)
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
                        }.buttonStyle(.plain).draggable(task.id.uuidString)
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
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @State var draft: ManagedTask
    @State private var hasStartDate: Bool
    @State private var hasDueDate: Bool

    init(task: ManagedTask) {
        _draft = State(initialValue: task)
        _hasStartDate = State(initialValue: task.startDate != nil)
        _hasDueDate = State(initialValue: task.dueDate != nil)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Название", text: $draft.title, axis: .vertical)
                    .hidigFont(size: 19, weight: .bold)
                    .textFieldStyle(.plain)
                TextField("Описание", text: $draft.description, axis: .vertical)
                    .textFieldStyle(HidigTextFieldStyle())
                    .lineLimit(3...8)
                field("Список") {
                    Picker("", selection: $draft.listID) {
                        ForEach(store.taskLists) { Text($0.name).tag($0.id) }
                    }.labelsHidden()
                }
                Toggle("Дата начала", isOn: $hasStartDate)
                if hasStartDate {
                    DatePicker("", selection: Binding(get: { draft.startDate ?? Date() }, set: { draft.startDate = $0 }), displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                        .labelsHidden()
                }
                Toggle("Весь день", isOn: $draft.isAllDay)
                Toggle("Срок выполнения", isOn: $hasDueDate)
                if hasDueDate {
                    DatePicker("", selection: Binding(get: { draft.dueDate ?? Date() }, set: { draft.dueDate = $0 }), displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                field("Продолжительность") {
                    Stepper("\(draft.durationMinutes) мин", value: $draft.durationMinutes, in: 15...720, step: 15)
                }
                field("Приоритет") {
                    Picker("", selection: $draft.priority) {
                        ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                    }.labelsHidden()
                }
                Toggle("Важная", isOn: $draft.isImportant)
                field("Метки") {
                    TextField("через запятую", text: Binding(
                        get: { draft.tags.joined(separator: ", ") },
                        set: { draft.tags = $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    )).textFieldStyle(HidigTextFieldStyle())
                }
                field("Pomodoro") {
                    Stepper("План: \(draft.plannedPomodoros)", value: $draft.plannedPomodoros, in: 0...99)
                    Text("Завершено: \(draft.completedPomodoros)").foregroundStyle(HidigPalette.secondary)
                }
                if store.state.googleCalendarConnection.isConnected {
                    field("Google Calendar") {
                        if draft.googleEventID != nil {
                            Text("Связано с событием").foregroundStyle(HidigPalette.secondary)
                            Button("Удалить связь") { store.unlinkTaskFromGoogle(draft.id) }
                                .buttonStyle(SecondaryButtonStyle())
                        } else if let calendarID = store.state.googleCalendarConnection.selectedCalendarIDs.first,
                                  draft.startDate != nil {
                            Button("Создать связанное событие") {
                                save()
                                Task { await store.linkTaskToGoogle(draft.id, calendarID: calendarID) }
                            }
                            .buttonStyle(SecondaryButtonStyle())
                        } else {
                            Text("Укажите дату и выберите календарь в разделе «Интеграции».")
                                .hidigFont(size: 10)
                                .foregroundStyle(HidigPalette.secondary)
                        }
                    }
                }
                if let active = store.activePomodoro, active.taskID == draft.id {
                    PomodoroControls(active: active)
                } else {
                    Button("Запустить Pomodoro") { save(); store.startPomodoro(for: draft.id) }
                        .buttonStyle(PrimaryButtonStyle())
                }
                TextField("Заметки и ссылки", text: $draft.notes, axis: .vertical)
                    .textFieldStyle(HidigTextFieldStyle())
                    .lineLimit(4...10)
                if !draft.changeHistory.isEmpty {
                    field("История") {
                        ForEach(draft.changeHistory.prefix(8)) { item in
                            Text("\(item.date.formatted(date: .abbreviated, time: .shortened)) — \(item.summary)")
                                .hidigFont(size: 10)
                        }
                    }
                }
                HStack {
                    Button("Сохранить", action: save).buttonStyle(PrimaryButtonStyle())
                    Spacer()
                    Button("В корзину") { store.trashManagedTask(draft.id) }.buttonStyle(DestructiveButtonStyle())
                }
            }
            .padding(16)
        }
        .foregroundStyle(HidigPalette.forest)
        .background(HidigPalette.surface.opacity(0.55))
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).hidigFont(size: 9, weight: .bold).foregroundStyle(HidigPalette.secondary)
            content()
        }
    }

    private func save() {
        draft.startDate = hasStartDate ? (draft.startDate ?? Date()) : nil
        draft.dueDate = hasDueDate ? (draft.dueDate ?? Date()) : nil
        store.updateManagedTask(draft)
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
