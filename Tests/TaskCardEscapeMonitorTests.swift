import AppKit
import XCTest
@testable import hidigFocus

final class TaskCardEscapeMonitorTests: XCTestCase {
    @MainActor func testPendingModalKeepsEditorOpenForPointerAndFirstEscape() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 400), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = NSView(frame: CGRect(x: 50, y: 50, width: 150, height: 150))
        window.contentView?.addSubview(editor)
        let coordinator = TaskCardEscapeMonitor.Coordinator()
        coordinator.view = editor
        var modal = true, editorDismissals = 0, modalDismissals = 0
        coordinator.shouldDismissOnPointer = { !modal }
        coordinator.dismiss = {
            if modal { modal = false; modalDismissals += 1 }
            else { editorDismissals += 1 }
        }
        let click = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 300, y: 300), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        XCTAssertNotNil(coordinator.handle(click))
        XCTAssertTrue(modal)
        XCTAssertEqual(editorDismissals, 0)
        let escape = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53))
        XCTAssertNil(coordinator.handle(escape))
        XCTAssertFalse(modal)
        XCTAssertEqual(modalDismissals, 1)
        XCTAssertEqual(editorDismissals, 0)
        XCTAssertNil(coordinator.handle(escape))
        XCTAssertEqual(editorDismissals, 1)
    }

    @MainActor func testPointerDismissalUsesCurrentModalStateAndKeepsInsideClicks() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 400), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let editor = NSView(frame: CGRect(x: 50, y: 50, width: 150, height: 150))
        window.contentView?.addSubview(editor)
        let coordinator = TaskCardEscapeMonitor.Coordinator()
        coordinator.view = editor
        var modal = false, dismissals = 0
        coordinator.shouldDismissOnPointer = { !modal }
        coordinator.dismiss = { dismissals += 1 }
        func click(_ point: CGPoint) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        }
        _ = coordinator.handle(try click(CGPoint(x: 70, y: 70)))
        XCTAssertEqual(dismissals, 0)
        _ = coordinator.handle(try click(CGPoint(x: 300, y: 300)))
        XCTAssertEqual(dismissals, 1)
        modal = true
        _ = coordinator.handle(try click(CGPoint(x: 300, y: 300)))
        XCTAssertEqual(dismissals, 1, "A newly presented modal must protect the editor without rebuilding the monitor")
    }
}
