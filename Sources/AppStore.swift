import AppKit
import Combine
import Foundation

@MainActor
final class AppStore: NSObject, ObservableObject {
    @Published var selectedSection: AppSection = .groups
    @Published private(set) var state: PersistedAppState
    @Published private(set) var connectionState: TickTickConnectionState = .checking
    @Published private(set) var journalEntries: [JournalEntry] = []
    @Published private(set) var selectedJournalEntry: JournalEntry?
    @Published private(set) var journalDraft = ""
    @Published var journalTitleDraft = ""
    @Published var selectedGroupID: UUID?
    @Published var errorMessage: String?
    @Published private(set) var isSynchronizing = false
    @Published private(set) var browserExtensionLastContact: Date?
    @Published private(set) var safariExtensionLastContact: Date?
    @Published private(set) var journalSaveState: JournalSaveState = .idle

    private let repository: AppStateRepository
    private let journalRepository: JournalRepository
    private let tickTickService = TickTickCLIService()
    private let rulesServer = LocalRulesServer()
    private var syncTimer: Timer?
    private var lastTerminationAttempt: [pid_t: Date] = [:]
    private var lastKnownUnlockState: [UUID: Bool] = [:]
    private var isLoadingJournal = false

    override init() {
        let repository = AppStateRepository()
        self.repository = repository
        self.journalRepository = JournalRepository(applicationSupportDirectory: repository.applicationSupportDirectory)
        var loadError: String?
        do {
            state = try repository.load()
        } catch {
            state = PersistedAppState()
            loadError = "Не удалось загрузить настройки: \(error.localizedDescription)"
        }
        super.init()
        errorMessage = loadError
        selectedGroupID = state.groups.first?.id
        rollDisciplineForward()
        loadJournalEntries(selectNewest: true)
        startRulesServer()
        beginApplicationMonitoring()
        updateBlockingRules()
        scheduleSynchronization()
        Task { await refreshConnectionAndTasks() }
    }

    deinit {
        syncTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        rulesServer.stop()
    }

    var todayTasks: [TickTickTask] {
        let today = DayKey.make(from: Date())
        let local = state.localTasks.filter { $0.dayKey == today }.map(\.asTask)
        let tickTick = lastSyncIsToday ? state.cachedTasks : []
        return local + tickTick
    }
    var groups: [BlockGroup] { state.groups }
    var habits: [Habit] { state.habits }
    var events: [ActivityEvent] { state.events }
    var protectionEnabled: Bool { state.protectionEnabled }
    var disciplineStreak: Int { state.disciplineStreak }

    var browserExtensionIsConnected: Bool {
        guard let browserExtensionLastContact else { return false }
        return Date().timeIntervalSince(browserExtensionLastContact) < 120
    }

    var browserExtensionStatusText: String {
        if browserExtensionIsConnected { return "Расширение подключено и получает правила" }
        return "Ждём сигнал от расширения. Обычно он приходит в течение 30 секунд"
    }

    var safariExtensionIsConnected: Bool {
        guard let safariExtensionLastContact else { return false }
        return Date().timeIntervalSince(safariExtensionLastContact) < 120
    }

    var safariContainerURL: URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/hidigFocus Safari.app", isDirectory: true),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("hidigFocus Safari.app", isDirectory: true)
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    var safariContainerIsInstalled: Bool { safariContainerURL != nil }

    var safariExtensionStatusText: String {
        if safariExtensionIsConnected { return "Расширение получает правила hidigFocus" }
        if safariContainerIsInstalled {
            return "Модуль установлен, но не связался с приложением. Проверьте, что расширение включено в Safari и имеет доступ ко всем сайтам."
        }
        return "Safari-модуль не найден в папке «Программы»."
    }

    var completedTaskCount: Int {
        todayTasks.filter(\.isCompleted).count
    }

    var selectedGroup: BlockGroup? {
        guard let selectedGroupID else { return state.groups.first }
        return state.groups.first { $0.id == selectedGroupID }
    }

    var lastSyncIsToday: Bool {
        guard let date = state.lastSuccessfulSync else { return false }
        return Calendar.current.isDateInToday(date)
    }

    func groupIsUnlocked(_ group: BlockGroup) -> Bool {
        guard group.isEnabled else { return true }
        guard state.protectionEnabled else { return true }
        if group.accessMode.usesSchedule, !group.schedule.isActive() { return true }
        if group.accessMode == .schedule { return false }
        let required: [TickTickTask]
        if group.requiresAllTodayTasks {
            required = todayTasks
        } else {
            required = todayTasks.filter { group.requiredTaskIDs.contains($0.id) }
        }
        guard !required.isEmpty else { return false }
        return required.allSatisfy(\.isCompleted)
    }

    func remainingTaskCount(for group: BlockGroup) -> Int {
        guard group.accessMode.usesTasks else { return 0 }
        let required = group.requiresAllTodayTasks
            ? todayTasks
            : todayTasks.filter { group.requiredTaskIDs.contains($0.id) }
        return required.filter { !$0.isCompleted }.count
    }

    func setProtectionEnabled(_ enabled: Bool) {
        guard enabled else { return }
        state.protectionEnabled = true
        state.disciplineLastCountedDayKey = DayKey.make(from: Date())
        appendEvent(.taskSync, "Защита включена.")
        saveAndApply()
    }

    func disableProtection() {
        guard state.protectionEnabled else { return }
        state.protectionEnabled = false
        state.disciplineStreak = 0
        state.disciplineLastCountedDayKey = DayKey.make(from: Date())
        for index in state.habits.indices {
            state.habits[index].resetCurrentStreak()
        }
        appendEvent(.protectionDisabled, "Защита отключена. Текущие серии обнулены.")
        saveAndApply()
    }

    func addGroup(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let group = BlockGroup.draft(name: name)
        state.groups.append(group)
        selectedGroupID = group.id
        saveAndApply()
    }

    func removeGroup(_ id: UUID) {
        guard state.groups.count > 1 else {
            errorMessage = "Должна остаться хотя бы одна группа."
            return
        }
        state.groups.removeAll { $0.id == id }
        if selectedGroupID == id { selectedGroupID = state.groups.first?.id }
        saveAndApply()
    }

    func updateGroupName(_ id: UUID, name: String) {
        guard let index = state.groups.firstIndex(where: { $0.id == id }) else { return }
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        state.groups[index].name = value
        saveAndApply()
    }

    func setGroupUsesAllTasks(_ id: UUID, value: Bool) {
        guard let index = state.groups.firstIndex(where: { $0.id == id }) else { return }
        state.groups[index].requiresAllTodayTasks = value
        if value { state.groups[index].requiredTaskIDs.removeAll() }
        saveAndApply()
    }

    func setGroupEnabled(_ id: UUID, value: Bool) {
        guard let index = state.groups.firstIndex(where: { $0.id == id }) else { return }
        state.groups[index].isEnabled = value
        saveAndApply()
    }

    func setGroupAccessMode(_ id: UUID, mode: GroupAccessMode) {
        guard let index = state.groups.firstIndex(where: { $0.id == id }) else { return }
        state.groups[index].accessMode = mode
        saveAndApply()
    }

    func updateGroupSchedule(_ id: UUID, schedule: BlockSchedule) {
        guard let index = state.groups.firstIndex(where: { $0.id == id }) else { return }
        state.groups[index].schedule = schedule
        saveAndApply()
    }

    func toggleRequiredTask(_ taskID: String, in groupID: UUID) {
        guard let index = state.groups.firstIndex(where: { $0.id == groupID }) else { return }
        if state.groups[index].requiredTaskIDs.contains(taskID) {
            state.groups[index].requiredTaskIDs.remove(taskID)
        } else {
            state.groups[index].requiredTaskIDs.insert(taskID)
        }
        saveAndApply()
    }

    func setRequiredTasks(_ taskIDs: Set<String>, in groupID: UUID) {
        guard let index = state.groups.firstIndex(where: { $0.id == groupID }) else { return }
        state.groups[index].requiredTaskIDs = taskIDs
        saveAndApply()
    }

    func addDomain(_ rawDomain: String, displayName: String, to groupID: UUID) throws {
        guard let index = state.groups.firstIndex(where: { $0.id == groupID }) else { return }
        let domain = LocalRulesServer.normalizedDomain(rawDomain)
        guard domain.contains("."), !domain.contains(" ") else { throw AppError.invalidDomain }
        guard !state.groups[index].resources.contains(where: { $0.kind == .domain && $0.identifier == domain }) else {
            throw AppError.duplicateResource
        }
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        state.groups[index].resources.append(BlockedResource(
            kind: .domain,
            displayName: name.isEmpty ? domain : name,
            identifier: domain
        ))
        saveAndApply()
    }

    func addApplication(at url: URL, to groupID: UUID) throws {
        guard let index = state.groups.firstIndex(where: { $0.id == groupID }),
              let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else {
            throw AppError.invalidApplication
        }
        guard !state.groups[index].resources.contains(where: { $0.kind == .application && $0.identifier == bundleID }) else {
            throw AppError.duplicateResource
        }
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent
        state.groups[index].resources.append(BlockedResource(
            kind: .application,
            displayName: displayName,
            identifier: bundleID,
            path: url.path
        ))
        saveAndApply()
        evaluateRunningApplications()
    }

    func removeResource(_ resourceID: UUID, from groupID: UUID) {
        guard let index = state.groups.firstIndex(where: { $0.id == groupID }) else { return }
        state.groups[index].resources.removeAll { $0.id == resourceID }
        saveAndApply()
    }

    func updateResource(
        _ resourceID: UUID,
        in groupID: UUID,
        displayName rawName: String,
        identifier rawIdentifier: String
    ) throws {
        guard let groupIndex = state.groups.firstIndex(where: { $0.id == groupID }),
              let resourceIndex = state.groups[groupIndex].resources.firstIndex(where: { $0.id == resourceID }) else {
            return
        }

        let existing = state.groups[groupIndex].resources[resourceIndex]
        let identifier: String
        switch existing.kind {
        case .domain:
            identifier = LocalRulesServer.normalizedDomain(rawIdentifier)
            guard identifier.contains("."), !identifier.contains(" ") else { throw AppError.invalidDomain }
        case .application:
            identifier = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !identifier.isEmpty, !identifier.contains(" ") else { throw AppError.invalidApplication }
        }

        guard !state.groups[groupIndex].resources.contains(where: {
            $0.id != resourceID && $0.kind == existing.kind && $0.identifier == identifier
        }) else {
            throw AppError.duplicateResource
        }

        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        state.groups[groupIndex].resources[resourceIndex].displayName = name.isEmpty ? identifier : name
        state.groups[groupIndex].resources[resourceIndex].identifier = identifier
        saveAndApply()
    }

    func addHabit(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        state.habits.append(Habit(name: name))
        save()
    }

    func addLocalTask(named rawName: String) {
        let title = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        state.localTasks.append(FocusTask(title: title))
        saveAndApply()
    }

    func toggleLocalTask(_ id: String) {
        guard let index = state.localTasks.firstIndex(where: { $0.id == id }) else { return }
        state.localTasks[index].isCompleted.toggle()
        recordNewlyUnlockedGroups()
        saveAndApply()
    }

    func removeLocalTask(_ id: String) {
        state.localTasks.removeAll { $0.id == id }
        for index in state.groups.indices {
            state.groups[index].requiredTaskIDs.remove(id)
        }
        saveAndApply()
    }

    func toggleHabit(_ habitID: UUID, on date: Date = Date()) {
        guard let index = state.habits.firstIndex(where: { $0.id == habitID }) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: date)
        guard target <= start,
              let earliest = Calendar.current.date(byAdding: .day, value: -1, to: start),
              target >= earliest else {
            errorMessage = "Отметку можно изменить только за сегодня или вчера. Более старые пропуски восстановить нельзя."
            return
        }
        state.habits[index].toggle(on: target)
        appendEvent(.habitChecked, "Обновлена привычка «\(state.habits[index].name)».")
        save()
    }

    func removeHabit(_ habitID: UUID) {
        state.habits.removeAll { $0.id == habitID }
        save()
    }

    func moveHabit(_ habitID: UUID, relativeTo targetID: UUID) {
        guard habitID != targetID,
              let sourceIndex = state.habits.firstIndex(where: { $0.id == habitID }),
              let originalTargetIndex = state.habits.firstIndex(where: { $0.id == targetID }) else {
            return
        }

        let habit = state.habits.remove(at: sourceIndex)
        guard let targetIndex = state.habits.firstIndex(where: { $0.id == targetID }) else { return }
        let insertionIndex = sourceIndex < originalTargetIndex ? targetIndex + 1 : targetIndex
        state.habits.insert(habit, at: min(insertionIndex, state.habits.endIndex))
        save()
    }

    func refreshConnectionAndTasks() async {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        connectionState = .checking
        let connection = await tickTickService.connectionState()
        connectionState = connection
        if connection == .connected {
            await synchronizeTasks()
        }
        isSynchronizing = false
    }

    func connectTickTick() async {
        connectionState = .connecting
        do {
            try await tickTickService.authenticate()
            connectionState = await tickTickService.connectionState()
            if connectionState == .connected { await synchronizeTasks() }
        } catch {
            connectionState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func synchronizeTasks() async {
        guard connectionState == .connected else { return }
        isSynchronizing = true
        do {
            let tasks = try await tickTickService.todayTasks()
            let previous = state.cachedTasks
            state.cachedTasks = tasks
            state.lastSuccessfulSync = Date()
            if previous != tasks {
                appendEvent(.taskSync, "TickTick: получено задач на сегодня — \(tasks.count).")
            }
            recordNewlyUnlockedGroups()
            saveAndApply()
        } catch {
            connectionState = .failed(error.localizedDescription)
            appendEvent(.error, "TickTick: \(error.localizedDescription)")
            saveAndApply()
        }
        isSynchronizing = false
    }

    func copyCLIInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("npm install -g @ticktick/ticktick-cli", forType: .string)
    }

    func revealBrowserExtension() {
        guard let projectURL = Bundle.module.resourceURL?
            .appendingPathComponent("BrowserExtension", isDirectory: true),
              FileManager.default.fileExists(atPath: projectURL.path) else {
            errorMessage = "Папка браузерного расширения не найдена в приложении."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([projectURL])
    }

    func revealSafariExtension() {
        guard let url = safariExtensionURL else {
            errorMessage = "Папка Safari-расширения не найдена в приложении."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func launchSafariContainer() {
        guard let url = safariContainerURL else {
            errorMessage = "Safari-модуль не установлен. Распакуйте архив и перенесите «hidigFocus Safari» в папку «Программы»."
            return
        }
        NSWorkspace.shared.open(url)
    }

    func copyBrowserExtensionPath() {
        guard let projectURL = browserExtensionURL else {
            errorMessage = "Папка браузерного расширения не найдена в приложении."
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(projectURL.path, forType: .string)
    }

    func copyBrowserExtensionsAddress(_ address: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(address, forType: .string)
    }

    var browserExtensionURL: URL? {
        guard let url = Bundle.module.resourceURL?.appendingPathComponent("BrowserExtension", isDirectory: true),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) else { return nil }
        return url
    }

    var safariExtensionURL: URL? {
        guard let url = Bundle.module.resourceURL?.appendingPathComponent("SafariExtension", isDirectory: true),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) else { return nil }
        return url
    }

    func reloadJournalEntries() {
        loadJournalEntries(selectNewest: selectedJournalEntry == nil)
    }

    func createJournalEntry() {
        do {
            let entry = try journalRepository.createTodayEntry()
            loadJournalEntries(selectNewest: false)
            selectJournalEntry(entry)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectJournalEntry(_ entry: JournalEntry) {
        do {
            isLoadingJournal = true
            selectedJournalEntry = entry
            journalTitleDraft = entry.title
            journalDraft = try journalRepository.read(entry)
            journalSaveState = .saved(entry.modifiedAt)
            isLoadingJournal = false
        } catch {
            isLoadingJournal = false
            errorMessage = error.localizedDescription
        }
    }

    func updateJournalDraft(_ value: String) {
        journalDraft = value
        guard !isLoadingJournal, let entry = selectedJournalEntry else { return }
        journalSaveState = .saving
        do {
            try journalRepository.write(value, to: entry)
            journalSaveState = .saved(Date())
        } catch {
            journalSaveState = .failed
            errorMessage = error.localizedDescription
        }
    }

    func renameSelectedJournalEntry() {
        guard let entry = selectedJournalEntry else { return }
        do {
            let renamed = try journalRepository.rename(entry, to: journalTitleDraft)
            selectedJournalEntry = renamed
            journalTitleDraft = renamed.title
            loadJournalEntries(selectNewest: false)
            if let refreshed = journalEntries.first(where: { $0.id == renamed.id }) {
                selectedJournalEntry = refreshed
            }
            journalSaveState = .saved(Date())
        } catch {
            journalTitleDraft = entry.title
            errorMessage = error.localizedDescription
        }
    }

    func revealJournalFolder() {
        do {
            try journalRepository.revealDirectory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func events(inLastDays days: Int, kind: ActivityEventKind? = nil) -> [ActivityEvent] {
        let start = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        return state.events.filter { $0.timestamp >= start && (kind == nil || $0.kind == kind) }
    }

    private func startRulesServer() {
        do {
            rulesServer.onRulesRequest = { [weak self] client in
                Task { @MainActor in
                    if client == "safari" {
                        self?.safariExtensionLastContact = Date()
                    } else {
                        self?.browserExtensionLastContact = Date()
                    }
                }
            }
            try rulesServer.start()
        } catch {
            appendEvent(.error, "Не удалось запустить локальный сервис браузерных правил: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSynchronization() {
        syncTimer = Timer.scheduledTimer(
            timeInterval: 60,
            target: self,
            selector: #selector(synchronizationTimerFired(_:)),
            userInfo: nil,
            repeats: true
        )
    }

    private func beginApplicationMonitoring() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self,
            selector: #selector(workspaceApplicationChanged(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(workspaceApplicationChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        evaluateRunningApplications()
    }

    @objc private func synchronizationTimerFired(_ timer: Timer) {
        Task {
            await refreshConnectionAndTasks()
            updateBlockingRules()
            evaluateRunningApplications()
        }
    }

    @objc private func workspaceApplicationChanged(_ notification: Notification) {
        evaluateRunningApplications()
    }

    private func evaluateRunningApplications() {
        guard state.protectionEnabled else { return }
        let identifiers = Set(state.groups
            .filter { $0.isEnabled && !groupIsUnlocked($0) }
            .flatMap(\.resources)
            .filter { $0.kind == .application }
            .map(\.identifier))
        guard !identifiers.isEmpty else { return }

        let currentPID = ProcessInfo.processInfo.processIdentifier
        let currentTime = Date()
        for application in NSWorkspace.shared.runningApplications {
            guard application.processIdentifier != currentPID,
                  let identifier = application.bundleIdentifier,
                  identifiers.contains(identifier) else { continue }
            if let previous = lastTerminationAttempt[application.processIdentifier],
               currentTime.timeIntervalSince(previous) < 5 { continue }
            lastTerminationAttempt[application.processIdentifier] = currentTime
            let name = application.localizedName ?? identifier
            if application.terminate() {
                appendEvent(.applicationClosed, "Закрыто приложение: \(name).")
            } else {
                appendEvent(.error, "Не удалось закрыть приложение: \(name).")
            }
            save()
        }
    }

    private func updateBlockingRules() {
        let rules = state.groups
            .filter { $0.isEnabled && !groupIsUnlocked($0) }
            .flatMap { group -> [BrowserBlockRule] in
                let requiredTasks = group.requiresAllTodayTasks
                    ? todayTasks
                    : todayTasks.filter { group.requiredTaskIDs.contains($0.id) }
                let remainingTasks = requiredTasks.filter { !$0.isCompleted }.map(\.title)

                let reason: BrowserBlockReason
                let blockedUntil: Date?
                if group.accessMode.usesTasks && !remainingTasks.isEmpty {
                    reason = .tasks
                    blockedUntil = nil
                } else if group.accessMode == .schedule,
                          let scheduleEnd = group.schedule.nextInactiveDate() {
                    reason = .schedule
                    blockedUntil = scheduleEnd
                } else {
                    reason = .permanent
                    blockedUntil = nil
                }

                return group.resources
                    .filter { $0.kind == .domain }
                    .map {
                        BrowserBlockRule(
                            domain: $0.identifier,
                            groupName: group.name,
                            reason: reason,
                            remainingTasks: remainingTasks,
                            blockedUntil: blockedUntil
                        )
                    }
            }
        rulesServer.update(rules: state.protectionEnabled ? rules : [])
    }

    private func recordNewlyUnlockedGroups() {
        for group in state.groups {
            let unlocked = groupIsUnlocked(group)
            if unlocked && lastKnownUnlockState[group.id] == false {
                appendEvent(.groupUnlocked, "Открыта группа «\(group.name)».")
            }
            lastKnownUnlockState[group.id] = unlocked
        }
    }

    private func rollDisciplineForward() {
        let today = DayKey.make(from: Date())
        guard state.protectionEnabled else {
            state.disciplineLastCountedDayKey = today
            return
        }
        guard let previousKey = state.disciplineLastCountedDayKey else {
            state.disciplineLastCountedDayKey = today
            save()
            return
        }
        guard previousKey != today else { return }
        state.disciplineStreak += 1
        state.disciplineLastCountedDayKey = today
        save()
    }

    private func loadJournalEntries(selectNewest: Bool) {
        do {
            journalEntries = try journalRepository.entries()
            if journalEntries.isEmpty {
                let entry = try journalRepository.createTodayEntry()
                journalEntries = [entry]
            }
            if selectNewest, let entry = journalEntries.first {
                selectJournalEntry(entry)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func appendEvent(_ kind: ActivityEventKind, _ message: String) {
        state.events.insert(ActivityEvent(kind: kind, message: message), at: 0)
        if state.events.count > 500 {
            state.events.removeLast(state.events.count - 500)
        }
    }

    private func saveAndApply() {
        save()
        updateBlockingRules()
        evaluateRunningApplications()
    }

    private func save() {
        do {
            try repository.save(state)
        } catch {
            errorMessage = "Не удалось сохранить данные: \(error.localizedDescription)"
        }
    }
}
