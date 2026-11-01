import AppKit
import SwiftUI

/// Quantized in hours, so ordinary pixel scrolling does not rebuild every card.
/// Intervals and placements still use the complete day; only offscreen views are omitted.
struct CalendarVisibleMinutes: Equatable {
    let lower: Double
    let upper: Double

    init(offset: CGFloat, viewportHeight: CGFloat, hourHeight: CGFloat) {
        let hour = max(1, hourHeight)
        lower = min(1440, max(0, Double(floor(offset / hour) * 60 - 60)))
        upper = max(lower, min(1440, Double(ceil((offset + viewportHeight) / hour) * 60 + 60)))
    }

    init(lower: Double, upper: Double) {
        self.lower = lower
        self.upper = upper
    }

    func renders(id: UUID, start: Double, end: Double, movingID: UUID?, selectedID: UUID?) -> Bool {
        id == movingID || id == selectedID || (start < upper && end > lower)
    }
}

/// Spatial hysteresis keeps mounted card identities stable during pixel scrolling.
/// Refill before the actual viewport reaches the retained window edge; there is
/// no time debounce and jumps/zoom/resize establish complete coverage immediately.
struct CalendarViewportRenderWindow {
    private(set) var window: CalendarVisibleMinutes?
    private var hourHeight: CGFloat?
    private var viewportHeight: CGFloat?
    private let prefetchMinutes = 90.0
    private let refillMargin = 30.0

    func isCompatible(hourHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        self.hourHeight == max(1, hourHeight) && self.viewportHeight == viewportHeight
    }
    mutating func update(bounds: CGRect, hourHeight: CGFloat) -> Bool {
        let hour = max(1, hourHeight)
        let lower = min(1440, max(0, Double(bounds.minY / hour) * 60))
        let upper = min(1440, max(lower, Double(bounds.maxY / hour) * 60))
        let geometryChanged = !isCompatible(hourHeight: hour, viewportHeight: bounds.height)
        self.hourHeight = hour
        viewportHeight = bounds.height
        if !geometryChanged, let window {
            let lowerGuard = window.lower == 0 ? 0 : window.lower + refillMargin
            let upperGuard = window.upper == 1440 ? 1440 : window.upper - refillMargin
            if lower >= lowerGuard && upper <= upperGuard { return false }
        }
        let next = CalendarVisibleMinutes(
            lower: max(0, floor(lower / 60) * 60 - prefetchMinutes),
            upper: min(1440, ceil(upper / 60) * 60 + prefetchMinutes))
        guard window != next else { return false }
        window = next
        return true
    }
}

final class CalendarTimelineViewport: ObservableObject {
    @Published private(set) var revision: UInt64 = 0
    private var bounds: CGRect?
    private var renderWindow = CalendarViewportRenderWindow()

    func visibleMinutes(hourHeight: CGFloat) -> CalendarVisibleMinutes {
        guard let bounds else {
            return CalendarVisibleMinutes(offset: hourHeight * 6, viewportHeight: hourHeight * 6, hourHeight: hourHeight)
        }
        if renderWindow.isCompatible(hourHeight: hourHeight, viewportHeight: bounds.height),
           let window = renderWindow.window { return window }
        // During a zoom the parent supplies the new scale before the native
        // bounds observer refreshes. Old pixel bounds can temporarily be beyond
        // the new day extent; retain all cards until native clipping catches up.
        let maximumY = max(0, max(1, hourHeight) * 24 - bounds.height)
        if bounds.minY < 0 || bounds.minY > maximumY {
            return CalendarVisibleMinutes(lower: 0, upper: 1440)
        }
        return CalendarVisibleMinutes(offset: bounds.minY, viewportHeight: bounds.height, hourHeight: hourHeight)
    }

    func update(bounds: CGRect, hourHeight: CGFloat) {
        self.bounds = bounds
        guard renderWindow.update(bounds: bounds, hourHeight: hourHeight) else { return }
        revision &+= 1
    }
}

struct CalendarTimelineViewportBinding: NSViewRepresentable {
    let viewport: CalendarTimelineViewport
    let hourHeight: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.hourHeight = hourHeight
        context.coordinator.viewport = viewport
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            guard let view, let scroll = view.enclosingScrollView else { return }
            coordinator?.attach(scroll)
        }
    }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator {
        weak var viewport: CalendarTimelineViewport?
        weak var scroll: NSScrollView?
        var hourHeight: CGFloat = 96
        private var observer: NSObjectProtocol?
        func attach(_ scroll: NSScrollView) {
            if self.scroll !== scroll {
                detach()
                self.scroll = scroll
                scroll.contentView.postsBoundsChangedNotifications = true
                observer = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                    object: scroll.contentView, queue: .main) { [weak self] _ in self?.refresh() }
            }
            refresh()
        }
        private func refresh() {
            if let scroll { viewport?.update(bounds: scroll.contentView.bounds, hourHeight: hourHeight) }
        }
        func detach() {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil; scroll = nil
        }
        deinit { detach() }
    }
}
