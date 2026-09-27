import AppKit
import SwiftUI

/// Axis remains locked for the full gesture, including momentum.
struct CalendarAxisLock {
    enum Axis { case undecided, horizontal, vertical }
    private(set) var axis: Axis = .undecided
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    mutating func reset() { axis = .undecided; x = 0; y = 0 }
    mutating func accept(dx: CGFloat, dy: CGFloat) -> Bool {
        if axis == .undecided {
            x += dx; y += dy
            guard max(abs(x), abs(y)) >= 3 else { return false }
            axis = abs(x) > abs(y) * 1.15 ? .horizontal : .vertical
        }
        return axis == .horizontal
    }
}

private struct CalendarAutoscrollKey: EnvironmentKey { static let defaultValue: (CGPoint?) -> CGSize = { _ in .zero } }
extension EnvironmentValues {
    var calendarAutoscroll: (CGPoint?) -> CGSize {
        get { self[CalendarAutoscrollKey.self] }
        set { self[CalendarAutoscrollKey.self] = newValue }
    }
}
final class CalendarDragScroller: ObservableObject {
    weak var scroll: NSScrollView?
    var changeDay: ((Int) -> Void)?
    var dayWidth: CGFloat = 0
    private var timer: Timer?
    private var point: CGPoint?
    private var total = CGSize.zero
    private var lastDay = Date.distantPast
    func update(_ point: CGPoint?) -> CGSize {
        self.point = point
        if point == nil { timer?.invalidate(); timer = nil; total = .zero; return .zero }
        if timer == nil {
            timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(timer!, forMode: .common)
        }
        return total
    }
    private func tick() {
        guard let point, let scroll, let window = scroll.window else { return }
        let mouse = scroll.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let height = scroll.bounds.height
        let delta: CGFloat = mouse.y < 40 ? -8 : (mouse.y > height - 40 ? 8 : 0)
        if delta != 0 {
            let origin = scroll.contentView.bounds.origin
            let limit = max(0, (scroll.documentView?.bounds.height ?? height) - height)
            let next = min(limit, max(0, origin.y + delta))
            scroll.contentView.scroll(to: CGPoint(x: origin.x, y: next)); scroll.reflectScrolledClipView(scroll.contentView)
            total.height += next - origin.y
        }
        _ = point
        let direction = mouse.x < 58 ? -1 : (mouse.x > scroll.bounds.width - 25 ? 1 : 0)
        if direction != 0, Date().timeIntervalSince(lastDay) > 0.7 {
            lastDay = Date(); total.width += CGFloat(direction) * dayWidth; changeDay?(direction)
        }
    }
    deinit { timer?.invalidate() }
}
struct CalendarScrollBinding: NSViewRepresentable {
    let scroller: CalendarDragScroller
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in scroller.scroll = view?.enclosingScrollView }
    }
}

/// Include one adjacent day and the previous period during an animated button transition.
enum CalendarRenderWindow {
    static func days(offset: CGFloat, dayWidth: CGFloat, visibleDays: Int) -> ClosedRange<Int> {
        let shifted = Int(floor(-offset / max(1, dayWidth)))
        return min(-1, shifted - 1)...max(visibleDays, shifted + visibleDays)
    }
}
