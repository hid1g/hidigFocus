import XCTest
@testable import hidigFocus

final class ResourceProtectionTests: XCTestCase {
    @MainActor private func makeStore(legacyDraft: Bool = false, disabledDraft: Bool = false) throws -> (AppStore, URL, UUID, UUID) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let resource = BlockedResource(kind: .domain, displayName: "Video", identifier: "video.example")
        let group = BlockGroup(name: "Sites", resources: [resource])
        var state = PersistedAppState()
        state.groups = [group, BlockGroup.draft(name: "Other")]
        state.disciplineStreak = 17
        state.disciplineLastCountedDayKey = DayKey.make(from: Date())
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        state.habits = [Habit(name: "Habit", checkInDayKeys: [DayKey.make(from: Date()), DayKey.make(from: yesterday)])]
        if legacyDraft {
            var draft = group; draft.resources[0].identifier = "different.example"
            state.pendingGroupRules = [group.id: draft]
        }
        if disabledDraft {
            var draft = group; draft.isEnabled = false
            state.pendingGroupRules = [group.id: draft]
        }
        let repository = AppStateRepository(applicationSupportDirectory: dir)
        try repository.save(state)
        return (AppStore(repository: repository, startServices: false), dir, group.id, resource.id)
    }
    @MainActor func testEditRequiresConfirmationAndCancelPreservesSeries() throws {
        let (store, dir, groupID, resourceID) = try makeStore()
        defer { store.flushPendingWrites(); try? FileManager.default.removeItem(at: dir) }
        try store.updateResource(resourceID, in: groupID, displayName: "Video", identifier: "different.example")
        XCTAssertNotNil(store.pendingProtectedResourceChange)
        XCTAssertEqual(store.state.groups[0].resources[0].identifier, "video.example")
        XCTAssertEqual(store.disciplineStreak, 17)
        XCTAssertFalse(try store.confirmProtectedResourceChange("wrong"))
        store.pendingProtectedResourceChange = nil
        XCTAssertEqual(store.state.groups[0].resources[0].identifier, "video.example")
        try store.updateResource(resourceID, in: groupID, displayName: "Video", identifier: "different.example")
        XCTAssertTrue(try store.confirmProtectedResourceChange("ПОДТВЕРДИТЬ"))
        XCTAssertEqual(store.state.groups[0].resources[0].identifier, "different.example")
        XCTAssertEqual(store.disciplineStreak, 0)
        XCTAssertTrue(store.protectionEnabled)
        XCTAssertEqual(store.state.habits[0].currentStreak(), 0)
        XCTAssertEqual(store.state.habits[0].checkInDayKeys.count, 1)
        store.flushPendingWrites()
        let saved = try AppStateRepository(applicationSupportDirectory: dir).load()
        XCTAssertEqual(saved.groups[0].resources[0].identifier, "different.example")
        XCTAssertEqual(saved.disciplineStreak, 0)
    }
    @MainActor func testAddAndRenameDoNotResetButDeletionDoes() throws {
        let (store, dir, groupID, resourceID) = try makeStore()
        defer { store.flushPendingWrites(); try? FileManager.default.removeItem(at: dir) }
        store.addGroup(named: "New")
        try store.addDomain("new.example", displayName: "New", to: groupID)
        store.applyGroupRule(groupID)
        try store.updateResource(resourceID, in: groupID, displayName: "Renamed", identifier: "https://VIDEO.EXAMPLE/")
        XCTAssertNil(store.pendingProtectedResourceChange)
        XCTAssertEqual(store.disciplineStreak, 17)
        store.removeResource(resourceID, from: groupID)
        XCTAssertEqual(store.state.groups[0].resources.count, 2)
        XCTAssertTrue(try store.confirmProtectedResourceChange("ПОДТВЕРДИТЬ"))
        XCTAssertFalse(store.state.groups[0].resources.contains { $0.id == resourceID })
        XCTAssertFalse(store.groups[0].resources.contains { $0.id == resourceID })
        XCTAssertEqual(store.disciplineStreak, 0)
    }
    @MainActor func testGroupDeletionCannotBypassConfirmation() throws {
        let (store, dir, groupID, _) = try makeStore()
        defer { store.flushPendingWrites(); try? FileManager.default.removeItem(at: dir) }
        store.removeGroup(groupID)
        XCTAssertEqual(store.state.groups.count, 2)
        XCTAssertEqual(store.disciplineStreak, 17)
        XCTAssertTrue(try store.confirmProtectedResourceChange("ПОДТВЕРДИТЬ"))
        XCTAssertEqual(store.state.groups.count, 1)
        XCTAssertEqual(store.disciplineStreak, 0)
        XCTAssertTrue(store.protectionEnabled)
    }
    @MainActor func testLegacyDraftCannotBypassConfirmation() throws {
        let (store, dir, groupID, _) = try makeStore(legacyDraft: true)
        defer { store.flushPendingWrites(); try? FileManager.default.removeItem(at: dir) }
        store.applyGroupRule(groupID)
        XCTAssertEqual(store.state.groups[0].resources[0].identifier, "video.example")
        XCTAssertEqual(store.disciplineStreak, 17)
        XCTAssertTrue(try store.confirmProtectedResourceChange("ПОДТВЕРДИТЬ"))
        XCTAssertEqual(store.state.groups[0].resources[0].identifier, "different.example")
        XCTAssertEqual(store.disciplineStreak, 0)
    }
    @MainActor func testAccessIndicatorUsesAppliedRuleUntilDraftIsApplied() throws {
        let (store, dir, groupID, _) = try makeStore(disabledDraft: true)
        defer { store.flushPendingWrites(); try? FileManager.default.removeItem(at: dir) }
        let draft = try XCTUnwrap(store.groups.first { $0.id == groupID })
        XCTAssertTrue(store.groupIsUnlocked(draft))
        XCTAssertFalse(store.groupIsUnlocked(try XCTUnwrap(store.appliedGroup(groupID))))
        XCTAssertTrue(store.groupStatusExplanation(groupID).hasPrefix("Закрыта"))
        XCTAssertEqual(store.disciplineStreak, 17)
        store.applyGroupRule(groupID)
        XCTAssertTrue(store.groupIsUnlocked(try XCTUnwrap(store.appliedGroup(groupID))))
        XCTAssertEqual(store.disciplineStreak, 17)
    }
}
