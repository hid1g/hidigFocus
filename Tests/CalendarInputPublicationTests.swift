import XCTest
import Combine
import AppKit
@testable import hidigFocus

final class CalendarInputPublicationTests: XCTestCase {
    func testOrdinaryInputPreservesEveryDeltaWithOnePublicationPerChange() {
        let pan = CalendarPanState()
        pan.beginInput(momentum: false, newGesture: true)
        let token = pan.presentationToken
        var changes = 0
        let observation = pan.objectWillChange.sink { changes += 1 }
        let deltas: [CGFloat] = (0..<120).map { $0 < 80 ? -3 : 2 }
        for delta in deltas {
            pan.beginInput(momentum: false)
            pan.offset += delta
        }
        XCTAssertEqual(pan.offset, deltas.reduce(0, +))
        XCTAssertEqual(pan.phase, .dragging)
        XCTAssertEqual(pan.presentationToken, token)
        XCTAssertEqual(changes, deltas.count)
        withExtendedLifetime(observation) {}
    }

    func testMomentumTransitionChangesPhaseOnceWithoutResamplingOffset() {
        let pan = CalendarPanState()
        pan.beginInput(momentum: false, newGesture: true)
        pan.offset = -120
        let token = pan.presentationToken
        var changes = 0
        let observation = pan.objectWillChange.sink { changes += 1 }
        pan.beginInput(momentum: true)
        XCTAssertEqual(pan.phase, .decelerating)
        XCTAssertEqual(pan.offset, -120)
        XCTAssertEqual(pan.visibleOffset, -120)
        XCTAssertEqual(pan.presentationToken, token)
        XCTAssertEqual(changes, 1)
        for _ in 0..<30 { pan.beginInput(momentum: true) }
        XCTAssertEqual(changes, 1)
        pan.offset += 25
        XCTAssertEqual(pan.offset, -95)
        XCTAssertEqual(changes, 2)
        withExtendedLifetime(observation) {}
    }

    func testExplicitNewStreamWhileDraggingInvalidatesOldTokenWithoutMoving() {
        let pan = CalendarPanState()
        pan.beginInput(momentum: false, newGesture: true)
        pan.offset = -85
        let previousToken = pan.presentationToken
        pan.beginInput(momentum: false, newGesture: true)
        XCTAssertGreaterThan(pan.presentationToken, previousToken)
        XCTAssertEqual(pan.offset, -85)
        XCTAssertEqual(pan.visibleOffset, -85)
        XCTAssertEqual(pan.phase, .dragging)
        pan.recordPresentation(-400, token: previousToken)
        pan.finishPresentation(token: previousToken)
        XCTAssertEqual(pan.visibleOffset, -85)
    }

    func testInputInterruptsSettleAtVisibleSampleAndRejectsOldCompletion() {
        let pan = CalendarPanState()
        var oldCompletion = false
        pan.animate(to: -400, reduceMotion: false, duration: 0.4, at: 10) { oldCompletion = true }
        let token = pan.presentationToken
        pan.recordPresentation(-125, token: token)
        // Ordinary input remains safe even if a caller did not emit onBegin.
        pan.beginInput(momentum: true)
        XCTAssertEqual(pan.offset, -125)
        XCTAssertEqual(pan.phase, .decelerating)
        XCTAssertGreaterThan(pan.presentationToken, token)
        pan.recordPresentation(-400, token: token)
        pan.finishPresentation(token: token)
        XCTAssertEqual(pan.visibleOffset, -125)
        XCTAssertFalse(oldCompletion)
        var newCompletion = false
        pan.animate(to: 0, reduceMotion: true) { newCompletion = true }
        XCTAssertTrue(newCompletion)
        XCTAssertFalse(oldCompletion)
    }
}
