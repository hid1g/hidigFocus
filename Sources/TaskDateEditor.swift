import SwiftUI

struct TaskDateEditor: View {
    @Binding var task: ManagedTask
    let dismiss: () -> Void
    let allowsRepeat: Bool
    @State private var selection: TaskScheduleSelection
    @State private var month: Date
    @State private var showsRepeat = false

    init(task: Binding<ManagedTask>, allowsRepeat: Bool = true, dismiss: @escaping () -> Void) {
        _task = task
        self.dismiss = dismiss
        self.allowsRepeat = allowsRepeat
        let value = TaskScheduleSelection(task: task.wrappedValue)
        _selection = State(initialValue: value)
        _month = State(initialValue: value.start)
    }
    var body: some View {
        VStack(spacing: 10) {
            Picker("Режим даты", selection: $selection.durationMode) {
                Text("Дата").tag(false)
                Text("Длительность").tag(true)
            }.pickerStyle(.segmented)
            if selection.durationMode {
                dateRow("Начать", date: Binding(get: { selection.start }, set: { date in
                    let duration = selection.end.timeIntervalSince(selection.start)
                    selection.start = date; selection.end = date.addingTimeInterval(duration)
                }))
                dateRow("Закончить", date: $selection.end)
            } else {
                HStack {
                    quickDay("Сегодня", icon: "sun.max", shift: 0)
                    Spacer()
                    quickDay("Завтра", icon: "sunrise", shift: 1)
                    Spacer()
                    quickDay("Через неделю", icon: "calendar.badge.plus", shift: 7)
                    Spacer()
                    Button {
                        let today = selection.calendar.startOfDay(for: Date())
                        selection.start = selection.calendar.date(bySettingHour: 20, minute: 0, second: 0, of: today) ?? today
                        selection.end = selection.start.addingTimeInterval(Double(selection.originalDuration * 60))
                        selection.hasTime = true; month = today
                    } label: { Image(systemName: "moon").frame(width: 42, height: 34) }
                        .buttonStyle(.plain).help("Сегодня вечером").accessibilityLabel("Сегодня вечером")
                }.foregroundStyle(HidigPalette.secondary)
                monthCalendar
            }
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "clock").foregroundStyle(HidigPalette.controlFill)
                if selection.hasTime {
                    if !selection.durationMode { HidigTimeButton(date: Binding(get: { selection.start }, set: { date in
                        let duration = selection.end.timeIntervalSince(selection.start)
                        selection.start = date; selection.end = date.addingTimeInterval(duration)
                    }), stepMinutes: 15, compact: true, timeZoneID: selection.timeZoneID) }
                    else { Text("Время задано") }
                    Spacer()
                    Button { selection.hasTime = false } label: {
                        Label("Без времени", systemImage: "xmark")
                    }.buttonStyle(.plain).foregroundStyle(HidigPalette.secondary)
                } else {
                    Button { selection.hasTime = true } label: {
                        HStack {
                            Text("Без времени")
                            Spacer()
                            Text("Добавить").foregroundStyle(HidigPalette.secondary)
                            Image(systemName: "chevron.right")
                        }.frame(maxWidth: .infinity, minHeight: 30).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("Добавить время задачи")
                }
            }
            Button { showsRepeat = true } label: {
                HStack {
                    Image(systemName: "repeat")
                    Text(selection.repeatRule?.frequency.title ?? "Не повторять")
                    Spacer()
                    Image(systemName: "chevron.right")
                }.frame(maxWidth: .infinity, minHeight: 30).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!allowsRepeat)
                .popover(isPresented: $showsRepeat) {
                    TaskRepeatEditor(rule: $selection.repeatRule, start: selection.start)
                        .padding(16).frame(width: 320).background(HidigPalette.surface)
                }
            if !allowsRepeat {
                Text("Для изменения повторения выберите область «Этот и следующие экземпляры» или «Вся серия».").font(.caption).foregroundStyle(HidigPalette.secondary)
            }
            HidigMenuPicker(options: zones.map { HidigMenuOption(id: $0, title: $0, systemImage: "globe") },
                            selection: $selection.timeZoneID, leadingIcon: "globe")
            if invalidRange {
                Text("Окончание должно быть позже начала.").font(.caption).foregroundStyle(HidigPalette.warning)
            }
            HStack(spacing: 10) {
                Button("Очистить") { task.startDate = nil; task.plannedEndDate = nil; dismiss() }
                    .buttonStyle(SecondaryButtonStyle(expands: true))
                Button("Готово") { selection.apply(to: &task); dismiss() }
                    .buttonStyle(PrimaryButtonStyle(expands: true)).disabled(invalidRange)
            }
        }.hidigFont(size: 12).padding(16).frame(width: 330)
            .background(HidigPalette.surface)
            .environment(\.timeZone, selection.calendar.timeZone)
    }
    private var invalidRange: Bool { selection.durationMode && selection.hasTime && selection.end <= selection.start }
    private var zones: [String] {
        Array(Set([selection.timeZoneID, TimeZone.current.identifier, "Europe/Moscow", "Europe/London", "Europe/Berlin", "Asia/Dubai", "America/New_York"])).sorted()
    }
    private func quickDay(_ title: String, icon: String, shift: Int) -> some View {
        Button {
            if let day = selection.calendar.date(byAdding: .day, value: shift, to: Date()) {
                selection.selectDay(day); month = day
            }
        } label: { Image(systemName: icon).frame(width: 42, height: 34) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title)
    }
    private func dateRow(_ title: String, date: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(HidigPalette.secondary)
            HStack {
                HidigDateButton(date: date, compact: true)
                if selection.hasTime { HidigTimeButton(date: date, stepMinutes: 15, compact: true, timeZoneID: selection.timeZoneID) }
                Spacer(minLength: 0)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var monthCalendar: some View {
        let calendar = selection.calendar
        let first = calendar.dateInterval(of: .month, for: month)?.start ?? month
        let leading = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leading, to: first) ?? first
        let days = (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
        return VStack(spacing: 6) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).hidigFont(size: 14, weight: .semibold)
                Spacer()
                Button { changeMonth(-1) } label: { Image(systemName: "chevron.left").frame(width: 24, height: 26) }
                    .help("Предыдущий месяц").accessibilityLabel("Предыдущий месяц")
                Button { month = Date() } label: { Image(systemName: "circle").frame(width: 24, height: 26) }
                    .help("Текущий месяц").accessibilityLabel("Текущий месяц")
                Button { changeMonth(1) } label: { Image(systemName: "chevron.right").frame(width: 24, height: 26) }
                    .help("Следующий месяц").accessibilityLabel("Следующий месяц")
            }.buttonStyle(.plain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                ForEach(0..<7, id: \.self) { index in
                    Text(calendar.shortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + index) % 7])
                        .foregroundStyle(HidigPalette.secondary).frame(height: 24)
                }
                ForEach(days, id: \.self) { day in
                    let selected = calendar.isDate(day, inSameDayAs: selection.start)
                    let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
                    Button { selection.selectDay(day); month = day } label: {
                        Text("\(calendar.component(.day, from: day))")
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(selected ? HidigPalette.controlFill : .clear)
                            .clipShape(Circle())
                            .foregroundStyle(selected ? Color.white : (inMonth ? HidigPalette.forest : HidigPalette.secondary.opacity(0.5)))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
        }
    }
    private func changeMonth(_ direction: Int) {
        month = selection.calendar.date(byAdding: .month, value: direction, to: month) ?? month
    }
}
