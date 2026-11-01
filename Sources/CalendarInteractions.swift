import AppKit
import SwiftUI
import QuartzCore

/// Axis remains locked for the full gesture, including momentum.
struct CalendarAxisLock {
    enum Axis { case undecided, horizontal, vertical }
    private(set) var axis: Axis = .undecided
    private(set) var horizontalDelta: CGFloat = 0
    private var x: CGFloat = 0
    private var y: CGFloat = 0
    mutating func reset() { axis = .undecided; x = 0; y = 0; horizontalDelta = 0 }
    mutating func accept(dx: CGFloat, dy: CGFloat) -> Bool {
        horizontalDelta = 0
        if axis == .undecided {
            x += dx; y += dy
            guard max(abs(x), abs(y)) >= 3 else { return false }
            axis = abs(x) > abs(y) * 1.15 ? .horizontal : .vertical
            if axis == .horizontal { horizontalDelta = x }
        } else if axis == .horizontal { horizontalDelta = dx }
        return axis == .horizontal
    }
}

struct CalendarAutoscrollActions {
    var update: (CGPoint?, Bool, ((CGSize) -> Void)?) -> CGSize
    func callAsFunction(_ point: CGPoint?, horizontal: Bool = true, onChange: ((CGSize) -> Void)? = nil) -> CGSize {
        update(point, horizontal, onChange)
    }
}
private struct CalendarAutoscrollKey: EnvironmentKey {
    static let defaultValue = CalendarAutoscrollActions { _, _, _ in .zero }
}
extension EnvironmentValues {
    var calendarAutoscroll: CalendarAutoscrollActions {
        get { self[CalendarAutoscrollKey.self] }
        set { self[CalendarAutoscrollKey.self] = newValue }
    }
}
/// Gesture coordinates are top-left/root based. Convert both AppKit flipping
/// conventions explicitly; don't sample a different pointer event during a drag.
enum CalendarPointerCoordinates {
    static func location(_ point: CGPoint, root: NSView, scroll: NSView) -> CGPoint {
        let inRoot = CGPoint(x: root.bounds.minX + point.x,
            y: root.isFlipped ? root.bounds.minY + point.y : root.bounds.maxY - point.y)
        let native = scroll.convert(inRoot, from: root)
        return CGPoint(x: native.x - scroll.bounds.minX,
            y: scroll.isFlipped ? native.y - scroll.bounds.minY : scroll.bounds.maxY - native.y)
    }
}
final class CalendarDragScroller: ObservableObject {
    weak var scroll: NSScrollView?
    var changeDay: ((Int) -> Void)?
    var dayWidth: CGFloat = 0
    private let clock = CalendarFrameClock()
    private var lastFrame: TimeInterval?
    private var point: CGPoint?
    private var total = CGSize.zero
    private var lastDay: TimeInterval?
    private var onChange: ((CGSize) -> Void)?
    private var horizontal = true
    private var zoomAnchor: CalendarZoomAnchor?
    func update(_ point: CGPoint?, horizontal: Bool = true, onChange: ((CGSize) -> Void)? = nil) -> CGSize {
        self.point = point
        self.horizontal = horizontal
        if let onChange { self.onChange = onChange }
        if point == nil { pause(); total = .zero; lastDay = nil; return .zero }
        if lastFrame == nil {
            lastFrame = CACurrentMediaTime()
            clock.start { [weak self] time in self?.tick(at: time) }
        }
        return total
    }
    func pause() { clock.stop(); lastFrame = nil; point = nil; onChange = nil; lastDay = nil }
    func finishZoom() { zoomAnchor = nil }
    func preserveZoom(from oldHeight: Double, to newHeight: Double) {
        guard oldHeight != newHeight, let scroll, let window = scroll.window else { return }
        let clip = scroll.contentView
        let pointer = clip.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let localY = min(clip.bounds.height, max(0, pointer.y - clip.bounds.minY))
        if zoomAnchor == nil {
            zoomAnchor = CalendarZoomAnchor(contentOffset: clip.bounds.minY, localY: localY, hourHeight: oldHeight)
        }
        let target = zoomAnchor?.contentOffset(hourHeight: newHeight, viewportHeight: clip.bounds.height) ?? clip.bounds.minY
        DispatchQueue.main.async { [weak scroll] in
            guard let scroll else { return }
            let limit = max(0, CGFloat(newHeight) * 24 - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: CGPoint(x: scroll.contentView.bounds.minX, y: min(limit, max(0, target))))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
    private func tick(at time: TimeInterval) {
        let elapsed = time - (lastFrame ?? time)
        lastFrame = time
        guard let point, let scroll, let root = scroll.window?.contentView else { pause(); return }
        let before = total
        let mouse = CalendarPointerCoordinates.location(point, root: root, scroll: scroll)
        let height = scroll.bounds.height
        let delta = CalendarAutoscrollMotion.delta(pointer: mouse.y, extent: height, elapsed: elapsed)
        if delta != 0 {
            let origin = scroll.contentView.bounds.origin
            let limit = max(0, (scroll.documentView?.bounds.height ?? height) - height)
            let next = min(limit, max(0, origin.y + delta))
            scroll.contentView.scroll(to: CGPoint(x: origin.x, y: next)); scroll.reflectScrolledClipView(scroll.contentView)
            total.height += next - origin.y
        }
        let direction = horizontal ? (mouse.x < 58 ? -1 : (mouse.x > scroll.bounds.width - 25 ? 1 : 0)) : 0
        if direction == 0 { lastDay = nil }
        else if lastDay == nil || time - (lastDay ?? time) > 0.7 {
            lastDay = time; total.width += CGFloat(direction) * dayWidth; changeDay?(direction)
        }
        if total != before { onChange?(total) }
    }
    deinit { clock.stop() }
}
struct CalendarScrollBinding: NSViewRepresentable {
    let scroller: CalendarDragScroller
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { [weak view] in scroller.scroll = view?.enclosingScrollView }
    }
}

/// Keep nearby days mounted while a fast swipe rebases the visible columns.
enum CalendarRenderWindow {
    static func days(offset: CGFloat, dayWidth: CGFloat, visibleDays: Int) -> ClosedRange<Int> {
        let shifted = Int(floor(-offset / max(1, dayWidth)))
        return min(-3, shifted - 3)...max(visibleDays + 2, shifted + visibleDays + 2)
    }

    /// Keep the previous, current, and next complete periods alive so button navigation
    /// can move already-rendered columns before the anchor is committed.
    static func preloadedPeriods(visibleDays: Int) -> ClosedRange<Int> {
        let count = max(1, visibleDays)
        return min(-3, -count)...max(count + 2, count * 2 - 1)
    }
}

/// Keep pointer feedback continuous; only the committed duration uses quarter hours.
enum CalendarTaskResize {
    static func height(original: CGFloat, translation: CGFloat, hourHeight: CGFloat) -> CGFloat {
        max(max(1, hourHeight) / 4, original + translation)
    }
    static func duration(original: Int, translation: CGFloat, hourHeight: CGFloat) -> Int {
        let minutes = Double(original) + Double(translation / max(1, hourHeight)) * 60
        return max(15, Int((minutes / 15).rounded()) * 15)
    }
    static func topOffset(originalDuration: Int, translation: CGFloat, hourHeight: CGFloat) -> Int {
        let minutes = Double(translation / max(1, hourHeight)) * 60
        return min(originalDuration - 15, Int((minutes / 15).rounded()) * 15)
    }
    static func topHeight(original: CGFloat, translation: CGFloat, hourHeight: CGFloat) -> CGFloat {
        max(max(1, hourHeight) / 4, original - translation)
    }
    static func topVisualOffset(originalHeight: CGFloat, translation: CGFloat, hourHeight: CGFloat) -> CGFloat {
        min(translation, originalHeight - max(1, hourHeight) / 4)
    }
}
