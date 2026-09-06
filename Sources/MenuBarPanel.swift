import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(HidigPalette.line)
            taskProgress
            Divider().overlay(HidigPalette.line)
            habits
            Divider().overlay(HidigPalette.line)
            footer
        }
        .frame(width: 330)
        .foregroundStyle(HidigPalette.forest)
        .background(HidigPalette.surface)
    }

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: store.protectionEnabled ? "shield.fill" : "shield.slash")
                .foregroundStyle(store.protectionEnabled ? HidigPalette.lettuceStrong : HidigPalette.warning)
                .frame(width: 34, height: 34)
                .background(HidigPalette.hover)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("hidigFocus").hidigFont(size: 15, weight: .bold, design: .rounded)
                Text(store.protectionEnabled ? "Защита включена" : "Защита выключена")
                    .hidigFont(size: 11, weight: .medium)
                    .foregroundStyle(HidigPalette.secondary)
            }
            Spacer()
            SyncButton(showTitle: false)
        }
        .padding(16)
    }

    private var taskProgress: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionEyebrow(text: "Задачи сегодня")
                Spacer()
                Text("\(store.completedTaskCount)/\(store.todayTasks.count)")
                    .hidigFont(size: 12, weight: .bold, design: .rounded)
            }
            ProgressView(value: Double(store.completedTaskCount), total: Double(max(store.todayTasks.count, 1)))
                .tint(HidigPalette.lettuceStrong)
            Text(taskStatus)
                .hidigFont(size: 11)
                .foregroundStyle(HidigPalette.secondary)
        }
        .padding(16)
    }

    private var habits: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionEyebrow(text: "Привычки")
                Spacer()
                Text("\(checkedHabits)/\(store.habits.count)")
                    .hidigFont(size: 11, weight: .bold)
                    .foregroundStyle(HidigPalette.secondary)
            }
            if store.habits.isEmpty {
                Text("Добавьте привычку в основном окне.")
                    .hidigFont(size: 11)
                    .foregroundStyle(HidigPalette.secondary)
            } else {
                ForEach(store.habits.prefix(5)) { habit in
                    HidigCheckboxRow(
                        title: habit.name,
                        isOn: habit.isChecked(on: Date()),
                        action: { store.toggleHabit(habit.id) }
                    )
                }
                if store.habits.count > 5 {
                    Text("Ещё \(store.habits.count - 5)")
                        .hidigFont(size: 10, weight: .medium)
                        .foregroundStyle(HidigPalette.secondary)
                }
            }
        }
        .padding(16)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Открыть hidigFocus") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openWindow(id: "main")
            }
            .buttonStyle(PrimaryButtonStyle())
            Spacer()
            Button("Завершить") { NSApplication.shared.terminate(nil) }
                .buttonStyle(GhostButtonStyle())
        }
        .padding(14)
    }

    private var checkedHabits: Int {
        store.habits.filter { $0.isChecked(on: Date()) }.count
    }

    private var taskStatus: String {
        guard !store.todayTasks.isEmpty else { return store.connectionState.title }
        let remaining = store.todayTasks.count - store.completedTaskCount
        return remaining == 0
            ? "Все задачи выполнены"
            : "Осталось \(RussianPluralizer.phrase(remaining, one: "задача", few: "задачи", many: "задач"))"
    }
}
