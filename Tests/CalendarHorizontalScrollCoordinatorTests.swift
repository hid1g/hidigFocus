import XCTest
import AppKit
@testable import hidigFocus

final class CalendarHorizontalScrollCoordinatorTests: XCTestCase {
    private struct Callback {
        let delta: CGFloat
        let ended: Bool
        let cancelled: Bool
        let momentum: Bool
    }
    private func coordinator(_ callback: @escaping (CGFloat, Bool, Bool, Bool) -> Void) -> CalendarHorizontalScrollCoordinator {
        let value = CalendarHorizontalScrollCoordinator()
        value.setEnabled(true)
        value.onScroll = callback
        return value
    }

    func testHorizontalThenVerticalKeepsAlignmentOwnershipAndAcceptsTerminalOutside() {
        var callbacks: [Callback] = []
        let value = coordinator { callbacks.append(Callback(delta: $0, ended: $1, cancelled: $2, momentum: $3)) }
        value.process(dx: -50, dy: 0, phase: .began, momentum: [], inside: true, at: 0)
        value.process(dx: 0, dy: 0, phase: .ended, momentum: [], inside: true, at: 1)
        let stale = try! XCTUnwrap(value.lifecycle.deadline)
        value.process(dx: 0, dy: 0, phase: .began, momentum: [], inside: true, at: 1.1)
        XCTAssertFalse(value.process(dx: 0, dy: 30, phase: .changed, momentum: [], inside: true, at: 1.2))
        value.finish(stale, at: 2)
        XCTAssertTrue(callbacks.filter(\.ended).isEmpty)
        value.process(dx: 0, dy: 0, phase: .ended, momentum: [], inside: false, at: 2.1)
        value.finish(try! XCTUnwrap(value.lifecycle.deadline), at: 3)
        XCTAssertEqual(callbacks.filter(\.ended).count, 1)
        XCTAssertEqual(callbacks.map(\.delta), [-50, 0])
    }

    func testFreshInputOutsideDoesNotInterruptOrDiscardPendingHorizontalFinish() {
        var ends = 0
        var begins = 0
        let value = coordinator { _, ended, _, _ in if ended { ends += 1 } }
        value.onBegin = { begins += 1; return false }
        value.process(dx: -50, dy: 0, phase: .began, momentum: [], inside: true, at: 0)
        value.process(dx: 0, dy: 0, phase: .ended, momentum: [], inside: true, at: 1)
        let deadline = try! XCTUnwrap(value.lifecycle.deadline)
        XCTAssertFalse(value.process(dx: 0, dy: 0, phase: .began, momentum: [], inside: false, at: 1.1))
        XCTAssertEqual(begins, 1)
        XCTAssertEqual(value.lifecycle.deadline, deadline)
        value.finish(deadline, at: 2)
        XCTAssertEqual(ends, 1)
    }

    func testFreshZeroDeltaInputInterruptsOngoingSettleAtVisibleSample() {
        let pan = CalendarPanState()
        var oldCompletion = false
        pan.animate(to: -200, reduceMotion: false) { oldCompletion = true }
        pan.recordPresentation(-75, token: pan.presentationToken)
        var ends = 0
        let value = coordinator { _, ended, _, _ in if ended { ends += 1 } }
        value.onBegin = { pan.beginInput(momentum: false, newGesture: true); return abs(pan.visibleOffset) > 0.1 }
        value.process(dx: 0, dy: 0, phase: .began, momentum: [], inside: true, at: 0)
        XCTAssertFalse(pan.isAnimating)
        XCTAssertEqual(pan.offset, -75)
        XCTAssertFalse(oldCompletion)
        value.process(dx: 0, dy: 20, phase: .changed, momentum: [], inside: true, at: 1)
        XCTAssertNil(value.lifecycle.deadline)
        value.process(dx: 0, dy: 0, phase: .ended, momentum: [], inside: false, at: 2)
        value.finish(try! XCTUnwrap(value.lifecycle.deadline), at: 3)
        XCTAssertEqual(ends, 1)
    }

    func testZeroOffsetNavigationStillFinishesOwnedCleanupAfterNewInput() {
        var lockedAllDayHeight: CGFloat? = 36
        var ends = 0
        let value = coordinator { _, ended, _, _ in
            if ended { ends += 1; lockedAllDayHeight = nil }
        }
        value.onBegin = { lockedAllDayHeight != nil }
        value.process(dx: 0, dy: 0, phase: .began, momentum: [], inside: true, at: 0)
        value.process(dx: 0, dy: 20, phase: .changed, momentum: [], inside: true, at: 1)
        XCTAssertNotNil(lockedAllDayHeight)
        XCTAssertNil(value.lifecycle.deadline)
        value.process(dx: 0, dy: 0, phase: .ended, momentum: [], inside: true, at: 2)
        value.finish(try! XCTUnwrap(value.lifecycle.deadline), at: 3)
        XCTAssertEqual(ends, 1)
        XCTAssertNil(lockedAllDayHeight)
    }

    func testMomentumConsumesEveryDeltaOnceAndOnlyTerminalSchedulesFinish() {
        var callbacks: [Callback] = []
        let value = coordinator { callbacks.append(Callback(delta: $0, ended: $1, cancelled: $2, momentum: $3)) }
        value.process(dx: -80, dy: 0, phase: .began, momentum: [], inside: true, at: 0)
        value.process(dx: -10, dy: 0, phase: .ended, momentum: [], inside: true, at: 1)
        let stale = try! XCTUnwrap(value.lifecycle.deadline)
        value.process(dx: -70, dy: 0, phase: [], momentum: .began, inside: false, at: 1.1)
        value.process(dx: -250, dy: 0, phase: [], momentum: .changed, inside: false, at: 4)
        XCTAssertNil(value.lifecycle.deadline)
        value.finish(stale, at: 5)
        XCTAssertTrue(callbacks.filter(\.ended).isEmpty)
        value.process(dx: -2, dy: 0, phase: [], momentum: .ended, inside: false, at: 6)
        let final = try! XCTUnwrap(value.lifecycle.deadline)
        value.finish(final, at: 6)
        value.finish(final, at: 7)
        XCTAssertEqual(callbacks.reduce(CGFloat.zero) { $0 + $1.delta }, -412)
        XCTAssertEqual(callbacks.filter(\.ended).count, 1)
        XCTAssertEqual(callbacks.filter { $0.momentum }.map(\.delta), [-70, -250, -2])
    }

    func testDisableAndDetachCannotDeliverOldFinishAfterReenable() {
        for detach in [false, true] {
            var ends = 0
            let value = coordinator { _, ended, _, _ in if ended { ends += 1 } }
            value.process(dx: -50, dy: 0, phase: .began, momentum: [], inside: true, at: 0)
            value.process(dx: 0, dy: 0, phase: .ended, momentum: [], inside: true, at: 1)
            let stale = try! XCTUnwrap(value.lifecycle.deadline)
            if detach { value.detach() } else { value.setEnabled(false) }
            value.finish(stale, at: 2)
            value.setEnabled(true)
            value.finish(stale, at: 3)
            XCTAssertEqual(ends, 0)
            XCTAssertFalse(value.needsHorizontalFinish)
        }
    }

    func testReversalKeepsAccumulatedDisplacementWithoutIntermediateSnap() {
        var displacement: CGFloat = 0
        var ends = 0
        let value = coordinator { delta, ended, _, _ in displacement += delta; if ended { ends += 1 } }
        value.process(dx: -600, dy: 0, phase: .began, momentum: [], inside: true, at: 0)
        value.process(dx: 0, dy: 0, phase: .ended, momentum: [], inside: true, at: 1)
        value.process(dx: 0, dy: 0, phase: .began, momentum: [], inside: true, at: 1.1)
        value.process(dx: 125, dy: 0, phase: .changed, momentum: [], inside: true, at: 1.2)
        XCTAssertEqual(displacement, -475)
        XCTAssertEqual(ends, 0)
        value.process(dx: 0, dy: 0, phase: .ended, momentum: [], inside: true, at: 2)
        value.finish(try! XCTUnwrap(value.lifecycle.deadline), at: 3)
        XCTAssertEqual(ends, 1)
        XCTAssertEqual(displacement, -475)
    }
}
