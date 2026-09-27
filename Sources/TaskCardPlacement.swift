import Foundation

/// Place the editor beside the selected card, constrained to the workspace.
enum TaskCardPlacement {
    static func frame(anchor: CGRect, bounds: CGRect, size: CGSize, margin: CGFloat = 12, gap: CGFloat = 12) -> CGRect {
        let usable = bounds.insetBy(dx: min(margin, bounds.width / 2), dy: min(margin, bounds.height / 2))
        let width = min(size.width, usable.width), height = min(size.height, usable.height)
        let right = anchor.maxX + gap
        let left = anchor.minX - gap - width
        let x: CGFloat
        if right + width <= usable.maxX { x = right }
        else if left >= usable.minX { x = left }
        else { x = anchor.midX < bounds.midX ? right : left }
        return CGRect(x: min(max(x, usable.minX), usable.maxX - width),
                      y: min(max(anchor.minY - 20, usable.minY), usable.maxY - height),
                      width: width, height: height)
    }
}

import AppKit
import SwiftUI

/// The in-window editor needs an Escape handler even when a text field has not taken focus.
struct TaskCardEscapeMonitor: NSViewRepresentable {
    let dismiss: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak coordinator = context.coordinator] event in
            guard let coordinator, let view = coordinator.view, event.window === view.window else { return event }
            if event.type == .keyDown, event.keyCode == 53 { coordinator.dismiss?(); return nil }
            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                let point = view.convert(event.locationInWindow, from: nil)
                if !view.bounds.contains(point) { coordinator.dismiss?() }
            }
            return event
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.dismiss = dismiss }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.detach() }
    final class Coordinator {
        weak var view: NSView?
        var dismiss: (() -> Void)?
        var monitor: Any?
        func detach() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
        deinit { detach() }
    }
}
