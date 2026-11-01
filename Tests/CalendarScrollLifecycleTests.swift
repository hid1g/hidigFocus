import XCTest
import AppKit
@testable import hidigFocus

final class CalendarScrollLifecycleTests: XCTestCase {
    func testLongPauseWhileFingerDownNeverSchedulesSnap() {
        var lifecycle = CalendarScrollLifecycle()
        lifecycle.observe(phase: .began, momentum: [], at: 0)
        lifecycle.observe(phase: .changed, momentum: [], at: 0.1)
        XCTAssertNil(lifecycle.deadline)
        lifecycle.observe(phase: .stationary, momentum: [], at: 10)
        XCTAssertNil(lifecycle.deadline)
        XCTAssertEqual(lifecycle.stream, .gesture)
    }

    func testTouchReleaseDoesNotSettleBeforeMomentumAndStaleDeadlineCannotFinishIt() {
        var lifecycle = CalendarScrollLifecycle()
        lifecycle.observe(phase: .began, momentum: [], at: 0)
        lifecycle.observe(phase: .ended, momentum: [], at: 1)
        let release = try! XCTUnwrap(lifecycle.deadline)
        XCTAssertFalse(lifecycle.finish(release, at: 1.1))
        lifecycle.observe(phase: [], momentum: .began, at: 1.2)
        XCTAssertNil(lifecycle.deadline)
        XCTAssertFalse(lifecycle.finish(release, at: 2))
        lifecycle.observe(phase: [], momentum: .changed, at: 3)
        XCTAssertNil(lifecycle.deadline)
        lifecycle.observe(phase: [], momentum: .ended, at: 4)
        let stop = try! XCTUnwrap(lifecycle.deadline)
        XCTAssertTrue(lifecycle.finish(stop, at: 4))
        XCTAssertFalse(lifecycle.finish(stop, at: 4))
        XCTAssertFalse(lifecycle.isOpen)
    }

    func testNoMomentumReleaseFinishesExactlyOnceAfterGrace() {
        var lifecycle = CalendarScrollLifecycle()
        lifecycle.observe(phase: .ended, momentum: [], at: 7)
        let stop = try! XCTUnwrap(lifecycle.deadline)
        XCTAssertFalse(lifecycle.finish(stop, at: 7.349))
        XCTAssertTrue(lifecycle.finish(stop, at: 7.35))
        XCTAssertFalse(lifecycle.finish(stop, at: 8))
    }

    func testNewGestureInvalidatesPendingReleaseWithoutFinishing() {
        var lifecycle = CalendarScrollLifecycle()
        lifecycle.observe(phase: .ended, momentum: [], at: 0)
        let stale = try! XCTUnwrap(lifecycle.deadline)
        lifecycle.reset()
        lifecycle.observe(phase: .began, momentum: [], at: 0.1)
        XCTAssertFalse(lifecycle.finish(stale, at: 1))
        XCTAssertNil(lifecycle.deadline)
        XCTAssertEqual(lifecycle.stream, .gesture)
    }

    func testPhaseLessWheelWaitsForQuietAndRejectsEarlierTimeout() {
        var lifecycle = CalendarScrollLifecycle()
        lifecycle.observe(phase: [], momentum: [], at: 0)
        let stale = try! XCTUnwrap(lifecycle.deadline)
        lifecycle.observe(phase: [], momentum: [], at: 0.1)
        let stop = try! XCTUnwrap(lifecycle.deadline)
        XCTAssertFalse(lifecycle.finish(stale, at: 1))
        XCTAssertFalse(lifecycle.finish(stop, at: 0.279))
        XCTAssertTrue(lifecycle.finish(stop, at: 0.28))
    }

    func testDisableOrDetachInvalidatesReleaseAndUnphasedTimersWithoutFinishing() {
        for phased in [false, true] {
            var lifecycle = CalendarScrollLifecycle()
            lifecycle.observe(phase: phased ? .ended : [], momentum: [], at: 1)
            let pending = try! XCTUnwrap(lifecycle.deadline)
            lifecycle.reset() // The monitor uses this exact path on disable/detach.
            XCTAssertNil(lifecycle.deadline)
            XCTAssertFalse(lifecycle.isOpen)
            XCTAssertFalse(lifecycle.finish(pending, at: 10))
            lifecycle.observe(phase: .began, momentum: [], at: 11)
            XCTAssertFalse(lifecycle.finish(pending, at: 12))
            XCTAssertEqual(lifecycle.stream, .gesture)
        }
    }

    func testCancellationAndDetachInvalidateAnyPendingCompletion() {
        for momentum in [false, true] {
            var lifecycle = CalendarScrollLifecycle()
            lifecycle.observe(phase: .ended, momentum: [], at: 0)
            let stale = try! XCTUnwrap(lifecycle.deadline)
            XCTAssertTrue(lifecycle.observe(phase: momentum ? [] : .cancelled,
                                            momentum: momentum ? .cancelled : [], at: 0.1))
            XCTAssertFalse(lifecycle.finish(stale, at: 1))
            XCTAssertFalse(lifecycle.isOpen)
            XCTAssertNil(lifecycle.deadline)
        }
    }
}
