import XCTest
import SwiftUI
@testable import hidigFocus

final class CalendarInteractionControllerTests: XCTestCase {
    private final class ValueBox<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
        var binding: Binding<Value> { Binding(get: { self.value }, set: { self.value = $0 }) }
    }
    private final class Fixture {
        let suite: String
        let defaults: UserDefaults
        let workspace: PlannerWorkspace
        let pan = CalendarPanState()
        let scroller = CalendarDragScroller()
        let preview = CalendarAllDayPreview()
        let region = ValueBox(CalendarAllDayDropRegion(bounds: CGRect(x: 100, y: 200, width: 800, height: 120)))
        let drop = ValueBox<Date?>(nil)
        let width = ValueBox<CGFloat>(200)
        let interactionAnchor = ValueBox<Date?>(nil)
        init(anchor: Date) {
            let suite = "CalendarInteractionControllerTests.\(UUID())"
            let defaults = UserDefaults(suiteName: suite)!
            self.suite = suite
            self.defaults = defaults
            workspace = PlannerWorkspace(defaults: defaults)
            workspace.anchor = anchor
        }
        func bind(_ controller: CalendarInteractionController) {
            controller.bind(scroller: scroller, pan: pan, workspace: workspace, preview: preview,
                            region: region.binding, dropDay: drop.binding,
                            columnWidth: width.binding, interactionAnchor: interactionAnchor.binding)
        }
        deinit { defaults.removePersistentDomain(forName: suite) }
    }
    private var calendar: Calendar { PlannerCalendar.current }
    private var anchor: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: 9))!
    }

    func testCachedActionReadsLiveRegionWidthAnchorAndPan() throws {
        let fixture = Fixture(anchor: anchor)
        let controller = CalendarInteractionController()
        fixture.bind(controller)
        let action = controller.allDayDragActions
        let task = ManagedTask(title: "Перенос")
        XCTAssertEqual(action.update(CGPoint(x: 150, y: 250), task), calendar.startOfDay(for: anchor))

        fixture.interactionAnchor.value = calendar.date(byAdding: .day, value: 3, to: anchor)
        fixture.region.value.bounds = CGRect(x: 200, y: 200, width: 600, height: 100)
        fixture.width.value = 100
        fixture.pan.offset = -125
        let expected = try XCTUnwrap(calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: anchor)))
        XCTAssertEqual(action.update(CGPoint(x: 350, y: 250), task), expected)
        XCTAssertEqual(fixture.drop.value, expected)
        XCTAssertEqual(fixture.preview.item?.task.id, task.id)

        fixture.interactionAnchor.value = nil
        fixture.workspace.anchor = calendar.date(byAdding: .day, value: 10, to: anchor)!
        XCTAssertEqual(action.update(CGPoint(x: 350, y: 250), task),
                       calendar.date(byAdding: .day, value: 12, to: calendar.startOfDay(for: anchor)))
        fixture.width.value = 0
        XCTAssertNil(action.update(CGPoint(x: 350, y: 250), task))
        XCTAssertNil(fixture.drop.value)
        XCTAssertNil(fixture.preview.item)
    }

    func testAllDayHitUsesVisibleAnimationSampleInsteadOfTarget() {
        let fixture = Fixture(anchor: anchor)
        let controller = CalendarInteractionController()
        fixture.bind(controller)
        let action = controller.allDayDragActions
        fixture.pan.animate(to: -300, reduceMotion: false)
        fixture.pan.recordPresentation(-60, token: fixture.pan.presentationToken)
        XCTAssertEqual(action.update(CGPoint(x: 250, y: 250), ManagedTask(title: "Перенос")),
                       calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: anchor)))
    }

    func testUnbindClearsOldPreviewAndCachedActionCanRebind() {
        let first = Fixture(anchor: anchor)
        let second = Fixture(anchor: calendar.date(byAdding: .day, value: 20, to: anchor)!)
        let controller = CalendarInteractionController()
        first.bind(controller)
        let action = controller.allDayDragActions
        let scroll = controller.autoscrollActions
        let task = ManagedTask(title: "Перенос")
        XCTAssertNotNil(action.update(CGPoint(x: 150, y: 250), task))
        controller.unbind()
        XCTAssertNil(first.drop.value)
        XCTAssertNil(first.preview.item)
        XCTAssertNil(action.update(CGPoint(x: 150, y: 250), task))
        XCTAssertEqual(scroll(nil), .zero)
        second.bind(controller)
        XCTAssertEqual(action.update(CGPoint(x: 150, y: 250), task), calendar.startOfDay(for: second.workspace.anchor))
        XCTAssertNil(first.drop.value)
        XCTAssertNil(first.preview.item)
        XCTAssertEqual(second.preview.item?.task.id, task.id)
    }

    func testCachedActionsDoNotRetainControllerOrBoundModels() {
        let fixture = Fixture(anchor: anchor)
        var controller: CalendarInteractionController? = CalendarInteractionController()
        fixture.bind(controller!)
        let action = controller!.allDayDragActions
        let scroll = controller!.autoscrollActions
        weak var weakController = controller
        controller = nil
        XCTAssertNil(weakController)
        XCTAssertNil(action.update(CGPoint(x: 150, y: 250), ManagedTask(title: "Перенос")))
        XCTAssertEqual(scroll(nil), .zero)

        let liveController = CalendarInteractionController()
        var bound: Fixture? = Fixture(anchor: anchor)
        weak var weakPan = bound!.pan
        weak var weakWorkspace = bound!.workspace
        weak var weakScroller = bound!.scroller
        weak var weakPreview = bound!.preview
        bound!.bind(liveController)
        bound = nil
        XCTAssertNil(weakPan)
        XCTAssertNil(weakWorkspace)
        XCTAssertNil(weakScroller)
        XCTAssertNil(weakPreview)
        XCTAssertNil(liveController.allDayDragActions.update(CGPoint(x: 150, y: 250), ManagedTask(title: "Перенос")))
    }
}
