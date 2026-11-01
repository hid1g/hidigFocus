import AppKit
import SwiftUI

/// One drawing surface replaces thousands of retained per-event view graphs in a
/// dense day. Virtual accessibility children retain each event and its actions.
struct CalendarDenseTimeline: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var workspace: PlannerWorkspace
    @Environment(\.hidigFontPreference) private var font
    @Environment(\.hidigTextScale) private var scale
    @Environment(\.calendarAutoscroll) private var autoscroll
    @Environment(\.calendarAllDayDrag) private var allDayDrag
    let day: Date
    let items: [CalendarDenseItem]
    let width: CGFloat
    let hourHeight: CGFloat
    let visible: CalendarVisibleMinutes
    @Binding var movingTaskID: UUID?
    let createDraft: (CGFloat, CGFloat?) -> Void
    @State private var hovered: CalendarDenseHit?
    @State private var interaction: Interaction?
    @State private var scrollTranslation = CGSize.zero
    @State private var hoveringAllDay: Date?
    @GestureState private var translation = CGSize.zero

    private struct Interaction {
        let id = UUID()
        let hit: CalendarDenseHit?
        let item: CalendarDenseItem?
        let startY: CGFloat
        let token: Int
    }
    var body: some View {
        GeometryReader { geometry in
            let global = geometry.frame(in: .global)
            let slice = CalendarDenseLayout.drawingSlice(visible: visible, hourHeight: hourHeight)
            Color.clear
            .overlay(alignment: .topLeading) {
                Canvas { context, _ in
                    context.translateBy(x: 0, y: -slice.minY)
                    for item in items where interaction?.item?.id != item.id { draw(item, context: &context) }
                }
                .frame(width: width, height: slice.height).offset(y: slice.minY)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
            .frame(width: width, height: hourHeight * 24)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture(count: 2).onEnded { value in
                if CalendarDenseLayout.hit(value.location, items: items) == nil { createDraft(value.location.y, nil) }
            }.exclusively(before: SpatialTapGesture().onEnded { value in activate(at: value.location) }))
            .simultaneousGesture(DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .updating($translation) { value, state, transaction in transaction.animation = nil; state = value.translation }
                .onChanged { value in
                    if interaction == nil {
                        let local = CGPoint(x: value.startLocation.x - global.minX, y: value.startLocation.y - global.minY)
                        let hit = CalendarDenseLayout.hit(local, items: items)
                        interaction = Interaction(hit: hit, item: hit.flatMap { h in items.first { $0.id == h.id } }, startY: local.y, token: workspace.cancellationToken)
                    }
                    guard let interaction, interaction.token == workspace.cancellationToken,
                          let item = interaction.item, interaction.hit?.part != .completion else { return }
                    if movingTaskID != item.id { movingTaskID = item.id }
                    if interaction.hit?.part == .body { hoveringAllDay = allDayDrag.update(value.location, item.task) }
                    if hoveringAllDay == nil {
                        scrollTranslation = autoscroll(value.location, horizontal: interaction.hit?.part == .body, onChange: { scrollTranslation = $0 })
                    }
                }
                .onEnded { value in finish(value) })
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    let next = CalendarDenseLayout.hit(point, items: items)
                    if next != hovered {
                        hovered = next
                        if next?.part == .start || next?.part == .end { NSCursor.resizeUpDown.set() }
                        else { NSCursor.arrow.set() }
                    }
                case .ended: hovered = nil; NSCursor.arrow.set()
                }
            }
            .overlay(alignment: .topLeading) {
                CalendarDenseAccessibility(items: items, label: "Задачи, \(day.formatted(date: .complete, time: .omitted))",
                    name: accessibilityName, completionTitle: completionTitle,
                    open: { store.selectedTaskID = $0.id }, complete: complete,
                    adjust: adjust)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .topLeading) {
                if let selected = store.selectedTaskID, let item = items.first(where: { $0.id == selected }) {
                    Color.clear.frame(width: item.rect.width, height: item.rect.height)
                        .taskCard(item.task).offset(x: item.rect.minX, y: item.rect.minY).allowsHitTesting(false)
                }
            }
            .overlay(alignment: .topLeading) {
                if let interaction, let item = interaction.item, interaction.hit?.part != .completion {
                    let preview = preview(item, part: interaction.hit?.part ?? .body)
                    Canvas { context, _ in
                        let local = CalendarDenseItem(task: item.task, rect: CGRect(origin: .zero, size: preview.rect.size))
                        draw(local, context: &context, moving: true)
                    }.frame(width: preview.rect.width, height: preview.rect.height)
                        .overlay(alignment: .topLeading) {
                            Text("\(PlannerCalendar.time(preview.start))–\(PlannerCalendar.time(preview.start.addingTimeInterval(Double(preview.duration * 60))))")
                                .hidigFont(size: 11, weight: .semibold).fixedSize().padding(6)
                                .background(HidigPalette.surfaceRaised).clipShape(RoundedRectangle(cornerRadius: 5)).offset(y: -27)
                        }
                        .offset(x: preview.rect.minX, y: preview.rect.minY)
                        .opacity(hoveringAllDay == nil ? 1 : 0).allowsHitTesting(false)
                } else if let interaction, interaction.item == nil {
                    Rectangle().fill(HidigPalette.controlFill.opacity(0.2))
                        .frame(width: width, height: max(2, abs(translation.height)))
                        .offset(y: interaction.startY + min(0, translation.height)).allowsHitTesting(false)
                }
            }
            .contextMenu {
                if let hit = hovered, let item = items.first(where: { $0.id == hit.id }) { TaskContextActions(task: item.task) }
            }
        }
        .frame(width: width, height: hourHeight * 24)
        .transaction { $0.animation = nil }
        .onChange(of: workspace.cancellationToken) { _ in reset() }
        .onChange(of: translation) { value in
            // GestureState resets before onEnded on some OS releases. Let the
            // final commit run first; cancellation still clears the preview.
            if value == .zero, let id = interaction?.id {
                DispatchQueue.main.async {
                    if interaction?.id == id, translation == .zero { reset() }
                }
            }
        }
        .onDisappear { if interaction != nil { reset() }; NSCursor.arrow.set() }
    }

    private func draw(_ item: CalendarDenseItem, context: inout GraphicsContext, moving: Bool = false) {
        let task = item.task, rect = item.rect
        let tint = Color(hex: store.taskList(id: task.listID)?.colorHex ?? "#6A9CC2")
        let inactive = task.status == .completed || task.status == .wontDo
        var c = context
        c.opacity = inactive ? 0.55 : 1
        let path = Path(roundedRect: rect, cornerRadius: 4)
        c.fill(path, with: .color(tint.opacity(moving ? 0.35 : 0.20)))
        c.stroke(path, with: .color(task.priority == .none ? tint.opacity(0.55) : task.priority.accent.opacity(0.55)), lineWidth: 1)
        guard rect.width >= 24 else { return }
        c.clip(to: path)
        if hovered?.id == item.id, rect.width >= 32 {
            let handleWidth = min(30, rect.width - 8)
            for y in [rect.minY + 2, rect.maxY - 4] {
                c.fill(Path(roundedRect: CGRect(x: rect.midX - handleWidth / 2, y: y, width: handleWidth, height: 2), cornerRadius: 1), with: .color(HidigPalette.secondary.opacity(0.7)))
            }
        }
        let layout = CalendarCardLayout(height: rect.height, width: rect.width, scale: scale, font: font, hasPriority: task.priority != .none)
        let check = CGRect(x: rect.minX + layout.padding + 2, y: rect.minY + layout.padding + 4, width: layout.completionSize, height: layout.completionSize)
        let box = Path(roundedRect: check, cornerRadius: 3)
        if task.status == .completed || task.status == .wontDo {
            c.fill(box, with: .color(HidigPalette.controlFill))
            let symbol = c.resolve(Text(Image(systemName: task.status == .completed ? "checkmark" : "xmark"))
                .font(.system(size: 10, weight: .bold)).foregroundColor(HidigPalette.onAccent))
            c.draw(symbol, in: check.insetBy(dx: 3, dy: 3))
        } else { c.stroke(box, with: .color(HidigPalette.secondary.opacity(0.65)), lineWidth: 1) }
        let textX = check.maxX + 5
        let textWidth = max(0, rect.maxX - textX - layout.padding - (task.priority != .none && rect.width > 65 ? 14 : 0))
        let native = CalendarCardLayout.nativeFont(font, size: layout.titleFontSize * scale)
        let lines = CalendarCanvasText.lines(task.title, width: textWidth, font: native, limit: layout.titleLines)
        for (index, line) in lines.enumerated() {
            let text = Text(line).font(font.font(size: layout.titleFontSize * scale, weight: .medium, design: nil))
                .foregroundColor(HidigPalette.forest).strikethrough(inactive)
            c.draw(c.resolve(text), at: CGPoint(x: textX, y: rect.minY + layout.padding + 2 + CGFloat(index) * layout.titleLineHeight), anchor: .topLeading)
        }
        if layout.showsTime, let start = task.startDate {
            let text = Text("\(PlannerCalendar.time(start))–\(PlannerCalendar.time(start.addingTimeInterval(Double(task.durationMinutes * 60))))")
                .font(font.font(size: layout.metadataFontSize * scale, weight: .regular, design: nil)).foregroundColor(HidigPalette.forest.opacity(0.82))
            c.draw(c.resolve(text), at: CGPoint(x: textX, y: rect.minY + layout.padding + 2 + CGFloat(lines.count) * layout.titleLineHeight + 2), anchor: .topLeading)
        }
        if task.priority != .none, rect.width > 65 {
            let flag = c.resolve(Text(Image(systemName: "flag.fill")).font(.system(size: 9)).foregroundColor(task.priority.accent))
            c.draw(flag, at: CGPoint(x: rect.maxX - layout.padding - 5, y: rect.minY + layout.padding + 7), anchor: .center)
        }
    }
    private func activate(at point: CGPoint) {
        guard let hit = CalendarDenseLayout.hit(point, items: items), let item = items.first(where: { $0.id == hit.id }) else { return }
        if hit.part == .completion { complete(item.task) } else { store.selectedTaskID = item.id }
    }
    private func complete(_ task: ManagedTask) {
        if task.status == .wontDo { store.setManagedTaskWontDo(task.id, skipped: false) }
        else { store.setManagedTaskCompleted(task.id, completed: task.status != .completed) }
    }
    private func completionTitle(_ task: ManagedTask) -> String { task.status == .completed || task.status == .wontDo ? "Вернуть в активные" : "Выполнить задачу" }
    private func accessibilityName(_ task: ManagedTask) -> String {
        "\(task.title), \(task.scheduleLabel), \(task.durationMinutes) минут, \(task.priority.title), \(completionTitle(task))"
    }
    private func adjust(_ task: ManagedTask, duration: Int) {
        guard let start = task.startDate else { return }
        let next = max(15, task.durationMinutes + duration)
        if next != task.durationMinutes { store.scheduleManagedTask(task.id, at: start, durationMinutes: next) }
    }
    private func preview(_ item: CalendarDenseItem, part: CalendarDensePart) -> (rect: CGRect, start: Date, duration: Int) {
        let task = item.task, start = task.startDate ?? day
        var rect = item.rect
        let dy = translation.height + scrollTranslation.height
        if part == .body {
            rect = rect.offsetBy(dx: translation.width, dy: dy)
            return (rect, TaskEngine.calendarMoveDate(from: start, translation: CGSize(width: translation.width + scrollTranslation.width, height: dy), dayWidth: width, hourHeight: hourHeight), task.durationMinutes)
        }
        if part == .end {
            rect.size.height = CalendarTaskResize.height(original: rect.height, translation: dy, hourHeight: hourHeight)
            return (rect, start, CalendarTaskResize.duration(original: task.durationMinutes, translation: dy, hourHeight: hourHeight))
        }
        let offset = CalendarTaskResize.topOffset(originalDuration: task.durationMinutes, translation: dy, hourHeight: hourHeight)
        rect.origin.y += CalendarTaskResize.topVisualOffset(originalHeight: rect.height, translation: dy, hourHeight: hourHeight)
        rect.size.height = CalendarTaskResize.topHeight(original: rect.height, translation: dy, hourHeight: hourHeight)
        return (rect, PlannerCalendar.current.date(byAdding: .minute, value: offset, to: start) ?? start, task.durationMinutes - offset)
    }
    private func finish(_ value: DragGesture.Value) {
        defer { reset() }
        guard let interaction, interaction.token == workspace.cancellationToken else { return }
        guard let item = interaction.item, let part = interaction.hit?.part else {
            createDraft(interaction.startY + min(0, value.translation.height), interaction.startY + max(0, value.translation.height))
            return
        }
        guard part != .completion else { return }
        let task = item.task, start = task.startDate ?? day
        if part == .body, let target = allDayDrag.update(value.location, task) { store.scheduleManagedTask(task.id, at: target, allDay: true); return }
        let scroll = autoscroll(value.location, horizontal: part == .body)
        let dy = value.translation.height + scroll.height
        if HidigRuntime.isIsolated {
            HidigQAEvidence.lastCalendarGesture = ["taskID": task.id.uuidString,
                "part": String(describing: part), "translationY": value.translation.height,
                "scrollY": scroll.height, "hourHeight": hourHeight,
                "originalDuration": task.durationMinutes, "netY": dy]
        }
        switch part {
        case .body:
            let next = TaskEngine.calendarMoveDate(from: start, translation: CGSize(width: value.translation.width + scroll.width, height: dy), dayWidth: width, hourHeight: hourHeight)
            store.scheduleManagedTask(task.id, at: next, allDay: false)
        case .end:
            let duration = CalendarTaskResize.duration(original: task.durationMinutes, translation: dy, hourHeight: hourHeight)
            if duration != task.durationMinutes { store.scheduleManagedTask(task.id, at: start, durationMinutes: duration) }
        case .start:
            let delta = CalendarTaskResize.topOffset(originalDuration: task.durationMinutes, translation: dy, hourHeight: hourHeight)
            if delta != 0, let next = PlannerCalendar.current.date(byAdding: .minute, value: delta, to: start) {
                store.scheduleManagedTask(task.id, at: next, durationMinutes: task.durationMinutes - delta)
            }
        case .completion: break
        }
    }
    private func reset() {
        if movingTaskID == interaction?.item?.id { movingTaskID = nil }
        interaction = nil; scrollTranslation = .zero; hoveringAllDay = nil
        _ = autoscroll(nil); _ = allDayDrag.update(nil, nil)
    }
}
