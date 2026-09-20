import XCTest
@testable import hidigFocus

final class GoogleCalendarSyncTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 10_000)

    func testCreateUpdateAndDeleteLinkDecisions() {
        var task = ManagedTask(title: "План", startDate: base, modifiedAt: base)
        XCTAssertEqual(GoogleSyncEngine.decision(for: task, remote: nil), .createRemote)

        let remote = event(updatedAt: base, etag: "v1")
        GoogleSyncEngine.markRemoteSaved(remote, on: &task, syncedAt: base)
        XCTAssertEqual(task.googleEventID, "event-1")
        XCTAssertEqual(GoogleSyncEngine.decision(for: task, remote: remote), .unchanged)

        task.modifiedAt = base.addingTimeInterval(20)
        let unchangedRemote = event(updatedAt: base, etag: "v2")
        XCTAssertEqual(GoogleSyncEngine.decision(for: task, remote: unchangedRemote), .updateRemote)

        GoogleSyncEngine.unlink(&task)
        XCTAssertNil(task.googleEventID)
        XCTAssertNil(task.googleCalendarID)
    }

    func testRemoteUpdateAndConflictResolutionAvoidCycles() {
        var task = ManagedTask(
            title: "Локально",
            startDate: base,
            modifiedAt: base,
            googleEventID: "event-1",
            googleCalendarID: "calendar-1",
            googleETag: "v1",
            lastSyncedAt: base
        )
        let remoteWins = event(updatedAt: base.addingTimeInterval(30), etag: "v2")
        XCTAssertEqual(GoogleSyncEngine.decision(for: task, remote: remoteWins), .updateLocal)
        GoogleSyncEngine.applyRemote(remoteWins, to: &task, syncedAt: base.addingTimeInterval(31))
        XCTAssertEqual(task.title, "Удалённо")
        XCTAssertEqual(GoogleSyncEngine.decision(for: task, remote: remoteWins), .unchanged)

        task.title = "Новая локальная"
        task.modifiedAt = base.addingTimeInterval(50)
        let concurrent = event(updatedAt: base.addingTimeInterval(40), etag: "v3")
        XCTAssertEqual(GoogleSyncEngine.decision(for: task, remote: concurrent), .conflictPreferLocal)
    }

    func testRemoteDeletionOnlyUnlinksTask() {
        var task = ManagedTask(
            title: "Не удалять",
            googleEventID: "event-1",
            googleCalendarID: "calendar-1",
            lastSyncedAt: base
        )
        XCTAssertEqual(GoogleSyncEngine.decision(for: task, remote: nil), .unlinkDeletedRemote)
        GoogleSyncEngine.unlink(&task)
        XCTAssertEqual(task.status, .active)
        XCTAssertEqual(task.title, "Не удалять")
    }

    func testAuthorizationOfflineAndExpiredTokenErrorsAreExplicit() {
        XCTAssertEqual(GoogleCalendarError.notAuthorized.errorDescription, "Google Calendar не авторизован.")
        XCTAssertTrue(GoogleCalendarError.offline.errorDescription?.contains("Нет подключения") == true)
        XCTAssertTrue(GoogleCalendarError.tokenExpired.errorDescription?.contains("истекла") == true)
    }

    private func event(updatedAt: Date, etag: String) -> GoogleCalendarEventSnapshot {
        GoogleCalendarEventSnapshot(
            id: "event-1",
            calendarID: "calendar-1",
            etag: etag,
            title: "Удалённо",
            description: "Описание",
            startDate: base,
            endDate: base.addingTimeInterval(3600),
            isAllDay: false,
            timeZoneID: "Europe/Moscow",
            updatedAt: updatedAt
        )
    }
}
