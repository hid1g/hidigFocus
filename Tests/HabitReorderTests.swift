import XCTest
@testable import hidigFocus

final class HabitReorderTests: XCTestCase {
    private let ids = (0..<4).map { _ in UUID() }
    private var frames: [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: ids.enumerated().map {
            ($0.element, CGRect(x: 0, y: CGFloat($0.offset) * 81, width: 800, height: 80))
        })
    }

    func testDragFollowsPointerAndOnlyNeighboursMoveBeforeCommit() {
        let session = HabitReorderSession()
        session.update(id: ids[0], order: ids, frames: frames, translation: 92)
        XCTAssertEqual(session.offset(for: ids[0]), 92)
        XCTAssertEqual(session.offset(for: ids[1]), -81)
        XCTAssertEqual(session.offset(for: ids[2]), 0)
        XCTAssertEqual(session.finish()?.target, ids[1])
        XCTAssertNil(session.drag)
    }

    func testLongDragUsesFrozenFramesAndCanReverse() {
        let session = HabitReorderSession()
        session.update(id: ids[0], order: ids, frames: frames, translation: 220)
        XCTAssertEqual(session.drag?.target, ids[3])
        session.update(id: ids[0], order: ids, frames: [:], translation: 48)
        XCTAssertEqual(session.drag?.target, ids[1])
        session.update(id: ids[0], order: ids, frames: [:], translation: 0)
        XCTAssertNil(session.finish())
    }

    func testDragUpClampsToTableAndCancellationDiscardsPreview() {
        let session = HabitReorderSession()
        session.update(id: ids[3], order: ids, frames: frames, translation: -1000)
        XCTAssertEqual(session.offset(for: ids[3]), -243)
        XCTAssertEqual(session.offset(for: ids[0]), 81)
        session.cancel()
        XCTAssertNil(session.finish())
        XCTAssertEqual(session.offset(for: ids[0]), 0)
    }

    func testDifferentRowHeightsShiftNeighboursByDraggedHeight() {
        let session = HabitReorderSession()
        var varied = frames
        varied[ids[0]] = CGRect(x: 0, y: 0, width: 800, height: 110)
        for index in 1..<ids.count { varied[ids[index]]!.origin.y += 30 }
        session.update(id: ids[0], order: ids, frames: varied, translation: 180)
        XCTAssertEqual(session.offset(for: ids[1]), -111)
        XCTAssertEqual(session.offset(for: ids[2]), -111)
    }

    func testMissingFramesDoNotStartDrag() {
        let session = HabitReorderSession()
        session.update(id: ids[0], order: ids, frames: [:], translation: 80)
        XCTAssertNil(session.drag)
    }
}
