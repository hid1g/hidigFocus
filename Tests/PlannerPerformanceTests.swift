import XCTest
@testable import hidigFocus

final class PlannerPerformanceTests: XCTestCase {
    @MainActor func testDisplayFormattingAndTaskLookupCost() throws {
        let state = PlannerFixtures.make(count: 10_000)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        try repository.save(state)
        let store = AppStore(repository: repository, startServices: false)
        let start = CFAbsoluteTimeGetCurrent()
        var characters = 0
        for task in state.managedTasks.prefix(1_000) { characters += task.scheduleLabel.count }
        let formatMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
        let lookupStart = CFAbsoluteTimeGetCurrent()
        for task in state.managedTasks.suffix(1_000) { XCTAssertEqual(store.task(id: task.id)?.id, task.id) }
        let lookupMs = (CFAbsoluteTimeGetCurrent() - lookupStart) * 1000
        XCTAssertGreaterThan(characters, 0)
        print(String(format: "DISPLAY_BENCH labels_1000_ms=%.3f lookup_1000_in_10000_ms=%.3f", formatMs, lookupMs))
        store.flushPendingWrites()
    }

    func testRepresentativeDataSets() throws {
        for count in [100, 1_000, 10_000] {
            let state = PlannerFixtures.make(count: count)
            let first = Calendar.current.startOfDay(for: Date())
            let end = Calendar.current.date(byAdding: .day, value: 7, to: first)!
            let start = CFAbsoluteTimeGetCurrent()
            let tasks = RecurrenceProjection.tasks(state.managedTasks, from: first, to: end)
            let projectMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let index = PlannerCalendarIndex(); index.replaceTasks(state.managedTasks)
            let indexStart = CFAbsoluteTimeGetCurrent(); _ = index.day(first)
            let coldMs = (CFAbsoluteTimeGetCurrent() - indexStart) * 1000
            let warmStart = CFAbsoluteTimeGetCurrent()
            for day in -7..<14 { _ = index.day(Calendar.current.date(byAdding: .day, value: day, to: first)!) }
            let warmMs = (CFAbsoluteTimeGetCurrent() - warmStart) * 1000
            print(String(format: "PLANNER_INDEX tasks=%d cold_ms=%.3f warm_21_days_ms=%.3f", count, coldMs, warmMs))
            let searchStart = CFAbsoluteTimeGetCurrent()
            let filter = PlannerFilter()
            let matches = state.managedTasks.filter { filter.matches($0, search: "проверка") }
            let searchMs = (CFAbsoluteTimeGetCurrent() - searchStart) * 1000
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let repository = AppStateRepository(applicationSupportDirectory: directory)
            let writeStart = CFAbsoluteTimeGetCurrent(); try repository.save(state)
            let saveMs = (CFAbsoluteTimeGetCurrent() - writeStart) * 1000
            XCTAssertEqual(try repository.load().managedTasks.count, count)
            XCTAssertFalse(tasks.isEmpty); XCTAssertFalse(matches.isEmpty)
            print(String(format: "PLANNER_BENCH tasks=%d projection_ms=%.3f search_ms=%.3f save_ms=%.3f visible=%d", count, projectMs, searchMs, saveMs, tasks.count))
        }
    }
}
