import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: PlannerWorkspace
    @Environment(\.openWindow) private var openWindow
    @State private var tab = 0
    @State private var selectedDate = Date()
    @State private var quickTitle = ""
    @State private var collapsed: Set<UUID> = []

    var body: some View {
        let _ = workspace.calendarRevision
        return VStack(spacing: 0) {
            Group {
                switch tab {
                case 0: taskPage
                case 1:
                    VStack(spacing: 0) {
                        MenuMonthCalendar(selection: $selectedDate)
                        Divider().padding(.vertical, 8)
                        dailyList
                    }.padding(.top, 14)
                case 2: FocusView(compact: true).padding(.top, 14)
                default: settingsPage
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            HStack(spacing: 0) {
                tabButton(0, title: "Задачи", image: "checkmark.square")
                tabButton(1, title: "Календарь", image: "calendar")
                tabButton(2, title: "Помодоро", image: "timer")
                tabButton(3, title: "Настройки", image: "gearshape")
            }.padding(.vertical, 12)
        }.frame(width: 360, height: 570)
            .foregroundStyle(HidigPalette.forest).background(HidigPalette.surface)
            .onAppear { store.prepareCalendarIndex(around: selectedDate) }
            .onChange(of: selectedDate) { store.prepareCalendarIndex(around: $0) }
    }
    private var taskPage: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                HidigDateButton(date: $selectedDate, compact: true)
                Spacer()
                SyncButton(showTitle: false)
            }
            TextField("Добавить задачу", text: $quickTitle)
                .textFieldStyle(HidigTextFieldStyle()).onSubmit {
                    guard !quickTitle.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    _ = store.createPlannerTask(ManagedTask(title: quickTitle, startDate: PlannerCalendar.current.startOfDay(for: selectedDate), isAllDay: true))
                    store.selectedTaskID = nil; quickTitle = ""
                }
            dailyList
        }.padding(.horizontal, 16).padding(.top, 18)
    }
    private var dailyList: some View {
        let tasks = store.calendarTasks(on: selectedDate).sorted {
            if $0.isAllDay != $1.isAllDay { return !$0.isAllDay }
            return ($0.startDate ?? $0.dueDate ?? .distantFuture) < ($1.startDate ?? $1.dueDate ?? .distantFuture)
        }
        let active = tasks.filter { $0.status == .active }
        let completed = tasks.filter { $0.status == .completed }
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                Text(PlannerCalendar.current.isDateInToday(selectedDate) ? "Сегодня" : selectedDate.formatted(date: .abbreviated, time: .omitted))
                    .hidigFont(size: 11).foregroundStyle(HidigPalette.secondary).padding(.vertical, 6)
                if tasks.isEmpty { Text("На этот день задач нет").foregroundStyle(HidigPalette.secondary).padding(.vertical, 14) }
                ForEach(PlannerTaskTree.rows(active, collapsed: collapsed)) { row in taskRow(row) }
                if !completed.isEmpty {
                    Text("Выполнено").hidigFont(size: 11).foregroundStyle(HidigPalette.secondary).padding(.top, 16).padding(.bottom, 5)
                    ForEach(PlannerTaskTree.rows(completed, collapsed: collapsed)) { row in taskRow(row).opacity(0.5) }
                }
            }.padding(.bottom, 12)
        }.padding(.horizontal, tab == 1 ? 16 : 0)
    }
    private func taskRow(_ row: PlannerTaskTree.Row) -> some View {
        let task = row.task
        return HStack(spacing: 7) {
            if row.hasChildren {
                Button {
                    if collapsed.contains(task.id) { collapsed.remove(task.id) } else { collapsed.insert(task.id) }
                } label: { Image(systemName: collapsed.contains(task.id) ? "chevron.right" : "chevron.down").font(.system(size: 9)) }
                    .buttonStyle(.plain).frame(width: 12).help("Подзадачи")
            }
            Toggle("", isOn: Binding(get: { task.status == .completed }, set: { store.setManagedTaskCompleted(task.id, completed: $0) }))
                .toggleStyle(TaskCheckboxStyle()).foregroundStyle(task.priority.accent)
                .accessibilityLabel(task.status == .completed ? "Вернуть задачу в активные" : "Выполнить задачу")
            Button { openTask(task) } label: {
                HStack(spacing: 5) {
                    Text(task.title).hidigFont(size: 13).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    if task.repeatRule != nil || task.seriesRootID != nil { Image(systemName: "repeat").font(.system(size: 10)).foregroundStyle(HidigPalette.secondary) }
                    if !task.reminders.isEmpty { Image(systemName: "bell").font(.system(size: 10)).foregroundStyle(HidigPalette.secondary) }
                    if task.priority != .none { Image(systemName: "flag.fill").font(.system(size: 9)).foregroundStyle(task.priority.accent) }
                    Text(task.isAllDay ? "Весь день" : task.startDate.map(PlannerCalendar.time) ?? "Без времени")
                        .hidigFont(size: 11).foregroundStyle(HidigPalette.controlFill).fixedSize()
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.padding(.leading, CGFloat(row.depth) * 12).frame(minHeight: 33)
    }
    private func openTask(_ task: ManagedTask) {
        store.planner.anchor = selectedDate
        store.planner.presentation = .calendar
        store.selectedSection = .calendar
        store.selectedTaskID = task.id
        NSApplication.shared.activate(ignoringOtherApps: true); openWindow(id: "main")
    }
    private func tabButton(_ value: Int, title: String, image: String) -> some View {
        Button { tab = value } label: {
            Image(systemName: image).font(.system(size: 19)).frame(maxWidth: .infinity, minHeight: 28)
                .foregroundStyle(tab == value ? HidigPalette.controlFill : HidigPalette.secondary)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(title).help(title)
    }
    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("hidigFocus").hidigFont(size: 23, weight: .semibold)
            Label(store.protectionEnabled ? "Защита включена" : "Защита выключена", systemImage: "shield")
            Text("Задачи блокировки: \(store.completedTaskCount)/\(store.todayTasks.count)")
            Button("Открыть hidigFocus") { NSApplication.shared.activate(ignoringOtherApps: true); openWindow(id: "main") }.buttonStyle(PrimaryButtonStyle())
            Button("Отдельное окно помодоро") { NSApplication.shared.activate(ignoringOtherApps: true); openWindow(id: "focus") }.buttonStyle(SecondaryButtonStyle())
            Spacer()
            Button("Завершить приложение") { NSApplication.shared.terminate(nil) }.buttonStyle(GhostButtonStyle())
        }.padding(22)
    }
}

private struct MenuMonthCalendar: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: PlannerWorkspace
    @Binding var selection: Date
    @State private var month = Date()
    private var calendar: Calendar { PlannerCalendar.current }
    private var days: [Date] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: month)) ?? month
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0 - offset, to: first) }
    }
    var body: some View {
        let _ = workspace.calendarRevision
        return VStack(spacing: 8) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).hidigFont(size: 16, weight: .semibold)
                Spacer()
                Button { step(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Предыдущий месяц")
                Button { month = Date(); selection = Date() } label: { Image(systemName: "circle") }.accessibilityLabel("Сегодня")
                Button { step(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Следующий месяц")
            }.buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 4) {
                ForEach(0..<7, id: \.self) { index in
                    Text(calendar.shortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                        .hidigFont(size: 10).foregroundStyle(HidigPalette.secondary)
                }
                ForEach(days, id: \.self) { day in
                    let selected = calendar.isDate(day, inSameDayAs: selection)
                    let hasTasks = !store.calendarTasks(on: day).isEmpty
                    Button { selection = day } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.day())).hidigFont(size: 12)
                                .frame(width: 28, height: 28)
                                .background(selected ? HidigPalette.controlFill : .clear).clipShape(Circle())
                                .foregroundStyle(selected ? .white : calendar.isDate(day, equalTo: month, toGranularity: .month) ? HidigPalette.forest : HidigPalette.secondary)
                            Circle().fill(hasTasks ? HidigPalette.controlFill : .clear).frame(width: 3, height: 3)
                        }.frame(maxWidth: .infinity).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                }
            }
        }.padding(.horizontal, 16)
            .onAppear { month = selection; store.prepareCalendarIndex(around: month) }
            .onChange(of: month) { store.prepareCalendarIndex(around: $0) }
    }
    private func step(_ value: Int) { month = calendar.date(byAdding: .month, value: value, to: month) ?? month }
}
