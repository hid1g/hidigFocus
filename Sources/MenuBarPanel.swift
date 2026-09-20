import AppKit
import SwiftUI

struct MenuBarPanel: View {
    @Environment(\.hidigPaletteIdentity) private var paletteIdentity
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            taskProgress
            habits
            footer
        }
        .padding(10)
        .frame(width: 350)
        .foregroundStyle(HidigPalette.forest)
        .background(HidigPalette.canvas)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
        .padding(15)
        .background(HidigPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
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
        .padding(15)
        .background(HidigPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var habits: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionEyebrow(text: "Привычки")
                Spacer()
                Text("\(checkedHabits)/\(store.habitsDueToday.count)")
                    .hidigFont(size: 11, weight: .bold)
                    .foregroundStyle(HidigPalette.secondary)
            }
            if store.habitsDueToday.isEmpty {
                Text(store.habits.isEmpty ? "Добавьте привычку в основном окне." : "На сегодня привычек нет.")
                    .hidigFont(size: 11)
                    .foregroundStyle(HidigPalette.secondary)
            } else {
                ForEach(store.habitsDueToday.prefix(5)) { habit in
                    HidigCheckboxRow(
                        title: habit.name,
                        isOn: habit.isChecked(on: Date()),
                        action: { store.toggleHabit(habit.id) }
                    )
                }
                if store.habitsDueToday.count > 5 {
                    Text("Ещё \(store.habitsDueToday.count - 5)")
                        .hidigFont(size: 10, weight: .medium)
                        .foregroundStyle(HidigPalette.secondary)
                }
            }
        }
        .padding(15)
        .background(HidigPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
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
        .padding(12)
        .background(HidigPalette.surface)
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(HidigPalette.line))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    private var checkedHabits: Int {
        store.habitsDueToday.filter { $0.isChecked(on: Date()) }.count
    }

    private var taskStatus: String {
        guard !store.todayTasks.isEmpty else { return store.connectionState.title }
        let remaining = store.todayTasks.count - store.completedTaskCount
        return remaining == 0
            ? "Все задачи выполнены"
            : "Осталось \(RussianPluralizer.phrase(remaining, one: "задача", few: "задачи", many: "задач"))"
    }
}
