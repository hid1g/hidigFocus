import AppKit
import SwiftUI

struct TaskDetailExtras: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var reminderService: TaskReminderService
    @Binding var task: ManagedTask
    @State private var reminderDate = Date().addingTimeInterval(3600)
    @State private var busyAttachment = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TaskSection(title: "Вложения") {
                ForEach(task.attachments) { attachment in
                    HStack {
                        Button(attachment.name) {
                            if let path = attachment.localPath { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
                            else if let url = attachment.remoteURL { NSWorkspace.shared.open(url) }
                        }.buttonStyle(.borderless)
                        Spacer()
                        Button { task.attachments.removeAll { $0.id == attachment.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("Убрать вложение из задачи")
                            .accessibilityLabel("Убрать вложение: \(attachment.name)")
                    }
                }
                Button(busyAttachment ? "Копируется…" : "Добавить файл…", action: importAttachment).buttonStyle(GhostButtonStyle()).disabled(busyAttachment)
            }
            TaskSection(title: "Напоминания") {
                ForEach(task.reminders) { reminder in
                    HStack {
                        Text(reminder.date?.formatted(date: .abbreviated, time: .shortened) ?? reminder.relativeMinutes.map { "За \($0) мин. до начала" } ?? reminder.sourceValue ?? "Неизвестное правило")
                        Spacer()
                        Button { task.reminders.removeAll { $0.id == reminder.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain)
                            .accessibilityLabel("Удалить напоминание")
                    }
                }
                HStack {
                    HidigDateButton(date: $reminderDate, compact: true)
                    HidigTimeButton(date: $reminderDate, stepMinutes: 15, compact: true)
                    Button { task.reminders.append(TaskReminder(date: reminderDate)) } label: { Image(systemName: "plus") }.buttonStyle(HidigIconButtonStyle()).help("Добавить напоминание")
                }
                Menu {
                    ForEach([0, 5, 15, 30, 60], id: \.self) { minutes in
                        Button(minutes == 0 ? "В момент начала" : "За \(minutes) минут") { task.reminders.append(TaskReminder(relativeMinutes: minutes)) }
                    }
                } label: { Label("Относительно начала", systemImage: "bell") }
                    .menuStyle(.borderlessButton).hidigFont(size: 12).disabled(task.startDate == nil)
                if !reminderService.authorized {
                    Text("Уведомления не разрешены. Задачи продолжают сохраняться.").foregroundStyle(.secondary)
                    Button("Разрешить уведомления") { Task { await reminderService.requestPermission() } }.buttonStyle(GhostButtonStyle())
                }
                if let error = reminderService.error { Text(error).foregroundStyle(.red) }
            }
            TaskSection(title: "Дедлайн") {
                Toggle("Есть независимый срок", isOn: Binding(get: { task.dueDate != nil }, set: { task.dueDate = $0 ? (task.startDate ?? Date()) : nil })).toggleStyle(TaskCheckboxStyle())
                if task.dueDate != nil {
                    HStack { HidigDateButton(date: deadlineBinding, compact: true); HidigTimeButton(date: deadlineBinding, stepMinutes: 15, compact: true) }
                }
                Text("Перенос в календаре меняет плановый интервал и сохраняет этот срок.").foregroundStyle(.secondary)
            }
            TaskSection(title: "История изменений") {
                let changes = store.task(id: task.id)?.changeHistory ?? task.changeHistory
                if changes.isEmpty {
                    Text("Изменений пока нет").foregroundStyle(HidigPalette.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(changes) { change in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(change.summary).fixedSize(horizontal: false, vertical: true)
                                Text(change.date, format: .dateTime.day().month().year().hour().minute())
                                    .hidigFont(size: 11).foregroundStyle(HidigPalette.secondary)
                            }.accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            if task.sourceUnavailable == true { Label("Задача недоступна в источнике. Локальная копия сохранена.", systemImage: "exclamationmark.triangle").foregroundStyle(.secondary) }
        }.hidigFont(size: 12).foregroundStyle(HidigPalette.forest)
    }
    private var deadlineBinding: Binding<Date> { Binding(get: { task.dueDate ?? Date() }, set: { task.dueDate = $0 }) }
    private func importAttachment() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        busyAttachment = true
        let root = store.attachmentDirectoryURL
        Task {
            do {
                let attachment = try await Task.detached(priority: .utility) {
                    let access = source.startAccessingSecurityScopedResource(); defer { if access { source.stopAccessingSecurityScopedResource() } }
                    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                    let target = root.appendingPathComponent(UUID().uuidString).appendingPathExtension(source.pathExtension)
                    try FileManager.default.copyItem(at: source, to: target)
                    return TaskAttachment(name: source.lastPathComponent, localPath: target.path)
                }.value
                task.attachments.append(attachment)
            } catch { store.errorMessage = "Не удалось добавить файл: \(error.localizedDescription)" }
            busyAttachment = false
        }
    }
}

struct TaskChecklistSection: View {
    @Binding var task: ManagedTask
    @State private var checklistTitle = ""
    var body: some View {
        TaskSection(title: "Чек-лист", initiallyExpanded: true) {
            ForEach($task.checklist) { $item in
                HStack {
                    Toggle("", isOn: $item.isCompleted).labelsHidden().toggleStyle(TaskCheckboxStyle())
                        .accessibilityLabel("Пункт чек-листа: \(item.title)")
                    TextField("Пункт", text: $item.title).textFieldStyle(HidigTextFieldStyle())
                    Button { task.checklist.removeAll { $0.id == item.id } } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).help("Удалить пункт")
                        .accessibilityLabel("Удалить пункт: \(item.title)")
                }
            }
            HStack {
                TextField("Новый пункт", text: $checklistTitle).textFieldStyle(HidigTextFieldStyle()).onSubmit(addChecklist)
                Button(action: addChecklist) { Image(systemName: "plus") }.buttonStyle(HidigIconButtonStyle())
                    .accessibilityLabel("Добавить пункт чек-листа")
            }
        }
    }
    private func addChecklist() {
        let title = checklistTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        task.checklist.append(TaskChecklistItem(title: title, sortOrder: Int64(task.checklist.count))); checklistTitle = ""
    }
}
