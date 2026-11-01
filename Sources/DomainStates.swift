import Combine
import Foundation

// Separate publishers intentionally never forward into AppStore.objectWillChange.
// Views subscribe only to the domain they display; command proxies preserve existing APIs.
@MainActor
final class JournalState: ObservableObject {
    @Published var journalEntries: [JournalEntry] = []
    @Published var selectedJournalEntry: JournalEntry? = nil
    @Published var journalDraft: String = ""
    @Published var journalTitleDraft: String = ""
    @Published var journalSaveState: JournalSaveState = .idle
}

@MainActor
final class SaveState: ObservableObject {
    @Published var taskSaveState: JournalSaveState = .idle
}

@MainActor
final class IntegrationState: ObservableObject {
    @Published var connectionState: TickTickConnectionState = .notRequested
    @Published var isSynchronizing: Bool = false
    @Published var browserExtensionLastContact: Date? = nil
    @Published var safariExtensionLastContact: Date? = nil
    @Published var googleCalendars: [GoogleCalendarDescriptor] = []
    @Published var isGoogleSynchronizing: Bool = false
    @Published var tickTickImportError: String? = nil
    @Published var tickTickImportPreview: TaskImportPreview? = nil
    @Published var isImportingTickTick: Bool = false
    var browserConnected: Bool { browserExtensionLastContact.map { Date().timeIntervalSince($0) < 120 } ?? false }
    var safariConnected: Bool { safariExtensionLastContact.map { Date().timeIntervalSince($0) < 120 } ?? false }
}

/// Shared presentation context for the main and compact focus windows; never persisted as task data.
@MainActor final class FocusPresentationState: ObservableObject {
    @Published var selectedTask: UUID?
    @Published var phase: PomodoroPhase = .work
    @Published var stopwatch = false
}
