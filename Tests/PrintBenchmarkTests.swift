import XCTest
@testable import hidigFocus

final class PrintBenchmarkTests: XCTestCase {
    func testTwentyRunsAndFiftyThousandTaskStress() throws {
        var state = PlannerFixtures.make(count: 10_000, now: Date(timeIntervalSince1970: 1_793_404_800))
        // Exactly 300 series; all remaining tasks are one-off occurrences.
        for i in state.managedTasks.indices { state.managedTasks[i].repeatRule = i < 300 ? TaskRepeatRule(frequency: .daily) : nil }
        let first = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_793_404_800))
        let end = Calendar.current.date(byAdding: .day, value: 7, to: first)!
        var samples: [[String: Double]] = []
        for run in 0..<20 {
            let index = PlannerCalendarIndex(); index.replaceTasks(state.managedTasks)
            let start = CFAbsoluteTimeGetCurrent(); let day = index.day(first)
            let cold = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let warmStart = CFAbsoluteTimeGetCurrent(); for _ in 0..<20 { _ = index.day(first) }
            let warm = (CFAbsoluteTimeGetCurrent() - warmStart) * 1000 / 20
            let searchStart = CFAbsoluteTimeGetCurrent(); let filter = PlannerFilter()
            let matches = state.managedTasks.filter { filter.matches($0, search: "проверка") }
            let search = (CFAbsoluteTimeGetCurrent() - searchStart) * 1000
            let projectionStart = CFAbsoluteTimeGetCurrent(); let tasks = RecurrenceProjection.tasks(state.managedTasks, from: first, to: end)
            let projection = (CFAbsoluteTimeGetCurrent() - projectionStart) * 1000
            XCTAssertFalse(matches.isEmpty); XCTAssertFalse(tasks.isEmpty)
            withExtendedLifetime(day) {}
            samples.append(["run": Double(run), "coldCalendarMs": cold, "warmCalendarQueryMs": warm, "searchMs": search, "projectionMs": projection])
        }
        if let path = ProcessInfo.processInfo.environment["HIDIGFOCUS_BENCHMARK_OUTPUT"] {
            try JSONSerialization.data(withJSONObject: ["tasks": 10000, "dailySeries": 300, "samples": samples, "scope": "data preparation only; not input latency or FPS"], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path))
        }
        var large = PlannerFixtures.make(count: 50_000, now: first)
        for i in large.managedTasks.indices { large.managedTasks[i].createdAt = first; large.managedTasks[i].modifiedAt = first }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = AppStateRepository(applicationSupportDirectory: directory)
        try repository.save(large)
        let restored = try repository.load()
        XCTAssertEqual(large.managedTasks.map(\.id), restored.managedTasks.map(\.id))
        XCTAssertTrue(large.managedTasks == restored.managedTasks, "Stress snapshot fields must round-trip")
        print("PRINT_STRESS tasks=50000 roundtrip=true")
    }
}
