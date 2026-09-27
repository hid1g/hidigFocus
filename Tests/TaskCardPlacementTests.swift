import XCTest
@testable import hidigFocus

final class TaskCardPlacementTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 1100, height: 720)
    let size = CGSize(width: 400, height: 310)
    func testCardOpensToRightOfLeftTask() {
        let anchor = CGRect(x: 80, y: 180, width: 220, height: 100)
        let frame = TaskCardPlacement.frame(anchor: anchor, bounds: bounds, size: size)
        XCTAssertEqual(frame.minX, anchor.maxX + 12)
        XCTAssertTrue(bounds.contains(frame))
    }
    func testCardOpensToLeftOfRightTask() {
        let anchor = CGRect(x: 850, y: 180, width: 220, height: 100)
        let frame = TaskCardPlacement.frame(anchor: anchor, bounds: bounds, size: size)
        XCTAssertEqual(frame.maxX, anchor.minX - 12)
        XCTAssertTrue(bounds.contains(frame))
    }
    func testEdgesAndExpandedDetailsStayInsideWindow() {
        for point in [CGPoint(x: -200, y: -100), CGPoint(x: 10, y: 700), CGPoint(x: 1090, y: 710)] {
            let frame = TaskCardPlacement.frame(anchor: CGRect(origin: point, size: CGSize(width: 250, height: 120)), bounds: bounds, size: CGSize(width: 400, height: 530))
            XCTAssertTrue(bounds.insetBy(dx: 12, dy: 12).contains(frame))
        }
    }
    func testSmallWindowConstrainsBothDimensions() {
        let small = CGRect(x: 0, y: 0, width: 360, height: 280)
        let frame = TaskCardPlacement.frame(anchor: CGRect(x: 200, y: 250, width: 100, height: 20), bounds: small, size: CGSize(width: 400, height: 530))
        XCTAssertTrue(small.insetBy(dx: 12, dy: 12).contains(frame))
        XCTAssertEqual(frame.size, CGSize(width: 336, height: 256))
    }
}
