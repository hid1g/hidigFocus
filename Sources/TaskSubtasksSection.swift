import SwiftUI

struct TaskSubtasksSection: View {
    @EnvironmentObject private var store: AppStore
    let parentID: UUID
    var beforeOpening: () -> Void = {}
    @State private var newTitle = ""

    var body: some View {
        let children = store.subtasks(of: parentID)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Подзадачи").hidigFont(size: 12, weight: .semibold)
                Spacer()
                Text("\(children.filter { $0.status == .completed }.count)/\(children.count)")
                    .hidigFont(size: 10).foregroundStyle(HidigPalette.secondary)
            }
            ForEach(children) { child in
                HStack(spacing: 8) {
                    if child.status == .wontDo {
                        Image(systemName: "xmark.square.fill").foregroundStyle(HidigPalette.secondary)
                            .frame(width: 20).help("Не будет выполнена")
                    } else { TaskCompletionButton(task: child, store: store) }
                    Button {
                        beforeOpening()
                        store.selectedTaskID = child.id
                    } label: {
                        HStack(spacing: 5) {
                            Text(child.title).lineLimit(2).multilineTextAlignment(.leading)
                                .foregroundStyle(child.status == .completed || child.status == .wontDo ? HidigPalette.secondary : HidigPalette.forest)
                            Spacer(minLength: 3)
                            if let date = child.startDate ?? child.dueDate {
                                Text(date.formatted(.dateTime.day().month(.abbreviated)))
                                    .hidigFont(size: 10).foregroundStyle(HidigPalette.secondary)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 9))
                                .foregroundStyle(HidigPalette.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Открыть подзадачу: \(child.title)")
                }
                Divider().overlay(HidigPalette.line.opacity(0.5))
            }
            HStack(spacing: 6) {
                TextField("Новая подзадача", text: $newTitle)
                    .textFieldStyle(.plain).onSubmit(addSubtask)
                Button(action: addSubtask) { Image(systemName: "plus").frame(width: 24, height: 26) }
                    .buttonStyle(.plain).help("Добавить подзадачу")
                    .accessibilityLabel("Добавить подзадачу")
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.hidigFont(size: 12)
    }
    private func addSubtask() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        beforeOpening()
        store.addSubtask(to: parentID, title: title)
        newTitle = ""
    }
}
