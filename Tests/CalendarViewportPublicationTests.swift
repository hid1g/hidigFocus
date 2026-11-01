import XCTest
import Combine
@testable import hidigFocus

final class CalendarViewportPublicationTests: XCTestCase {
    func testSubpixelBoundaryOscillationPublicationCount() {
        let viewport = CalendarTimelineViewport()
        var publications = 0
        let observer = viewport.objectWillChange.sink { publications += 1 }
        for index in 0..<600 {
            viewport.update(bounds: CGRect(x: 0, y: 720 + (index.isMultiple(of: 2) ? -0.5 : 0.5), width: 1000, height: 650), hourHeight: 120)
        }
        XCTAssertLessThanOrEqual(publications, 2, "Subpixel reversal must not repeatedly rebuild all calendar columns")
        print("VIEWPORT_CANDIDATE boundaryOscillation events=600 publications=\(publications)")
        withExtendedLifetime(observer) {}
    }
    func testOneDaySweepPublicationCountAndCoverage() {
        let viewport = CalendarTimelineViewport()
        var publications = 0
        let observer = viewport.objectWillChange.sink { publications += 1 }
        for pixel in stride(from: 0, through: 2000, by: 2) {
            viewport.update(bounds: CGRect(x: 0, y: pixel, width: 1000, height: 650), hourHeight: 120)
            let visible = viewport.visibleMinutes(hourHeight: 120)
            XCTAssertLessThanOrEqual(visible.lower, Double(pixel) / 2)
            XCTAssertGreaterThanOrEqual(visible.upper, min(1440, Double(pixel + 650) / 2))
        }
        XCTAssertLessThan(publications, 20)
        print("VIEWPORT_CANDIDATE oneWaySweep events=1001 publications=\(publications)")
        withExtendedLifetime(observer) {}
    }
    func testCoverageOnJumpsReversalsZoomAndResize() {
        let viewport = CalendarTimelineViewport()
        for scale: CGFloat in [44, 64.79532334953547, 96, 120] {
            for height: CGFloat in [300, 651, 1400, 3000] {
                let maximum = max(0, scale * 24 - height)
                let offsets: [CGFloat] = [0, maximum, maximum / 2, 0, maximum * 0.8, maximum * 0.79, 1, maximum]
                for y in offsets {
                    viewport.update(bounds: CGRect(x: 0, y: y, width: 1000, height: height), hourHeight: scale)
                    let rendered = viewport.visibleMinutes(hourHeight: scale)
                    let actualLower = min(1440, max(0, Double(y / scale) * 60))
                    let actualUpper = min(1440, Double((y + height) / scale) * 60)
                    XCTAssertLessThanOrEqual(rendered.lower, actualLower)
                    XCTAssertGreaterThanOrEqual(rendered.upper, actualUpper)
                    XCTAssertGreaterThanOrEqual(rendered.lower, 0)
                    XCTAssertLessThanOrEqual(rendered.upper, 1440)
                }
            }
        }
    }

    func testScaleReadBeforeNativeObserverRefreshStillCoversViewport() {
        let viewport = CalendarTimelineViewport()
        let bounds = CGRect(x: 0, y: 720, width: 1000, height: 651)
        viewport.update(bounds: bounds, hourHeight: 120)
        let rendered = viewport.visibleMinutes(hourHeight: 44)
        XCTAssertLessThanOrEqual(rendered.lower, Double(bounds.minY / 44) * 60)
        XCTAssertGreaterThanOrEqual(rendered.upper, min(1440, Double(bounds.maxY / 44) * 60))
    }

    func testZoomFromOldBottomToSmallerScaleHasConservativeCoverage() {
        let viewport = CalendarTimelineViewport()
        viewport.update(bounds: CGRect(x: 0, y: 2000, width: 1000, height: 650), hourHeight: 120)
        let transient = viewport.visibleMinutes(hourHeight: 44)
        XCTAssertEqual(transient.lower, 0)
        XCTAssertEqual(transient.upper, 1440)
        let pureBounds = CalendarVisibleMinutes(offset: 2000, viewportHeight: 650, hourHeight: 44)
        XCTAssertGreaterThanOrEqual(pureBounds.lower, 0)
        XCTAssertLessThanOrEqual(pureBounds.lower, pureBounds.upper)
        XCTAssertLessThanOrEqual(pureBounds.upper, 1440)
        viewport.update(bounds: CGRect(x: 0, y: 406, width: 1000, height: 650), hourHeight: 44)
        let final = viewport.visibleMinutes(hourHeight: 44)
        XCTAssertLessThanOrEqual(final.lower, 406.0 / 44 * 60)
        XCTAssertEqual(final.upper, 1440)
    }

    func testPinnedAndLongSpanningCardsRemainRendered() {
        let viewport = CalendarTimelineViewport()
        viewport.update(bounds: CGRect(x: 0, y: 1200, width: 1000, height: 651), hourHeight: 120)
        let rendered = viewport.visibleMinutes(hourHeight: 120)
        let pinned = UUID(), long = UUID()
        XCTAssertTrue(rendered.renders(id: pinned, start: 0, end: 15, movingID: pinned, selectedID: nil))
        XCTAssertTrue(rendered.renders(id: pinned, start: 0, end: 15, movingID: nil, selectedID: pinned))
        XCTAssertTrue(rendered.renders(id: long, start: 0, end: 1440, movingID: nil, selectedID: nil))
        XCTAssertFalse(rendered.renders(id: UUID(), start: 0, end: 15, movingID: nil, selectedID: nil))
    }

}
