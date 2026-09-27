import XCTest
@testable import hidigFocus

final class FocusTests: XCTestCase {
    @MainActor func testDurationPresetsCustomPersistenceAndActiveSessionProtection() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let repository = AppStateRepository(applicationSupportDirectory: dir)
        let store = AppStore(repository: repository, startServices: false)
        for (work, rest) in [(25, 5), (30, 5), (45, 10), (50, 10), (60, 15), (37, 8)] {
            XCTAssertTrue(store.setFocusDurations(workMinutes: work, breakMinutes: rest))
            store.startFocus()
            XCTAssertEqual(store.activePomodoro?.targetSeconds, work * 60)
            XCTAssertFalse(store.setFocusDurations(workMinutes: 20, breakMinutes: 4))
            XCTAssertEqual(store.activePomodoro?.targetSeconds, work * 60)
            store.finishPomodoro(completed: false)
            store.startFocus(phase: .shortBreak)
            XCTAssertEqual(store.activePomodoro?.targetSeconds, rest * 60)
            store.finishPomodoro(completed: false)
        }
        XCTAssertFalse(store.setFocusDurations(workMinutes: 0, breakMinutes: 5))
        XCTAssertFalse(store.setFocusDurations(workMinutes: 25, breakMinutes: -1))
        store.flushPendingWrites()
        let loaded = try repository.load()
        XCTAssertEqual(loaded.taskSettings.workMinutes, 37)
        XCTAssertEqual(loaded.taskSettings.shortBreakMinutes, 8)
    }
    func testFreeFocusPauseResumeAndPersistence() throws {
        var state = PersistedAppState()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        XCTAssertTrue(TaskEngine.startFocus(in: &state, now: start))
        XCTAssertFalse(TaskEngine.startFocus(in: &state, now: start))
        TaskEngine.pausePomodoro(in: &state, now: start.addingTimeInterval(60))
        XCTAssertEqual(TaskEngine.focusElapsed(try XCTUnwrap(state.activePomodoro), now: start.addingTimeInterval(120)), 60)
        let decoded = try JSONDecoder().decode(PersistedAppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.activePomodoro, state.activePomodoro)
        TaskEngine.resumePomodoro(in: &state, now: start.addingTimeInterval(120))
        let session = try XCTUnwrap(TaskEngine.finishPomodoro(in: &state, now: start.addingTimeInterval(180)))
        XCTAssertEqual(session.durationSeconds, 120)
        XCTAssertNil(session.taskID)
        XCTAssertNil(state.activePomodoro)
    }
    func testBreakAndStopwatchModes() throws {
        var state = PersistedAppState()
        XCTAssertTrue(TaskEngine.startFocus(phase: .shortBreak, in: &state))
        XCTAssertEqual(state.activePomodoro?.targetSeconds, 5 * 60)
        XCTAssertEqual(state.activePomodoro?.phase, .shortBreak)
        TaskEngine.finishPomodoro(in: &state)
        XCTAssertTrue(TaskEngine.startFocus(stopwatch: true, in: &state))
        XCTAssertEqual(state.activePomodoro?.isStopwatch, true)
    }
    @MainActor func testCountdownCompletesOnceWhilePausedAndStopwatchDoNot() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = AppStore(repository: AppStateRepository(applicationSupportDirectory: dir), startServices: false)
        store.startFocus()
        let start = try XCTUnwrap(store.activePomodoro?.startedAt)
        store.pausePomodoro()
        store.checkFocusCompletion(now: start.addingTimeInterval(4000))
        XCTAssertNotNil(store.activePomodoro)
        store.resumePomodoro()
        store.checkFocusCompletion(now: start.addingTimeInterval(4000))
        XCTAssertNil(store.activePomodoro)
        XCTAssertEqual(store.pomodoroSessions.count, 1)
        XCTAssertEqual(store.pomodoroSessions.first?.durationSeconds, 25 * 60)
        store.checkFocusCompletion(now: start.addingTimeInterval(5000))
        XCTAssertEqual(store.pomodoroSessions.count, 1)
        store.startFocus(stopwatch: true)
        store.checkFocusCompletion(now: start.addingTimeInterval(8000))
        XCTAssertNotNil(store.activePomodoro)
        store.finishPomodoro(completed: false)
        store.flushPendingWrites()
    }
}
