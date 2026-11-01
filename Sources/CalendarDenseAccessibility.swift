import AppKit
import SwiftUI

/// Native virtual elements keep every visible event reachable without retaining
/// a SwiftUI Button graph for each overlapping occurrence and adjacent day.
struct CalendarDenseAccessibility: NSViewRepresentable {
    let items: [CalendarDenseItem]
    let label: String
    let name: (ManagedTask) -> String
    let completionTitle: (ManagedTask) -> String
    let open: (ManagedTask) -> Void
    let complete: (ManagedTask) -> Void
    let adjust: (ManagedTask, Int) -> Void

    func makeNSView(context: Context) -> CalendarDenseAccessibilityView { CalendarDenseAccessibilityView() }
    func updateNSView(_ view: CalendarDenseAccessibilityView, context: Context) { configure(view) }
    func configure(_ view: CalendarDenseAccessibilityView) {
        guard view.lastItems != items || view.accessibilityLabel() != label else { return }
        view.lastItems = items
        view.setAccessibilityLabel(label)
        var next: [CalendarDenseAccessibilityElement] = []
        let existing = Dictionary(uniqueKeysWithValues: view.elements.map { ($0.taskID, $0) })
        for item in items {
            let element = existing[item.id] ?? CalendarDenseAccessibilityElement(taskID: item.id)
            element.owner = view
            element.rect = item.rect
            element.setAccessibilityFrameInParentSpace(item.rect)
            element.setAccessibilityParent(view)
            element.setAccessibilityRole(.button)
            element.setAccessibilityEnabled(true)
            element.setAccessibilityLabel(name(item.task))
            element.setAccessibilityIdentifier("calendar.task.\(item.id.uuidString)")
            element.press = { open(item.task) }
            element.setAccessibilityCustomActions([
                NSAccessibilityCustomAction(name: completionTitle(item.task), handler: { complete(item.task); return true }),
                NSAccessibilityCustomAction(name: "Увеличить длительность на 15 минут", handler: { adjust(item.task, 15); return true }),
                NSAccessibilityCustomAction(name: "Уменьшить длительность на 15 минут", handler: { adjust(item.task, -15); return true })
            ])
            next.append(element)
        }
        view.elements = next
        if view.window != nil { NSAccessibility.post(element: view, notification: .layoutChanged) }
    }
    static func dismantleNSView(_ view: CalendarDenseAccessibilityView, coordinator: ()) {
        view.elements = []; view.lastItems = nil
    }
}

final class CalendarDenseAccessibilityView: NSView {
    var elements: [CalendarDenseAccessibilityElement] = []
    var lastItems: [CalendarDenseItem]?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityChildren() -> [Any]? { elements }
    override func accessibilityVisibleChildren() -> [Any]? {
        let visible = visibleRect.intersection(bounds)
        return elements.filter { $0.rect.intersects(visible) }
    }
    override func accessibilityFrame() -> NSRect {
        guard let window else { return .zero }
        let visible = visibleRect.intersection(bounds)
        guard !visible.isNull, !visible.isEmpty else { return .zero }
        return window.convertToScreen(convert(visible, to: nil))
    }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        elements.reversed().first { $0.accessibilityFrame().contains(point) } ?? super.accessibilityHitTest(point)
    }
}

final class CalendarDenseAccessibilityElement: NSAccessibilityElement {
    let taskID: UUID
    weak var owner: NSView?
    var rect = CGRect.zero
    var press: (() -> Void)?
    init(taskID: UUID) { self.taskID = taskID; super.init() }
    override func accessibilityFrame() -> NSRect {
        guard let owner, let window = owner.window else { return .zero }
        return window.convertToScreen(owner.convert(rect, to: nil))
    }
    override func accessibilityPerformPress() -> Bool {
        guard let press else { return false }
        press(); return true
    }
}
