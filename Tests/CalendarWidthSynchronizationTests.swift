import XCTest
import AppKit
@testable import hidigFocus

final class CalendarWidthSynchronizationTests: XCTestCase {
    func testRebasePreservesFixedDatePixelsAfterRestoreAndRepeatedResizes() {
        let pan = CalendarPanState()
        pan.dayWidth = 189.75
        pan.offset = -73

        for renderedWidth: CGFloat in [372.25, 244.75, 138.0, 972.0 / 7.0, 40.0, 372.25] {
            let fractionBeforeResize = pan.offset / pan.dayWidth
            pan.resizeDayWidth(to: renderedWidth)
            XCTAssertEqual(pan.dayWidth, renderedWidth)
            XCTAssertEqual(pan.offset / renderedWidth, fractionBeforeResize, accuracy: 0.000001)

            for delta in [-0.65, -2.4, 0.8, 6.25].map({ CGFloat($0) * renderedWidth }) {
                let requestedOffset = pan.offset + delta
                let result = CalendarNavigation.rebasedSwipe(offset: requestedOffset, dayWidth: pan.dayWidth)
                // A fixed date moves left by one rendered column when the date
                // origin advances. Changing the origin must preserve its pixels.
                let sameDateAfterRebase = -CGFloat(result.dayShift) * renderedWidth + result.remainingOffset
                XCTAssertEqual(sameDateAfterRebase, requestedOffset, accuracy: 0.000001)
                pan.offset = result.remainingOffset
            }
        }
    }

    func testResizingInterruptedSettlePreservesVisibleFractionAndDestination() {
        let pan = CalendarPanState()
        let previousWidth: CGFloat = 189.75
        let renderedWidth: CGFloat = 372.25
        pan.dayWidth = previousWidth
        pan.animate(to: -4 * previousWidth, reduceMotion: false, duration: 1, at: 10)
        pan.recordPresentation(-1.4 * previousWidth, token: pan.presentationToken)

        pan.resizeDayWidth(to: renderedWidth, at: 10.25)
        XCTAssertEqual(pan.dayWidth, renderedWidth)
        XCTAssertEqual(pan.offset, -4 * renderedWidth, accuracy: 0.000001)
        XCTAssertEqual(pan.visibleOffset, -1.4 * renderedWidth, accuracy: 0.000001)

        pan.beginInput(momentum: false)
        XCTAssertEqual(pan.offset, -1.4 * renderedWidth, accuracy: 0.000001)
        let result = CalendarNavigation.rebasedSwipe(offset: pan.offset, dayWidth: pan.dayWidth)
        XCTAssertEqual(-CGFloat(result.dayShift) * renderedWidth + result.remainingOffset,
                       pan.offset, accuracy: 0.000001)
    }
}
