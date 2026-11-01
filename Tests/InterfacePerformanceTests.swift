import XCTest
@testable import hidigFocus

final class InterfacePerformanceTests: XCTestCase {
    func testCalendarRenderingHotPathCost() {
        let started = CFAbsoluteTimeGetCurrent()
        var checksum: CGFloat = 0
        for i in 0..<25_000 {
            let layout = CalendarCardLayout(height: CGFloat([24, 36, 54, 72, 90, 120][i % 6]),
                width: CGFloat([90, 180, 300][i % 3]), scale: 1, font: .system, hasPriority: i % 2 == 0)
            checksum += layout.requiredHeight
        }
        XCTAssertGreaterThan(checksum, 0)
        print(String(format: "UI_RENDER_BENCH calendar_layout_25000_ms=%.3f checksum=%.0f", (CFAbsoluteTimeGetCurrent() - started) * 1000, checksum))
    }
    @MainActor func testCachedTaskQueriesStayFreshThroughEditsStatusFilterTrashAndUndo() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "hidigFocus.performance.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: directory),
            startServices: false, plannerDefaults: defaults)
        defer { store.flushPendingWrites() }
        store.taskSidebarSelection = .all
        store.planner.filter.showCompleted = false
        let id = try XCTUnwrap(store.addManagedTask(named: "Первое название"))
        XCTAssertTrue(store.visibleManagedTasks.contains { $0.id == id })
        var task = try XCTUnwrap(store.task(id: id))
        task.title = "Новое название"
        store.updateManagedTask(task)
        XCTAssertEqual(store.visibleManagedTasks.first { $0.id == id }?.title, "Новое название")
        store.setManagedTaskCompleted(id, completed: true)
        XCTAssertFalse(store.visibleManagedTasks.contains { $0.id == id })
        store.planner.filter.showCompleted = true
        XCTAssertEqual(store.visibleManagedTasks.first { $0.id == id }?.status, .completed)
        store.undoTaskAction()
        XCTAssertEqual(store.visibleManagedTasks.first { $0.id == id }?.status, .active)
        store.trashManagedTask(id)
        XCTAssertFalse(store.visibleManagedTasks.contains { $0.id == id })
        store.taskSidebarSelection = .trash
        XCTAssertEqual(store.visibleManagedTasks.first { $0.id == id }?.status, .trashed)
        store.restoreManagedTask(id)
        XCTAssertFalse(store.visibleManagedTasks.contains { $0.id == id })
        store.taskSidebarSelection = .all
        XCTAssertEqual(store.visibleManagedTasks.first { $0.id == id }?.status, .active)
    }

    func testCalendarViewportKeepsVisibleSpanningMovingAndSelectedTasks() {
        let visible = CalendarVisibleMinutes(offset: 720, viewportHeight: 480, hourHeight: 120)
        let id = UUID()
        XCTAssertTrue(visible.renders(id: id, start: 390, end: 435, movingID: nil, selectedID: nil))
        XCTAssertTrue(visible.renders(id: id, start: 0, end: 1440, movingID: nil, selectedID: nil))
        XCTAssertFalse(visible.renders(id: id, start: 1080, end: 1140, movingID: nil, selectedID: nil))
        XCTAssertTrue(visible.renders(id: id, start: 1080, end: 1140, movingID: id, selectedID: nil))
        XCTAssertTrue(visible.renders(id: id, start: 1080, end: 1140, movingID: nil, selectedID: id))
        for hourHeight: CGFloat in [48, 72, 96, 120, 180] {
            for hour in 0..<24 {
                let window = CalendarVisibleMinutes(offset: CGFloat(hour) * hourHeight, viewportHeight: 480, hourHeight: hourHeight)
                XCTAssertTrue(window.renders(id: id, start: Double(hour * 60), end: Double(hour * 60 + 15), movingID: nil, selectedID: nil))
            }
        }
    }

    func testCalendarViewportDoesNotPublishForEveryScrollPixel() {
        let viewport = CalendarTimelineViewport()
        viewport.update(bounds: CGRect(x: 0, y: 725, width: 700, height: 480), hourHeight: 120)
        let revision = viewport.revision
        viewport.update(bounds: CGRect(x: 0, y: 726, width: 700, height: 480), hourHeight: 120)
        XCTAssertEqual(viewport.revision, revision)
        viewport.update(bounds: CGRect(x: 0, y: 850, width: 700, height: 480), hourHeight: 120)
        XCTAssertEqual(viewport.revision, revision, "The retained overscan still covers this scroll")
        let retained = viewport.visibleMinutes(hourHeight: 120)
        XCTAssertLessThanOrEqual(retained.lower, 425)
        XCTAssertGreaterThanOrEqual(retained.upper, 665)
        viewport.update(bounds: CGRect(x: 0, y: 1800, width: 700, height: 480), hourHeight: 120)
        XCTAssertGreaterThan(viewport.revision, revision)
        let jumped = viewport.visibleMinutes(hourHeight: 120)
        XCTAssertLessThanOrEqual(jumped.lower, 900)
        XCTAssertGreaterThanOrEqual(jumped.upper, 1140)
    }

}
