import AppKit
import XCTest
@testable import hidigFocus

final class CalendarPointerCoordinatesTests: XCTestCase {
    private final class FlippedView: NSView { override var isFlipped: Bool { true } }
    @MainActor func testGesturePointerUsesTopLeftOriginForBothNativeCoordinateDirections() {
        for flippedRoot in [false, true] {
            for flippedScroll in [false, true] {
                let root: NSView = flippedRoot ? FlippedView() : NSView()
                root.frame = CGRect(x: 0, y: 0, width: 900, height: 712)
                let scroll: NSView = flippedScroll ? FlippedView() : NSView()
                scroll.frame = CGRect(x: 110, y: flippedRoot ? 281 : 0, width: 790, height: 431)
                root.addSubview(scroll)
                for y in [0.0, 20, 215, 411, 431] {
                    let actual = CalendarPointerCoordinates.location(CGPoint(x: 510, y: 281 + y), root: root, scroll: scroll)
                    XCTAssertEqual(actual.x, 400, accuracy: 0.001)
                    XCTAssertEqual(actual.y, y, accuracy: 0.001)
                }
                let center = CalendarPointerCoordinates.location(CGPoint(x: 510, y: 500), root: root, scroll: scroll)
                XCTAssertEqual(CalendarAutoscrollMotion.delta(pointer: center.y, extent: 431, elapsed: 1.0/60), 0)
                let top = CalendarPointerCoordinates.location(CGPoint(x: 510, y: 285), root: root, scroll: scroll)
                let bottom = CalendarPointerCoordinates.location(CGPoint(x: 510, y: 708), root: root, scroll: scroll)
                XCTAssertLessThan(CalendarAutoscrollMotion.delta(pointer: top.y, extent: 431, elapsed: 1.0/60), 0)
                XCTAssertGreaterThan(CalendarAutoscrollMotion.delta(pointer: bottom.y, extent: 431, elapsed: 1.0/60), 0)
            }
        }
    }
    @MainActor func testNativeScrollAndWindowPositionDoNotChangeTheGestureLocation() {
        let root = FlippedView(frame: CGRect(x: 80, y: 100, width: 900, height: 712))
        let scroll = FlippedView(frame: CGRect(x: 110, y: 281, width: 790, height: 431))
        scroll.bounds = CGRect(x: 20, y: 700, width: 790, height: 431)
        root.addSubview(scroll)
        XCTAssertEqual(CalendarPointerCoordinates.location(CGPoint(x: 510, y: 500), root: root, scroll: scroll), CGPoint(x: 400, y: 219))
        scroll.bounds.origin.y = 1200
        XCTAssertEqual(CalendarPointerCoordinates.location(CGPoint(x: 510, y: 500), root: root, scroll: scroll), CGPoint(x: 400, y: 219))
    }
}
