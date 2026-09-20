import XCTest
@testable import hidigFocus

final class TickTickLiveImportTests: XCTestCase {
    func testLiveImportWhenExplicitlyEnabled() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HIDIGFOCUS_RUN_LIVE_IMPORT"] == "1")
        let service = TickTickCLIService()
        let start = Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date()
        let snapshot = try await service.fullImportSnapshot(since: start)
        let repository = AppStateRepository()
        var state = try repository.load()
        let before = state.managedTasks.count
        let report = TaskEngine.importTickTick(
            folders: snapshot.folders,
            lists: snapshot.lists,
            records: snapshot.records,
            into: &state
        )
        XCTAssertEqual(state.managedTasks.count, before + report.imported)
        XCTAssertEqual(Set(state.managedTasks.compactMap(\.sourceID)).count, state.managedTasks.compactMap(\.sourceID).count)
        // Live verification must never replace the running application's database.
        print("TICKTICK_IMPORT_DRY_RUN lists=\(snapshot.preview.lists) active=\(snapshot.preview.activeTasks) completed=\(snapshot.preview.completedTasks) imported=\(report.imported) updated=\(report.updated) skipped=\(report.skipped) failed=\(report.failed)")
    }
}
