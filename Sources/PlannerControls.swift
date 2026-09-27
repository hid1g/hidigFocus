import AppKit
import SwiftUI

struct PlannerFilterMenu: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: PlannerWorkspace
    var body: some View {
        HStack(spacing: 8) {
            Menu {
                Toggle("Выполненные", isOn: $workspace.filter.showCompleted)
                Toggle("Локальные задачи", isOn: $workspace.filter.showLocal)
                Toggle("Задачи TickTick", isOn: $workspace.filter.showImported)
                Toggle("События календаря", isOn: $workspace.filter.showEvents)
                Divider()
                Menu("Списки") {
                    ForEach(store.taskLists) { list in
                        Toggle(list.name, isOn: Binding(get: { workspace.filter.listIDs.contains(list.id) }, set: { enabled in
                            if enabled { workspace.filter.listIDs.insert(list.id) } else { workspace.filter.listIDs.remove(list.id) }
                        }))
                    }
                }
                Menu("Приоритет") {
                    Button("Любой") { workspace.filter.priority = nil }
                    ForEach(TaskPriority.allCases) { priority in
                        Button(priority.title) { workspace.filter.priority = priority }
                    }
                }
                Divider()
                Button("Сбросить фильтры") { workspace.filter = PlannerFilter(); workspace.search = "" }
            } label: { Label(workspace.filter.isActive ? "Фильтры включены" : "Фильтры", systemImage: "line.3.horizontal.decrease.circle") }
            .fixedSize()
            Menu {
                ForEach(PlannerSort.allCases, id: \.rawValue) { sort in
                    Button(sort.title) { workspace.sort = sort }
                }
            } label: { Label(workspace.sort.title, systemImage: "arrow.up.arrow.down") }
            Spacer()
            if workspace.filter.isActive || !workspace.search.isEmpty {
                Button("Сбросить") { workspace.filter = PlannerFilter(); workspace.search = "" }.buttonStyle(.borderless)
            }
            SaveStatusView()
        }.font(.system(size: 11)).padding(.horizontal, 16).padding(.vertical, 7)
    }
}

struct SaveStatusView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Group {
            switch store.taskSaveState {
            case .idle: EmptyView()
            case .saving: Text("Сохраняется…")
            case .saved: Text("Сохранено")
            case .failed: Button("Повторить сохранение") { store.save() }
            }
        }.font(.system(size: 10)).foregroundStyle(.secondary).accessibilityLabel("Состояние сохранения")
    }
}

struct BulkTaskActions: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: PlannerWorkspace
    @State private var tag = ""
    @State private var showsTagEditor = false
    @State private var batchDate = Date()
    @State private var showsBatchDate = false
    var body: some View {
        HStack {
            Text("Выбрано: \(workspace.selectedIDs.count)")
            Button("Выполнить") { store.bulkComplete(workspace.selectedIDs) }
            Menu("Дата") {
                Button("Сегодня") { schedule(0) }; Button("Завтра") { schedule(1) }
                Button("Без даты") { store.bulkEdit(workspace.selectedIDs) { $0.startDate = nil; $0.plannedEndDate = nil } }
            }
            Button("Другая дата") { showsBatchDate = true }.popover(isPresented: $showsBatchDate) {
                VStack {
                    DatePicker("Плановое начало", selection: $batchDate)
                    Button("Перенести") {
                        store.bulkEdit(workspace.selectedIDs) { $0.startDate = batchDate; $0.plannedEndDate = batchDate.addingTimeInterval(Double($0.durationMinutes * 60)); $0.isAllDay = false }
                        showsBatchDate = false
                    }
                }.padding(16)
            }
            Menu("Список") {
                ForEach(store.taskLists) { list in Button(list.name) { store.bulkEdit(workspace.selectedIDs) { $0.listID = list.id } } }
            }
            Menu("Приоритет") {
                ForEach(TaskPriority.allCases) { priority in Button(priority.title) { store.bulkEdit(workspace.selectedIDs) { $0.priority = priority } } }
            }
            Menu("Метки") {
                ForEach(Array(Set(store.state.managedTasks.flatMap(\.tags))).sorted(), id: \.self) { tag in
                    Button(tag) { store.bulkEdit(workspace.selectedIDs) { if !$0.tags.contains(tag) { $0.tags.append(tag) } } }
                }
            }
            Button("Новая метка") { showsTagEditor = true }.popover(isPresented: $showsTagEditor) {
                HStack {
                    TextField("Метка", text: $tag)
                    Button("Добавить") {
                        let value = tag.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !value.isEmpty { store.bulkEdit(workspace.selectedIDs) { if !$0.tags.contains(value) { $0.tags.append(value) } } }
                        tag = ""; showsTagEditor = false
                    }
                }.padding(16)
            }
            Button { store.bulkTrash(workspace.selectedIDs) } label: { Image(systemName: "trash") }.help("В корзину")
            Button("Снять выбор") { workspace.selectedIDs = [] }
        }.font(.system(size: 11)).padding(10).frame(maxWidth: .infinity, alignment: .leading).background(HidigPalette.surfaceRaised)
    }
    private func schedule(_ days: Int) {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: Date())) ?? Date()
        store.bulkEdit(workspace.selectedIDs) { task in
            task.startDate = date; task.isAllDay = true
            task.plannedEndDate = date.addingTimeInterval(Double(task.durationMinutes * 60))
        }
    }
}

/// Placeholder and caret share NSTextView's actual text-container origin.
struct TaskNotesEditor: NSViewRepresentable {
    @Binding var text: String
    @Environment(\.hidigTextScale) private var scale
    @Environment(\.hidigFontPreference) private var preference
    private var editorFont: NSFont {
        let size = 13 * scale
        switch preference {
        case .system: return .systemFont(ofSize: size)
        case .rounded: return NSFont(descriptor: NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.rounded) ?? NSFont.systemFont(ofSize: size).fontDescriptor, size: size) ?? .systemFont(ofSize: size)
        case .serif: return NSFont(descriptor: NSFont.systemFont(ofSize: size).fontDescriptor.withDesign(.serif) ?? NSFont.systemFont(ofSize: size).fontDescriptor, size: size) ?? .systemFont(ofSize: size)
        case .monospaced: return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .avenir: return NSFont(name: "AvenirNext-Regular", size: size) ?? .systemFont(ofSize: size)
        case .georgia: return NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }
    func makeNSView(context: Context) -> NSScrollView {
        let view = PlaceholderTaskTextView()
        view.delegate = context.coordinator; view.isRichText = false; view.allowsUndo = true
        view.font = editorFont; view.textColor = .labelColor
        view.drawsBackground = false; view.textContainerInset = NSSize(width: 0, height: 8)
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.autoresizingMask = [.width]
        view.string = text; view.setAccessibilityLabel("Описание задачи")
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true; scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.binding = $text
        guard let view = scroll.documentView as? PlaceholderTaskTextView else { return }
        view.font = editorFont
        if view.string != text {
            let range = view.selectedRange(); view.string = text
            view.setSelectedRange(NSRange(location: min(range.location, text.utf16.count), length: 0))
        }
        view.needsDisplay = true
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var binding: Binding<String>
        init(text: Binding<String>) { binding = text }
        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            binding.wrappedValue = view.string; view.needsDisplay = true
        }
    }
}
private final class PlaceholderTaskTextView: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.placeholderTextColor]
        ("Описание" as NSString).draw(at: textContainerOrigin, withAttributes: attributes)
    }
}

struct PlannerScrollPosition: NSViewRepresentable {
    let key: String
    let workspace: PlannerWorkspace
    var initialY: CGFloat = 0
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { let view = NSView(); context.coordinator.attach(view, key: key, workspace: workspace, initialY: initialY); return view }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.attach(view, key: key, workspace: workspace, initialY: initialY) }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.detach() }
    final class Coordinator {
        weak var scroll: NSScrollView?
        var observer: NSObjectProtocol?
        var activeKey: String?
        func attach(_ view: NSView, key: String, workspace: PlannerWorkspace, initialY: CGFloat) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let scroll = view?.enclosingScrollView else { return }
                guard self.scroll !== scroll || self.activeKey != key else { return }
                self.detach(); self.scroll = scroll; self.activeKey = key
                scroll.contentView.postsBoundsChangedNotifications = true
                scroll.contentView.scroll(to: workspace.scrollPositions[key] ?? CGPoint(x: 0, y: initialY))
                scroll.reflectScrolledClipView(scroll.contentView)
                self.observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak scroll] _ in
                    if let scroll { workspace.scrollPositions[key] = scroll.contentView.bounds.origin }
                }
            }
        }
        func detach() { if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil }
        deinit { detach() }
    }
}
