import XCTest
import Combine
@testable import hidigFocus

final class CalendarMotionTests: XCTestCase {
    func testInterruptedMotionStartsAtVisibleSampleAndNeverCallsOldCompletion() {
        let pan = CalendarPanState()
        var completed = false
        pan.animate(to: -400, reduceMotion: false, duration: 0.4, at: 10) { completed = true }
        // Deliberately sample before the end: the old implementation exposed its
        // target immediately and would jump to -400 on interruption.
        pan.recordPresentation(-375, token: pan.presentationToken)
        pan.interrupt()
        XCTAssertEqual(pan.offset, -375, accuracy: 0.0001)
        XCTAssertFalse(completed)
        XCTAssertEqual(pan.phase, .idle)
        pan.beginInput(momentum: true)
        XCTAssertEqual(pan.phase, .decelerating)
        pan.beginInput(momentum: false)
        XCTAssertEqual(pan.phase, .dragging)
        pan.animate(to: 200, reduceMotion: true) { completed = true }
        XCTAssertEqual(pan.offset, 200)
        XCTAssertTrue(completed)
        XCTAssertEqual(pan.phase, .idle)
    }

    func testPresentationCompletionRejectsStaleTokensAndDoesNotCompleteAtConstruction() {
        let pan = CalendarPanState()
        var completions = 0
        pan.animate(to: -400, reduceMotion: false) { completions += 1 }
        let first = pan.presentationToken
        XCTAssertEqual(completions, 0)
        pan.finishPresentation(token: first)
        XCTAssertEqual(completions, 0)
        pan.recordPresentation(-200, token: first)
        XCTAssertEqual(completions, 0)
        pan.interrupt()
        XCTAssertEqual(pan.offset, -200)
        pan.animate(to: 200, reduceMotion: false) { completions += 1 }
        let second = pan.presentationToken
        pan.recordPresentation(-400, token: first)
        pan.finishPresentation(token: first)
        XCTAssertEqual(completions, 0)
        XCTAssertEqual(pan.visibleOffset, -200)
        pan.recordPresentation(200, token: second)
        pan.finishPresentation(token: second)
        pan.finishPresentation(token: second)
        XCTAssertEqual(completions, 1)
        XCTAssertEqual(pan.phase, .idle)
    }

    func testInterpolationSamplesDoNotPublishObservableChanges() {
        let pan = CalendarPanState()
        pan.animate(to: -400, reduceMotion: false)
        let token = pan.presentationToken
        var changes = 0
        let observation = pan.objectWillChange.sink { changes += 1 }
        var modifier = CalendarObservedOffset(value: -400, leading: 100, pan: pan, token: token)
        XCTAssertEqual(pan.visibleOffset, 0)
        for offset in 1...399 { modifier.animatableData = -CGFloat(offset) }
        XCTAssertEqual(pan.visibleOffset, -399)
        XCTAssertEqual(changes, 0)
        pan.interrupt()
        XCTAssertEqual(pan.offset, -399)
        withExtendedLifetime(observation) {}
    }

    func testResizePreservesFractionalDayAndAnimationCompletion() {
        let pan = CalendarPanState()
        pan.dayWidth = 200; pan.offset = -100
        pan.resizeDayWidth(to: 400)
        XCTAssertEqual(pan.offset, -200)
        var completions = 0
        pan.animate(to: -400, reduceMotion: false, duration: 0.4, at: 10) { completions += 1 }
        pan.resizeDayWidth(to: 100, at: 10.1)
        pan.completeImmediately()
        XCTAssertEqual(pan.offset, -100)
        XCTAssertEqual(completions, 1)
        pan.completeImmediately()
        XCTAssertEqual(completions, 1)
    }

    func testButtonQueueCanBeUsedImmediatelyAfterSwipeInterruptsAnimation() {
        var queue = CalendarNavigationQueue()
        XCTAssertFalse(queue.enqueueIfBusy(1))
        queue.start()
        XCTAssertTrue(queue.enqueueIfBusy(1))
        XCTAssertTrue(queue.enqueueIfBusy(-1))
        XCTAssertTrue(queue.enqueueIfBusy(1))
        XCTAssertEqual(queue.pending, 1)
        queue.cancel()
        XCTAssertEqual(queue.pending, 0)
        XCTAssertFalse(queue.inFlight)
        XCTAssertFalse(queue.enqueueIfBusy(-1))
        queue.start(); _ = queue.enqueueIfBusy(-1); queue.finish()
        XCTAssertEqual(queue.next(), -1)
        XCTAssertNil(queue.next())
    }

    func testZoomCommitsOnlyOnceAndRestartsFromTheLastPreference() {
        var zoom = CalendarZoomSession()
        for scale in [1.1, 0.9, 1.25] { zoom.update(magnification: scale, persisted: 80) }
        XCTAssertEqual(zoom.preview, 100)
        XCTAssertEqual(zoom.finish(), 100)
        XCTAssertNil(zoom.finish())
        zoom.update(magnification: 0.5, persisted: 100)
        XCTAssertEqual(zoom.finish(), 50)
        zoom.update(magnification: .nan, persisted: 100)
        XCTAssertNil(zoom.finish())
    }

    func testZoomKeepsMinuteUnderPointerAndClampsAtDayBounds() {
        let anchor = CalendarZoomAnchor(contentOffset: 480, localY: 120, hourHeight: 80)
        XCTAssertEqual(anchor.minute, 450)
        XCTAssertEqual(anchor.contentOffset(hourHeight: 120, viewportHeight: 600), 780)
        XCTAssertEqual(anchor.contentOffset(hourHeight: 44, viewportHeight: 600), 210)
        let bottom = CalendarZoomAnchor(contentOffset: 1600, localY: 400, hourHeight: 96)
        XCTAssertEqual(bottom.contentOffset(hourHeight: 44, viewportHeight: 600), 456)
    }

    func testAutoscrollDistanceIsIndependentOfRefreshRateAndStallsAreBounded() {
        func distance(fps: Int) -> CGFloat {
            (0..<fps).reduce(0) { sum, _ in sum + CalendarAutoscrollMotion.delta(pointer: 0, extent: 600, elapsed: 1 / Double(fps)) }
        }
        XCTAssertEqual(distance(fps: 30), -480, accuracy: 0.001)
        XCTAssertEqual(distance(fps: 60), distance(fps: 120), accuracy: 0.001)
        XCTAssertEqual(CalendarAutoscrollMotion.delta(pointer: 20, extent: 600, elapsed: 1 / 60), -4)
        XCTAssertEqual(CalendarAutoscrollMotion.delta(pointer: 300, extent: 600, elapsed: 1), 0)
        XCTAssertEqual(CalendarAutoscrollMotion.delta(pointer: 600, extent: 600, elapsed: 5), 24)
    }

    func testAxisDecisionPreservesSmallDeltasAndMomentumReversal() {
        var axis = CalendarAxisLock()
        XCTAssertFalse(axis.accept(dx: 1, dy: 0.1))
        XCTAssertFalse(axis.accept(dx: 1, dy: 0.1))
        XCTAssertTrue(axis.accept(dx: 1, dy: 0.1))
        XCTAssertEqual(axis.horizontalDelta, 3)
        XCTAssertTrue(axis.accept(dx: -15, dy: 30))
        XCTAssertEqual(axis.horizontalDelta, -15)
        axis.reset()
        XCTAssertFalse(axis.accept(dx: 1, dy: 8))
        XCTAssertFalse(axis.accept(dx: 100, dy: 0))
    }
}
