import AppKit

import SwiftUI

struct FocusView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    var compact = false
    @State private var selectedTask: UUID?
    @State private var phase: PomodoroPhase = .work
    @State private var stopwatch = false
    @State private var selectingTask = false
    @State private var taskSearch = ""

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: compact ? 18 : 28) {
                HStack {
                    Text("Помодоро").hidigFont(size: compact ? 18 : 24, weight: .semibold)
                    Spacer()
                    Button { openWindow(id: "focus"); NSApplication.shared.activate(ignoringOtherApps: true) } label: { Image(systemName: "arrow.up.right.square") }
                        .buttonStyle(.plain).help("Открыть отдельное окно").accessibilityLabel("Отдельное окно помодоро")
                }
                Picker("Режим", selection: Binding(get: { store.activePomodoro?.isStopwatch ?? stopwatch }, set: { stopwatch = $0 })) {
                    Text("Помо").tag(false)
                    Text("Секундомер").tag(true)
                }.pickerStyle(.segmented).disabled(store.activePomodoro != nil)
                Button { selectingTask = true } label: {
                    HStack {
                        Text(focusTitle).lineLimit(2)
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }.foregroundStyle(HidigPalette.secondary)
                }.buttonStyle(.plain).disabled(store.activePomodoro != nil)
                    .popover(isPresented: $selectingTask) { taskSelector }
                Menu {
                    Button("Фокус") { phase = .work }
                    Button("Перерыв") { phase = .shortBreak }
                    Button("Длинный перерыв") { phase = .longBreak }
                } label: {
                    HStack(spacing: 8) {
                        Text(phaseTitle)
                        Image(systemName: "chevron.down").font(.system(size: 10))
                    }.padding(.horizontal, 16).padding(.vertical, 9)
                        .background(HidigPalette.surfaceRaised).clipShape(Capsule())
                }.menuStyle(.borderlessButton).fixedSize().disabled(store.activePomodoro != nil)
                    .accessibilityLabel("Интервал")
                FocusClock(active: store.activePomodoro, seconds: idleSeconds, stopwatch: stopwatch, compact: compact)
                HStack(spacing: 12) {
                    if let active = store.activePomodoro {
                        Button(active.pausedAt == nil ? "Пауза" : "Продолжить") {
                            if active.pausedAt == nil { store.pausePomodoro() } else { store.resumePomodoro() }
                        }.buttonStyle(PrimaryButtonStyle())
                        Button("Завершить") { store.finishPomodoro() }.buttonStyle(SecondaryButtonStyle())
                        Button { store.finishPomodoro(completed: false) } label: { Image(systemName: "xmark") }
                            .buttonStyle(HidigIconButtonStyle()).help("Отменить сессию")
                    } else {
                        Button("Начать") { store.startFocus(taskID: selectedTask, phase: phase, stopwatch: stopwatch) }
                            .buttonStyle(PrimaryButtonStyle()).frame(minWidth: 120)
                    }
                }
                if !compact { Spacer(minLength: 0) }
            }.padding(compact ? 12 : 32).frame(maxWidth: compact ? .infinity : 420)
            if !compact {
                Divider()
                overview.padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }.foregroundStyle(HidigPalette.forest).background(HidigPalette.canvas)
    }
    private var focusTitle: String {
        let id = store.activePomodoro?.taskID ?? selectedTask
        return id.flatMap { store.task(id: $0)?.title } ?? "Без задачи"
    }
    private var idleSeconds: Int {
        switch phase {
        case .work: return store.state.taskSettings.workMinutes * 60
        case .shortBreak: return store.state.taskSettings.shortBreakMinutes * 60
        case .longBreak: return store.state.taskSettings.longBreakMinutes * 60
        }
    }
    private var phaseTitle: String {
        switch store.activePomodoro?.phase ?? phase {
        case .work: return "Фокус"
        case .shortBreak: return "Перерыв"
        case .longBreak: return "Длинный перерыв"
        }
    }
    private var taskSelector: some View {
        VStack(spacing: 10) {
            TextField("Найти задачу", text: $taskSearch).textFieldStyle(HidigTextFieldStyle())
            Button("Без задачи") { selectedTask = nil; selectingTask = false }.buttonStyle(GhostButtonStyle())
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(store.state.managedTasks.filter { $0.status == .active && (taskSearch.isEmpty || $0.title.localizedCaseInsensitiveContains(taskSearch)) }) { task in
                        Button(task.title) { selectedTask = task.id; selectingTask = false }
                            .buttonStyle(GhostButtonStyle()).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }.padding(14).frame(width: 320, height: 350).background(HidigPalette.surface)
    }
    private var overview: some View {
        let sessions = store.pomodoroSessions
        let today = sessions.filter { PlannerCalendar.current.isDateInToday($0.startedAt) }
        return VStack(alignment: .leading, spacing: 22) {
            Text("Обзор").hidigFont(size: 23, weight: .semibold)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                metric("Помо сегодня", value: "\(today.filter { $0.phase == .work && $0.wasCompleted }.count)")
                metric("Фокус сегодня", value: "\(today.filter { $0.phase == .work }.reduce(0) { $0 + $1.durationSeconds } / 60) мин")
                metric("Всего помо", value: "\(sessions.filter { $0.phase == .work && $0.wasCompleted }.count)")
                metric("Всего фокуса", value: "\(sessions.filter { $0.phase == .work }.reduce(0) { $0 + $1.durationSeconds } / 60) мин")
            }
            Text("История концентрации").hidigFont(size: 18, weight: .semibold)
            if sessions.isEmpty {
                Text("Сессий пока нет").foregroundStyle(HidigPalette.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(sessions.sorted { $0.startedAt > $1.startedAt }) { session in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.taskID.flatMap { store.task(id: $0)?.title } ?? "Без задачи").lineLimit(1)
                                Text(session.startedAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(HidigPalette.secondary)
                            }
                            Spacer()
                            Text("\(session.durationSeconds / 60) мин").monospacedDigit()
                            Image(systemName: session.wasCompleted ? "checkmark.circle" : "xmark.circle").foregroundStyle(HidigPalette.secondary)
                        }
                    }
                }
            }
        }
    }
    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).hidigFont(size: 12).foregroundStyle(HidigPalette.secondary)
            Text(value).hidigFont(size: 25, weight: .semibold).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(HidigPalette.surfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// Only this lightweight subtree ticks; task lists and calendar do not observe clock updates.
private struct FocusClock: View {
    let active: ActivePomodoro?
    let seconds: Int
    let stopwatch: Bool
    let compact: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = active.map { TaskEngine.focusElapsed($0, now: context.date) } ?? 0
            let countingUp = active?.isStopwatch ?? stopwatch
            let target = max(1, active?.targetSeconds ?? seconds)
            let display = countingUp ? elapsed : max(0, target - elapsed)
            ZStack {
                Circle().stroke(HidigPalette.line.opacity(0.5), lineWidth: 5)
                if active != nil && !countingUp {
                    Circle().trim(from: 0, to: min(1, CGFloat(elapsed) / CGFloat(target)))
                        .stroke(HidigPalette.controlFill, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
                }
                Text(String(format: "%02d:%02d", display / 60, display % 60))
                    .hidigFont(size: compact ? 44 : 56, weight: .regular).monospacedDigit()
            }.frame(width: compact ? 215 : 285, height: compact ? 215 : 285)
        }
    }
}
