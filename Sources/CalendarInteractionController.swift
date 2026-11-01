import SwiftUI

/// Stable environment actions read live UI bindings instead of capturing a new
/// calendar view value on every date rebase. No calendar data is owned here.
final class CalendarInteractionController {
    private weak var scroller: CalendarDragScroller?
    private weak var pan: CalendarPanState?
    private weak var workspace: PlannerWorkspace?
    private weak var preview: CalendarAllDayPreview?
    private var region: Binding<CalendarAllDayDropRegion>?
    private var dropDay: Binding<Date?>?
    private var columnWidth: Binding<CGFloat>?
    private var interactionAnchor: Binding<Date?>?

    lazy var autoscrollActions = CalendarAutoscrollActions { [weak self] point, horizontal, onChange in
        self?.scroller?.update(point, horizontal: horizontal, onChange: onChange) ?? .zero
    }
    lazy var allDayDragActions = CalendarAllDayDragActions { [weak self] point, task in
        self?.updateAllDayDrag(point, task)
    }

    func bind(scroller: CalendarDragScroller, pan: CalendarPanState, workspace: PlannerWorkspace,
              preview: CalendarAllDayPreview, region: Binding<CalendarAllDayDropRegion>,
              dropDay: Binding<Date?>, columnWidth: Binding<CGFloat>, interactionAnchor: Binding<Date?>) {
        self.scroller = scroller
        self.pan = pan
        self.workspace = workspace
        self.preview = preview
        self.region = region
        self.dropDay = dropDay
        self.columnWidth = columnWidth
        self.interactionAnchor = interactionAnchor
    }

    func updateAllDayDrag(_ point: CGPoint?, _ task: ManagedTask?) -> Date? {
        guard let point, let task, let region, let columnWidth, let pan, let workspace,
              let day = region.wrappedValue.day(at: point,
                  anchor: interactionAnchor?.wrappedValue ?? workspace.anchor,
                  dayWidth: columnWidth.wrappedValue, panOffset: pan.visibleOffset) else {
            if dropDay?.wrappedValue != nil { dropDay?.wrappedValue = nil }
            if preview?.item != nil { preview?.item = nil }
            return nil
        }
        if dropDay?.wrappedValue != day { dropDay?.wrappedValue = day }
        scroller?.pause()
        preview?.item = .init(task: task, point: point)
        return day
    }

    func unbind() {
        _ = updateAllDayDrag(nil, nil)
        scroller = nil; pan = nil; workspace = nil; preview = nil
        region = nil; dropDay = nil; columnWidth = nil; interactionAnchor = nil
    }
}
