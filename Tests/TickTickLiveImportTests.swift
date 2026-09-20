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
        let backup = try repository.createBackup(label: "before-ticktick-live-import")
        let report = TaskEngine.importTickTick(
            folders: snapshot.folders,
            lists: snapshot.lists,
            records: snapshot.records,
            into: &state
        )
        try repository.save(state)
        XCTAssertEqual(state.managedTasks.count, before + report.imported)
        XCTAssertEqual(Set(state.managedTasks.compactMap(\.sourceID)).count, state.managedTasks.compactMap(\.sourceID).count)
        let backupName = backup?.lastPathComponent ?? "none"
        print("TICKTICK_IMPORT lists=\(snapshot.preview.lists) active=\(snapshot.preview.activeTasks) completed=\(snapshot.preview.completedTasks) imported=\(report.imported) skipped=\(report.skipped) failed=\(report.failed) backup=\(backupName)")
    }
}
