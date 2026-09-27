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
    @Published var selectedTaskID: UUID?
    @Published var taskSidebarSelection: TaskSidebarSelection = .today
    let planner: PlannerWorkspace
    let reminderService = TaskReminderService()
    var tasksPresentation: TasksPresentation { get { planner.presentation } set { planner.presentation = newValue } }
    var taskCalendarMode: TaskCalendarMode { get { planner.mode } set { planner.mode = newValue } }
    var taskCalendarAnchor: Date { get { planner.anchor } set { planner.anchor = newValue } }
    @Published private(set) var taskSaveState: JournalSaveState = .idle
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    private var undoEntries: [TaskHistoryEntry] = []
    private var redoEntries: [TaskHistoryEntry] = []
    @Published private(set) var canUndoHabit = false
    private var habitUndo: (Habit, Habit)?
    private var pendingUndo: [ManagedTask]?
    private var saveRevision: UInt64 = 0
    private var writer: SaveCoordinator!
    private var persistenceFailedToLoad = false
    private var indexedTasks: [ManagedTask] = []
    private var taskPositions: [UUID: Int] = [:]
    private var listPositions: [UUID: Int] = [:]
    private var countCache: [TaskSidebarSelection: Int] = [:]
    private var countCacheDay: Date?
    private var countCacheCompleted = false
    private var calendarIndex = PlannerCalendarIndex()
    private var calendarFallbackDays: [Date: [ManagedTask]] = [:]
    private var calendarPreparationScheduled = false
    private var calendarNavigationAnchor: Date?
    private var indexRequest: UInt64 = 0
    private var indexBuild: Task<Void, Never>?
    private var indexRequestedAnchor: Date?
    private var projectionGeneration: UInt64 = 0
    private var virtualTasks: [UUID: ManagedTask] = [:]
    private let journalWriter = DispatchQueue(label: "hidigFocus.journal", qos: .utility)
    private var lastReminderDay = Calendar.current.startOfDay(for: Date())
    private var pendingJournalSave: Task<Void, Never>?
    private var pendingJournalValue: (String, JournalEntry, Int)?
    private var journalRevision = 0
    @Published var errorMessage: String?
    @Published private(set) var isSynchronizing = false
    @Published private(set) var browserExtensionLastContact: Date?
    @Published private(set) var safariExtensionLastContact: Date?
    @Published private(set) var journalSaveState: JournalSaveState = .idle
    @Published private(set) var googleCalendars: [GoogleCalendarDescriptor] = []
    @Published private(set) var googleCalendarEvents: [GoogleCalendarEventSnapshot] = []
    @Published private(set) var isGoogleSynchronizing = false
    @Published private(set) var tickTickImportPreview: TaskImportPreview?
    @Published private(set) var isImportingTickTick = false

    private let servicesEnabled: Bool
    private let repository: AppStateRepository
    private let journalRepository: JournalRepository
    private let tickTickService = TickTickCLIService()
    private let googleCalendarService = GoogleCalendarService()
    private let rulesServer = LocalRulesServer()
    private var syncTimer: Timer?
    private var focusTimer: Timer?
    private var lastTerminationAttempt: [pid_t: Date] = [:]
    private var lastKnownUnlockState: [UUID: Bool] = [:]
    private var isLoadingJournal = false
    private var pendingTickTickImport: TickTickCLIService.ImportSnapshot?

    override convenience init() {
        self.init(repository: AppStateRepository(), startServices: ProcessInfo.processInfo.environment["HIDIGFOCUS_QA"] != "1")
    }
    init(repository: AppStateRepository, startServices: Bool = true, plannerDefaults: UserDefaults = .standard) {
        self.planner = PlannerWorkspace(defaults: plannerDefaults)
        self.servicesEnabled = startServices
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
        if startServices {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.checkFocusCompletion() }
            }
            focusTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        if ProcessInfo.processInfo.environment["HIDIGFOCUS_QA"] == "1", state.managedTasks.isEmpty,
           let count = ProcessInfo.processInfo.environment["HIDIGFOCUS_QA_TASKS"].flatMap(Int.init) {
            state = PlannerFixtures.make(count: count)
        }
        if ProcessInfo.processInfo.environment["HIDIGFOCUS_QA"] == "1" {
            selectedSection = .tasks; planner.presentation = .calendar; planner.mode = .fourDays; planner.anchor = Date()
        }
        writer = SaveCoordinator(repository: repository)
        persistenceFailedToLoad = loadError != nil
        indexedTasks = state.managedTasks
        rebuildTaskPositions()
        calendarIndex.replaceTasks(indexedTasks)
        reminderService.refresh(state.managedTasks)
        errorMessage = loadError
        NotificationCenter.default.addObserver(self, selector: #selector(flushBeforeTermination), name: NSApplication.willTerminateNotification, object: nil)
        selectedGroupID = state.groups.first?.id
        rollDisciplineForward()
        loadJournalEntries(selectNewest: true)
        if startServices {
            startRulesServer(); beginApplicationMonitoring(); updateBlockingRules(); scheduleSynchronization()
            Task { await refreshConnectionAndTasks() }
        }
    }

    deinit {
        focusTimer?.invalidate()
        syncTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        rulesServer.stop()
    }

    var todayTasks: [TickTickTask] {
        let today = DayKey.make(from: Date())
        let local = state.localTasks.filter { $0.dayKey == today }.map(\.asTask)
        let tickTick = lastSyncIsToday ? state.cachedTasks : []
        return local + tickTick
    }
    var groups: [BlockGroup] { state.groups.map { state.pendingGroupRules?[$0.id] ?? $0 } }
    var habits: [Habit] { state.habits }
    var habitsDueToday: [Habit] {
        state.habits.enumerated()
            .filter { $0.element.isDue(on: Date()) }
            .sorted {
                if $0.element.priority.rank != $1.element.priority.rank {
                    return $0.element.priority.rank > $1.element.priority.rank
                }
                return $0.offset < $1.offset
            }
            .map(\.element)
    }
    var events: [ActivityEvent] { state.events }
    var protectionEnabled: Bool { state.protectionEnabled }
    var disciplineStreak: Int { state.disciplineStreak }
    var taskFolders: [TaskFolder] { state.taskFolders.sorted { $0.sortOrder < $1.sortOrder } }
    var taskLists: [TaskList] { state.taskLists.sorted { $0.sortOrder < $1.sortOrder } }
    var selectedManagedTask: ManagedTask? {
        guard let selectedTaskID else { return nil }
        return task(id: selectedTaskID)
    }

    var visibleManagedTasks: [ManagedTask] {
        tasks(for: taskSidebarSelection)
    }

    private func tasks(for selection: TaskSidebarSelection) -> [ManagedTask] {
        let calendar = PlannerCalendar.current
        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let filtered = state.managedTasks.filter { task in
            let allowed = task.status == .active || (planner.filter.showCompleted && task.status == .completed)
            switch selection {
            case .all: return allowed
            case .tomorrow: return allowed && (task.startDate ?? task.dueDate).map { calendar.isDateInTomorrow($0) } == true
            case .unscheduled: return allowed && task.startDate == nil
            case .today:
                return allowed && (task.startDate.map(calendar.isDateInToday) == true || task.dueDate.map { $0 < calendar.date(byAdding: .day, value: 1, to: start)! } == true)
            case .nextSevenDays:
                return allowed && (task.startDate ?? task.dueDate).map { $0 >= start && $0 < end } == true
            case .inbox:
                return allowed && task.listID == TaskList.inboxID
            case .list(let id):
                return allowed && task.listID == id
            case .completed:
                return task.status == .completed
            case .trash:
                return task.status == .trashed
            }
        }
        if selection == .completed {
            return filtered.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        }
        return filtered.sorted {
            switch ($0.startDate, $1.startDate) {
            case let (left?, right?) where left != right: return left < right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return $0.sortOrder < $1.sortOrder
            }
        }
    }

    var unscheduledManagedTasks: [ManagedTask] {
        state.managedTasks.filter { $0.status == .active && $0.startDate == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var activeTaskCount: Int { state.managedTasks.filter { $0.status == .active }.count }

    func visibleCount(selection: TaskSidebarSelection) -> Int {
        let day = PlannerCalendar.current.startOfDay(for: Date())
        if day != countCacheDay || countCacheCompleted != planner.filter.showCompleted {
            countCache.removeAll(); countCacheDay = day; countCacheCompleted = planner.filter.showCompleted
        }
        if countCache.isEmpty { rebuildCounts(day: day) }
        return countCache[selection] ?? 0
    }
    private func rebuildCounts(day: Date) {
        let calendar = PlannerCalendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: day) ?? day
        for task in state.managedTasks {
            if task.status == .completed { countCache[.completed, default: 0] += 1 }
            if task.status == .trashed { countCache[.trash, default: 0] += 1 }
            guard task.status == .active || (countCacheCompleted && task.status == .completed) else { continue }
            countCache[.all, default: 0] += 1
            countCache[.list(task.listID), default: 0] += 1
            if task.listID == TaskList.inboxID { countCache[.inbox, default: 0] += 1 }
            if task.startDate == nil { countCache[.unscheduled, default: 0] += 1 }
            if task.startDate.map({ calendar.isDate($0, inSameDayAs: day) }) == true || task.dueDate.map({ $0 < tomorrow }) == true { countCache[.today, default: 0] += 1 }
            if let date = task.startDate ?? task.dueDate {
                if calendar.isDate(date, inSameDayAs: tomorrow) { countCache[.tomorrow, default: 0] += 1 }
                if date >= day && date < weekEnd { countCache[.nextSevenDays, default: 0] += 1 }
            }
        }
    }

    func calendarTasks(on day: Date) -> [ManagedTask] {
        if let cached = calendarIndex.cachedDay(day) {
            if projectionGeneration != calendarIndex.generation {
                virtualTasks.merge(calendarIndex.projectedByID, uniquingKeysWith: { _, latest in latest })
                projectionGeneration = calendarIndex.generation
            }
            return cached
        }
        if !calendarPreparationScheduled {
            calendarPreparationScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.calendarPreparationScheduled = false
                self.prepareCalendarIndex(around: self.calendarNavigationAnchor)
            }
        }
        let first = PlannerCalendar.current.startOfDay(for: day)
        if let cached = calendarFallbackDays[first] { return cached }
        let end = PlannerCalendar.current.date(byAdding: .day, value: 1, to: first) ?? first
        // A cheap real-task fallback stays usable while recurrence indexing runs off the UI thread.
        let fallback = indexedTasks.filter {
            guard $0.status == .active || $0.status == .completed, let start = $0.startDate ?? $0.dueDate else { return false }
            if ($0.excludedOccurrences ?? []).contains(start), $0.seriesRootID == nil { return false }
            if $0.isAllDay || $0.startDate == nil { return PlannerCalendar.current.isDate(start, inSameDayAs: first) }
            return start < end && ($0.calendarEndDate ?? start.addingTimeInterval(900)) > first
        }
        // Bound memory during navigation across many years.
        if calendarFallbackDays.count >= 128 { calendarFallbackDays.removeAll(keepingCapacity: true) }
        calendarFallbackDays[first] = fallback
        return fallback
    }
    func prepareCalendarIndex(around date: Date? = nil, force: Bool = false) {
        let anchor = PlannerCalendar.current.startOfDay(for: date ?? planner.anchor)
        calendarNavigationAnchor = anchor
        let leading = PlannerCalendar.current.date(byAdding: .day, value: -7, to: anchor) ?? anchor
        let trailing = PlannerCalendar.current.date(byAdding: .day, value: planner.mode == .agenda ? 29 : 13, to: anchor) ?? anchor
        if !force, calendarIndex.cachedDay(anchor) != nil, calendarIndex.cachedDay(leading) != nil, calendarIndex.cachedDay(trailing) != nil { return }
        // One in-flight window already covers nearby dates; do not cancel it at every day boundary.
        if !force, let requested = indexRequestedAnchor, indexBuild != nil,
           abs(PlannerCalendar.current.dateComponents([.day], from: requested, to: anchor).day ?? 0) <= 20 { return }
        indexRequest += 1; let revision = indexRequest
        indexRequestedAnchor = anchor
        if !planner.preparingCalendar { planner.preparingCalendar = true }
        let tasks = indexedTasks, radius = 45
        indexBuild?.cancel()
        indexBuild = Task { [weak self] in
            // Coalesce bursts before starting recurrence work, including reversal.
            do { try await Task.sleep(nanoseconds: 30_000_000) } catch { return }
            let prepared = await Task.detached(priority: .userInitiated) {
                let index = PlannerCalendarIndex(radius: radius); index.replaceTasks(tasks); _ = index.day(anchor); return index
            }.value
            guard let self, revision == self.indexRequest, !Task.isCancelled else { return }
            self.calendarIndex = prepared; self.projectionGeneration = 0; self.indexBuild = nil
            self.planner.preparingCalendar = false; self.planner.calendarRevision += 1
        }
    }

    func plannerMatches(_ task: ManagedTask, search: String, includeTrash: Bool = false, includeCompleted: Bool = false) -> Bool {
        planner.filter.matches(task, search: search, includeTrash: includeTrash, includeCompleted: includeCompleted)
    }
    func plannerEvents(on day: Date, search: String) -> [GoogleCalendarEventSnapshot] {
        let first = PlannerCalendar.current.startOfDay(for: day)
        let end = PlannerCalendar.current.date(byAdding: .day, value: 1, to: first) ?? first
        return googleCalendarEvents.filter { $0.startDate < end && $0.endDate > first && planner.filter.matches($0, search: search) }
    }
    func task(id: UUID) -> ManagedTask? {
        if let index = taskPositions[id], state.managedTasks.indices.contains(index), state.managedTasks[index].id == id {
            return state.managedTasks[index]
        }
        // Validate positions because an operation can add/remove a task before save().
        if let index = state.managedTasks.firstIndex(where: { $0.id == id }) {
            taskPositions[id] = index; return state.managedTasks[index]
        }
        taskPositions.removeValue(forKey: id)
        return virtualTasks[id]
    }
    func taskList(id: UUID) -> TaskList? {
        if let index = listPositions[id], state.taskLists.indices.contains(index), state.taskLists[index].id == id { return state.taskLists[index] }
        guard let index = state.taskLists.firstIndex(where: { $0.id == id }) else { return nil }
        listPositions[id] = index; return state.taskLists[index]
    }
    private func rebuildTaskPositions() {
        taskPositions = Dictionary(state.managedTasks.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        listPositions = Dictionary(state.taskLists.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        countCache.removeAll()
    }
    func resolvedTask(id: UUID) -> ManagedTask? {
        guard let root = task(id: id) else { return nil }
        if root.repeatRule != nil, let date = root.startDate ?? root.dueDate, (root.excludedOccurrences ?? []).contains(date) {
            return task(id: RecurrenceProjection.occurrenceID(root: id, date: date)) ?? root
        }
        return root
    }
    private func materialize(_ id: UUID) {
        guard !state.managedTasks.contains(where: { $0.id == id }), let task = virtualTasks[id],
              let root = task.seriesRootID, let date = task.occurrenceDate,
              let index = state.managedTasks.firstIndex(where: { $0.id == root }) else { return }
        var latest = state.managedTasks[index]
        latest.id = task.id; latest.seriesRootID = root; latest.occurrenceDate = date
        latest.startDate = task.startDate; latest.plannedEndDate = task.startDate.map { $0.addingTimeInterval(Double(latest.durationMinutes * 60)) }
        latest.status = .active; latest.completedAt = nil; latest.repeatRule = nil; latest.excludedOccurrences = nil; latest.nextOccurrenceID = nil
        latest.sourceID = nil; latest.tickTickBaseline = nil; latest.googleEventID = nil; latest.googleCalendarID = nil; latest.googleETag = nil
        state.managedTasks[index].excludedOccurrences = (state.managedTasks[index].excludedOccurrences ?? []) + [date]
        state.managedTasks.append(latest)
    }
    private func editableOccurrenceID(_ id: UUID) -> UUID {
        materialize(id)
        guard let root = task(id: id), root.repeatRule != nil, root.seriesRootID == nil,
              let date = root.startDate ?? root.dueDate,
              let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { return id }
        let occurrenceID = RecurrenceProjection.occurrenceID(root: root.id, date: date)
        if !state.managedTasks.contains(where: { $0.id == occurrenceID }) {
            var copy = root; copy.id = occurrenceID; copy.seriesRootID = id; copy.occurrenceDate = date
            copy.repeatRule = nil; copy.excludedOccurrences = nil; copy.nextOccurrenceID = nil
            copy.sourceID = nil; copy.tickTickBaseline = nil
            state.managedTasks.append(copy)
        }
        if !(state.managedTasks[index].excludedOccurrences ?? []).contains(date) {
            state.managedTasks[index].excludedOccurrences = (state.managedTasks[index].excludedOccurrences ?? []) + [date]
        }
        return occurrenceID
    }
    func updateSeriesEdits(from original: ManagedTask, to draft: ManagedTask) {
        let rootID = original.seriesRootID ?? original.id
        guard let rootIndex = state.managedTasks.firstIndex(where: { $0.id == rootID }) else { return }
        recordTaskUndo()
        let shift = draft.startDate.flatMap { new in original.startDate.map { new.timeIntervalSince($0) } } ?? 0
        for index in state.managedTasks.indices where state.managedTasks[index].id == rootID || state.managedTasks[index].seriesRootID == rootID {
            var value = state.managedTasks[index]
            if original.title != draft.title { value.title = draft.title }
            if original.description != draft.description { value.description = draft.description }
            if original.notes != draft.notes { value.notes = draft.notes }
            if original.listID != draft.listID { value.listID = draft.listID }
            if original.tags != draft.tags { value.tags = draft.tags }
            if original.priority != draft.priority { value.priority = draft.priority }
            if original.checklist != draft.checklist { value.checklist = draft.checklist }
            if original.attachments != draft.attachments { value.attachments = draft.attachments }
            if original.reminders != draft.reminders { value.reminders = draft.reminders }
            if original.repeatRule != draft.repeatRule, value.id == rootID { value.repeatRule = draft.repeatRule }
            if original.isAllDay != draft.isAllDay { value.isAllDay = draft.isAllDay }
            if original.timeZoneID != draft.timeZoneID { value.timeZoneID = draft.timeZoneID }
            if original.startDate != draft.startDate {
                value.startDate = draft.startDate == nil ? nil : value.startDate?.addingTimeInterval(shift)
                value.occurrenceDate = value.occurrenceDate?.addingTimeInterval(shift)
                value.excludedOccurrences = value.excludedOccurrences?.map { $0.addingTimeInterval(shift) }
            }
            if original.durationMinutes != draft.durationMinutes { value.durationMinutes = draft.durationMinutes }
            value.plannedEndDate = value.startDate.map { $0.addingTimeInterval(Double(value.durationMinutes * 60)) }
            if original.dueDate != draft.dueDate {
                if let new = draft.dueDate, let old = original.dueDate { value.dueDate = value.dueDate?.addingTimeInterval(new.timeIntervalSince(old)) }
                else { value.dueDate = draft.dueDate }
            }
            TaskEngine.updateTask(value, in: &state)
        }
        if draft.repeatRule == nil { state.managedTasks[rootIndex].excludedOccurrences = nil }
        save()
    }

    func recordTaskUndo() { if pendingUndo == nil { pendingUndo = state.managedTasks } }
    func undoTaskAction() {
        if let text = NSApp?.keyWindow?.firstResponder as? NSTextView, text.undoManager?.canUndo == true { text.undoManager?.undo(); return }
        guard let entry = undoEntries.popLast() else { return }
        state.managedTasks = entry.applying(to: state.managedTasks, reverse: true)
        redoEntries.append(entry); save(); updateUndoAvailability()
    }
    func redoTaskAction() {
        if let text = NSApp?.keyWindow?.firstResponder as? NSTextView, text.undoManager?.canRedo == true { text.undoManager?.redo(); return }
        guard let entry = redoEntries.popLast() else { return }
        state.managedTasks = entry.applying(to: state.managedTasks, reverse: false)
        undoEntries.append(entry); save(); updateUndoAvailability()
    }
    private func updateUndoAvailability() { canUndo = !undoEntries.isEmpty; canRedo = !redoEntries.isEmpty }
    func bulkEdit(_ ids: Set<UUID>, change: (inout ManagedTask) -> Void) {
        recordTaskUndo()
        for id in ids {
            materialize(id)
            if var value = task(id: id) { change(&value); TaskEngine.updateTask(value, in: &state) }
        }
        save()
    }
    func bulkTrash(_ ids: Set<UUID>) {
        recordTaskUndo()
        for id in ids { materialize(id); TaskEngine.trash(id, in: &state) }
        planner.selectedIDs = []; selectedTaskID = nil; save()
    }
    func bulkComplete(_ ids: Set<UUID>, completed: Bool = true) {
        recordTaskUndo()
        for id in ids { materialize(id); TaskEngine.setCompleted(id, completed: completed, in: &state) }
        save()
    }
    func reorderTask(_ id: UUID, before target: UUID) {
        guard id != target else { return }; recordTaskUndo()
        var ordered = state.managedTasks.sorted { $0.sortOrder < $1.sortOrder }.map(\.id)
        ordered.removeAll { $0 == id }
        guard let destination = ordered.firstIndex(of: target) else { pendingUndo = nil; return }
        ordered.insert(id, at: destination)
        let positions = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element, Int64($0.offset)) })
        for index in state.managedTasks.indices { state.managedTasks[index].sortOrder = positions[state.managedTasks[index].id] ?? 0 }
        planner.sort = .manual; save()
    }
    func addSubtask(to parent: UUID, title: String) {
        guard task(id: parent) != nil else { return }; recordTaskUndo()
        let parentID = editableOccurrenceID(parent)
        guard let root = task(id: parentID) else { pendingUndo = nil; return }
        if let id = TaskEngine.addTask(title: title, listID: root.listID, to: &state), let i = state.managedTasks.firstIndex(where: { $0.id == id }) { state.managedTasks[i].parentTaskID = parentID }
        save()
    }
    func editSeries(_ id: UUID, change: (inout ManagedTask) -> Void) {
        guard let occurrence = task(id: id) else { return }
        let rootID = occurrence.seriesRootID ?? id
        recordTaskUndo()
        if var root = task(id: rootID) { change(&root); TaskEngine.updateTask(root, in: &state) }
        for index in state.managedTasks.indices where state.managedTasks[index].seriesRootID == rootID && state.managedTasks[index].status == .active {
            var value = state.managedTasks[index]; change(&value); TaskEngine.updateTask(value, in: &state)
        }
        save()
    }

    var scheduledManagedTasks: [ManagedTask] {
        state.managedTasks.filter { $0.status != .trashed && $0.startDate != nil }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    func matrixTasks(in quadrant: EisenhowerQuadrant) -> [ManagedTask] {
        state.managedTasks.filter {
            ($0.status == .active || (planner.filter.showCompleted && $0.status == .completed))
                && $0.quadrant == quadrant
        }.sorted { $0.sortOrder < $1.sortOrder }
    }

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
        guard let selectedGroupID else { return groups.first }
        return groups.first { $0.id == selectedGroupID }
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
        guard enabled, !state.protectionEnabled else { return }
        state.protectionEnabled = true
        state.disciplineLastCountedDayKey = DayKey.make(from: Date())
        appendEvent(.taskSync, "Защита включена.")
        saveAndApply()
    }

    func disableProtection() {
        guard state.protectionEnabled else { return }
        let lostStreak = state.disciplineStreak
        state.protectionEnabled = false
        state.disciplineStreak = 0
        state.disciplineLastCountedDayKey = DayKey.make(from: Date())
        for index in state.habits.indices {
            state.habits[index].resetCurrentStreak()
        }
        let streak = RussianPluralizer.phrase(lostStreak, one: "день", few: "дня", many: "дней")
        appendEvent(.protectionDisabled, "Защита отключена. Серия \(streak) без отключения и текущие серии привычек обнулены.")
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
        state.pendingGroupRules?.removeValue(forKey: id)
        if selectedGroupID == id { selectedGroupID = state.groups.first?.id }
        saveAndApply()
    }

    private func editGroup(_ id: UUID, change: (inout BlockGroup) throws -> Void) rethrows {
        guard let index = state.groups.firstIndex(where: { $0.id == id }) else { return }
        var group = state.pendingGroupRules?[id] ?? state.groups[index]
        try change(&group)
        if state.groups[index].isEnabled {
            if state.pendingGroupRules == nil { state.pendingGroupRules = [:] }
            state.pendingGroupRules?[id] = group; save()
        } else { state.groups[index] = group; state.pendingGroupRules?.removeValue(forKey: id); saveAndApply() }
    }
    func hasPendingGroupRule(_ id: UUID) -> Bool { state.pendingGroupRules?[id] != nil }
    func applyGroupRule(_ id: UUID) {
        guard let draft = state.pendingGroupRules?[id], let index = state.groups.firstIndex(where: { $0.id == id }) else { return }
        state.groups[index] = draft; state.pendingGroupRules?.removeValue(forKey: id); saveAndApply()
    }
    func discardGroupRule(_ id: UUID) { state.pendingGroupRules?.removeValue(forKey: id); save() }
    func groupStatusExplanation(_ id: UUID) -> String {
        guard let group = state.groups.first(where: { $0.id == id }) else { return "Группа не найдена" }
        if !group.isEnabled { return "Черновик. Правило не применяется." }
        if !state.protectionEnabled { return "Защита выключена." }
        if group.accessMode.usesSchedule && !group.schedule.isActive() { return "Открыта вне расписания блокировки: \(group.schedule.timeDescription)." }
        if group.accessMode == .schedule { return "Закрыта по расписанию: \(group.schedule.timeDescription)." }
        let remaining = remainingTaskCount(for: group)
        if groupIsUnlocked(group) { return "Открыта: назначенные задачи выполнены." }
        return remaining > 0 ? "Закрыта до выполнения назначенных задач. Осталось: \(remaining)." : "Закрыта: доступные назначенные задачи отсутствуют."
    }
    func updateGroupName(_ id: UUID, name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }; editGroup(id) { $0.name = value }
    }
    func setGroupUsesAllTasks(_ id: UUID, value: Bool) { editGroup(id) { $0.requiresAllTodayTasks = value; if value { $0.requiredTaskIDs.removeAll() } } }
    func setGroupEnabled(_ id: UUID, value: Bool) {
        guard let index = state.groups.firstIndex(where: { $0.id == id }) else { return }
        if value, let draft = state.pendingGroupRules?[id] { state.groups[index] = draft }
        state.pendingGroupRules?.removeValue(forKey: id)
        state.groups[index].isEnabled = value; saveAndApply()
    }
    func setGroupAccessMode(_ id: UUID, mode: GroupAccessMode) { editGroup(id) { $0.accessMode = mode } }
    func updateGroupSchedule(_ id: UUID, schedule: BlockSchedule) { editGroup(id) { $0.schedule = schedule } }
    func toggleRequiredTask(_ taskID: String, in groupID: UUID) {
        editGroup(groupID) { group in
            if group.requiredTaskIDs.contains(taskID) { group.requiredTaskIDs.remove(taskID) } else { group.requiredTaskIDs.insert(taskID) }
        }
    }
    func setRequiredTasks(_ taskIDs: Set<String>, in groupID: UUID) { editGroup(groupID) { $0.requiredTaskIDs = taskIDs } }

    func addDomain(_ rawDomain: String, displayName: String, to groupID: UUID) throws {
        try editGroup(groupID) { group in
            let domain = LocalRulesServer.normalizedDomain(rawDomain)
            guard domain.contains("."), !domain.contains(" ") else { throw AppError.invalidDomain }
            guard !group.resources.contains(where: { $0.kind == .domain && $0.identifier == domain }) else { throw AppError.duplicateResource }
            let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            group.resources.append(BlockedResource(kind: .domain, displayName: name.isEmpty ? domain : name, identifier: domain))
        }
    }

    func addApplication(at url: URL, to groupID: UUID) throws {
        try editGroup(groupID) { group in
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { throw AppError.invalidApplication }
            guard !group.resources.contains(where: { $0.kind == .application && $0.identifier == bundleID }) else { throw AppError.duplicateResource }
            let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            group.resources.append(BlockedResource(kind: .application, displayName: displayName, identifier: bundleID, path: url.path))
        }
    }

    func removeResource(_ resourceID: UUID, from groupID: UUID) {
        editGroup(groupID) { $0.resources.removeAll { $0.id == resourceID } }
    }

    func updateResource(_ resourceID: UUID, in groupID: UUID, displayName rawName: String, identifier rawIdentifier: String) throws {
        try editGroup(groupID) { group in
            guard let resourceIndex = group.resources.firstIndex(where: { $0.id == resourceID }) else { return }
            let existing = group.resources[resourceIndex]
            let identifier: String
            switch existing.kind {
            case .domain:
                identifier = LocalRulesServer.normalizedDomain(rawIdentifier)
                guard identifier.contains("."), !identifier.contains(" ") else { throw AppError.invalidDomain }
            case .application:
                identifier = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !identifier.isEmpty, !identifier.contains(" ") else { throw AppError.invalidApplication }
            }
            guard !group.resources.contains(where: { $0.id != resourceID && $0.kind == existing.kind && $0.identifier == identifier }) else { throw AppError.duplicateResource }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            group.resources[resourceIndex].displayName = name.isEmpty ? identifier : name
            group.resources[resourceIndex].identifier = identifier
        }
    }


    func addHabit(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        state.habits.append(Habit(name: name))
        save()
    }

    func addHabit(_ habit: Habit) {
        var value = habit
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { return }
        state.habits.append(value)
        save()
    }

    func updateHabit(_ habit: Habit) {
        guard let index = state.habits.firstIndex(where: { $0.id == habit.id }) else { return }
        var value = habit
        value.name = value.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.name.isEmpty else { return }
        state.habits[index] = value
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

    @discardableResult
    func createPlannerTask(_ draft: ManagedTask) -> UUID? {
        recordTaskUndo()
        let list = state.taskLists.contains(where: { $0.id == draft.listID }) ? draft.listID : TaskList.inboxID
        guard let id = TaskEngine.addTask(title: draft.title, listID: list, to: &state), let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { pendingUndo = nil; return nil }
        var value = draft; value.id = id; value.listID = list; value.sortOrder = state.managedTasks[index].sortOrder
        state.managedTasks[index] = value; selectedTaskID = id; save(); return id
    }

    @discardableResult
    func addManagedTask(named title: String, listID: UUID? = nil) -> UUID? {
        recordTaskUndo()
        let targetList = listID ?? {
            if case .list(let id) = taskSidebarSelection { return id }
            return TaskList.inboxID
        }()
        let id = TaskEngine.addTask(title: title, listID: targetList, to: &state)
        selectedTaskID = id
        save()
        return id
    }

    func updateManagedTask(_ task: ManagedTask) {
        recordTaskUndo()
        materialize(task.id)
        TaskEngine.updateTask(task, in: &state)
        save()
    }

    func updateManagedTaskEdits(from original: ManagedTask, to draft: ManagedTask) {
        recordTaskUndo()
        let id = editableOccurrenceID(draft.id)
        var before = original, after = draft; before.id = id; after.id = id
        if id != draft.id { before.repeatRule = nil; after.repeatRule = nil }
        TaskEngine.applyEdits(from: before, to: after, in: &state)
        save()
    }

    func setManagedTaskCompleted(_ id: UUID, completed: Bool) {
        recordTaskUndo()
        materialize(id)
        TaskEngine.setCompleted(id, completed: completed, in: &state)
        save()
    }

    func duplicateManagedTask(_ id: UUID) {
        recordTaskUndo()
        materialize(id)
        if TaskEngine.duplicate(id, in: &state) != nil { save() }
    }

    func trashManagedTask(_ id: UUID) {
        recordTaskUndo()
        let target = editableOccurrenceID(id)
        TaskEngine.trash(target, in: &state)
        if selectedTaskID == id { selectedTaskID = nil }
        save()
    }

    func restoreManagedTask(_ id: UUID) {
        recordTaskUndo()
        materialize(id)
        TaskEngine.restoreFromTrash(id, in: &state)
        save()
    }

    func permanentlyDeleteManagedTask(_ id: UUID) {
        TaskEngine.permanentlyDelete(id, in: &state)
        if selectedTaskID == id { selectedTaskID = nil }
        save()
    }

    func scheduleManagedTask(_ id: UUID, at date: Date?, durationMinutes: Int? = nil, allDay: Bool? = nil) {
        recordTaskUndo()
        let target = editableOccurrenceID(id)
        TaskEngine.schedule(target, at: date, durationMinutes: durationMinutes, allDay: allDay, in: &state)
        save()
    }

    func setTaskQuadrant(_ id: UUID, _ quadrant: EisenhowerQuadrant) {
        recordTaskUndo()
        materialize(id)
        TaskEngine.setQuadrant(id, quadrant: quadrant, in: &state)
        save()
    }

    func reorderList(_ id: UUID, before target: UUID) {
        var ordered = taskLists.map(\.id); ordered.removeAll { $0 == id }
        guard id != target, let destination = ordered.firstIndex(of: target) else { return }
        ordered.insert(id, at: destination)
        for (order, listID) in ordered.enumerated() {
            if let index = state.taskLists.firstIndex(where: { $0.id == listID }) { state.taskLists[index].sortOrder = Int64(order) }
        }
        save()
    }

    func addTaskFolder(named rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        state.taskFolders.append(TaskFolder(name: name, sortOrder: (state.taskFolders.map(\.sortOrder).max() ?? 0) + 1))
        save()
    }

    func toggleTaskFolder(_ id: UUID) {
        guard let index = state.taskFolders.firstIndex(where: { $0.id == id }) else { return }
        state.taskFolders[index].isCollapsed.toggle()
        save()
    }

    func addTaskList(named rawName: String, folderID: UUID? = nil) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        state.taskLists.append(TaskList(
            folderID: folderID,
            name: name,
            sortOrder: (state.taskLists.map(\.sortOrder).max() ?? 0) + 1
        ))
        save()
    }

    func startPomodoro(for taskID: UUID) {
        if TaskEngine.startPomodoro(taskID: taskID, in: &state) { save() }
    }

    func startFocus(taskID: UUID? = nil, phase: PomodoroPhase = .work, stopwatch: Bool = false) {
        if TaskEngine.startFocus(taskID: taskID, phase: phase, stopwatch: stopwatch, in: &state) { save() }
    }
    func checkFocusCompletion(now: Date = Date()) {
        guard let active = state.activePomodoro, active.pausedAt == nil, active.isStopwatch != true,
              TaskEngine.focusElapsed(active, now: now) >= active.targetSeconds else { return }
        TaskEngine.finishPomodoro(in: &state, now: now)
        save()
    }
    func pausePomodoro() {
        TaskEngine.pausePomodoro(in: &state)
        save()
    }

    func resumePomodoro() {
        TaskEngine.resumePomodoro(in: &state)
        save()
    }

    func finishPomodoro(completed: Bool = true) {
        TaskEngine.finishPomodoro(in: &state, completed: completed)
        save()
    }

    var activePomodoro: ActivePomodoro? { state.activePomodoro }
    var pomodoroSessions: [PomodoroSession] { state.pomodoroSessions }

    func prepareTickTickImport() async {
        guard connectionState == .connected, !isImportingTickTick else { return }
        isImportingTickTick = true
        defer { isImportingTickTick = false }
        do {
            let start = Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date()
            let snapshot = try await tickTickService.fullImportSnapshot(since: start)
            pendingTickTickImport = snapshot
            tickTickImportPreview = snapshot.preview
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func performPreparedTickTickImport() {
        guard let snapshot = pendingTickTickImport else { return }
        do {
            writer.flush()
            _ = try repository.createBackup()
            _ = TaskEngine.importTickTick(
                folders: snapshot.folders,
                lists: snapshot.lists,
                records: snapshot.records,
                into: &state, completeSnapshot: true
            )
            save()
            pendingTickTickImport = nil
            tickTickImportPreview = nil
        } catch {
            errorMessage = "Импорт остановлен: не удалось создать резервную копию. \(error.localizedDescription)"
        }
    }

    func connectGoogleCalendar(clientID: String, clientSecret: String?) async {
        guard !isGoogleSynchronizing else { return }
        isGoogleSynchronizing = true
        defer { isGoogleSynchronizing = false }
        do {
            UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "googleOAuthClientID")
            try await googleCalendarService.authorize(clientID: clientID, clientSecret: clientSecret)
            googleCalendars = try await googleCalendarService.calendars()
            state.googleCalendarConnection.isConnected = true
            state.googleCalendarConnection.lastSyncError = nil
            save()
        } catch {
            state.googleCalendarConnection.isConnected = false
            state.googleCalendarConnection.lastSyncError = error.localizedDescription
            errorMessage = error.localizedDescription
            save()
        }
    }

    func disconnectGoogleCalendar() {
        googleCalendarService.disconnect()
        googleCalendars = []
        googleCalendarEvents = []
        state.googleCalendarConnection = GoogleCalendarConnection()
        save()
    }

    func setGoogleCalendarSelected(_ id: String, selected: Bool) {
        if selected { state.googleCalendarConnection.selectedCalendarIDs.insert(id) }
        else { state.googleCalendarConnection.selectedCalendarIDs.remove(id) }
        save()
    }

    func refreshGoogleCalendars() async {
        guard state.googleCalendarConnection.isConnected, !isGoogleSynchronizing else { return }
        isGoogleSynchronizing = true
        defer { isGoogleSynchronizing = false }
        do {
            googleCalendars = try await googleCalendarService.calendars()
            try await synchronizeGoogleCalendar()
            state.googleCalendarConnection.lastSuccessfulSync = Date()
            state.googleCalendarConnection.lastSyncError = nil
        } catch {
            state.googleCalendarConnection.lastSyncError = error.localizedDescription
            errorMessage = error.localizedDescription
        }
        save()
    }

    func linkTaskToGoogle(_ taskID: UUID, calendarID: String) async {
        guard let index = state.managedTasks.firstIndex(where: { $0.id == taskID }),
              state.managedTasks[index].startDate != nil else { return }
        do {
            let event = try await googleCalendarService.createEvent(from: state.managedTasks[index], calendarID: calendarID)
            if let current = state.managedTasks.firstIndex(where: { $0.id == taskID }) {
                GoogleSyncEngine.markRemoteSaved(event, on: &state.managedTasks[current])
            }
            save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unlinkTaskFromGoogle(_ taskID: UUID) {
        guard let index = state.managedTasks.firstIndex(where: { $0.id == taskID }) else { return }
        GoogleSyncEngine.unlink(&state.managedTasks[index])
        save()
    }

    private func synchronizeGoogleCalendar() async throws {
        let calendarIDs = state.googleCalendarConnection.selectedCalendarIDs
        guard !calendarIDs.isEmpty else { return }
        let start = Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date()
        let end = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
        var eventsByID: [String: GoogleCalendarEventSnapshot] = [:]
        for calendarID in calendarIDs {
            for event in try await googleCalendarService.events(calendarID: calendarID, from: start, to: end) {
                eventsByID[event.identity] = event
            }
        }
        googleCalendarEvents = Array(eventsByID.values)

        let linkedIDs = state.managedTasks.filter { $0.googleEventID != nil }.map(\.id)
        for id in linkedIDs {
            guard let initial = task(id: id), let eventID = initial.googleEventID, let calendarID = initial.googleCalendarID,
                  calendarIDs.contains(calendarID) else { continue }
            let key = "google:\(calendarID):\(eventID)"
            var remote = eventsByID[key]
            if remote == nil { remote = try await googleCalendarService.event(calendarID: calendarID, eventID: eventID) }
            guard let index = state.managedTasks.firstIndex(where: { $0.id == id }), state.managedTasks[index].googleEventID == eventID else { continue }
            let sent = state.managedTasks[index]
            switch GoogleSyncEngine.decision(for: sent, remote: remote) {
            case .updateLocal, .conflictPreferRemote:
                if let remote { GoogleSyncEngine.applyRemote(remote, to: &state.managedTasks[index]) }
            case .updateRemote, .conflictPreferLocal:
                do {
                    let saved = try await googleCalendarService.updateEvent(from: sent, calendarID: calendarID, eventID: eventID)
                    if let current = state.managedTasks.firstIndex(where: { $0.id == id && $0.googleEventID == eventID }) {
                        GoogleSyncEngine.markRemoteSaved(saved, on: &state.managedTasks[current], syncedAt: sent.modifiedAt)
                    }
                    eventsByID[key] = saved
                } catch GoogleCalendarError.api(let status, _) where status == 412 {
                    // Refresh after a conditional-write conflict; a later cycle decides again.
                    if let fresh = try await googleCalendarService.event(calendarID: calendarID, eventID: eventID) { eventsByID[key] = fresh }
                    throw GoogleCalendarError.api(412, "Событие изменено в Google. Данные перечитаны; повторите синхронизацию.")
                }
            case .unlinkDeletedRemote: GoogleSyncEngine.unlink(&state.managedTasks[index])
            case .createRemote, .unchanged: break
            }
        }
        googleCalendarEvents = Array(eventsByID.values)

    }

    func undoHabitCheck() {
        guard let (before, after) = habitUndo, let index = state.habits.firstIndex(where: { $0.id == after.id }), state.habits[index] == after else { return }
        state.habits[index] = before; habitUndo = nil; canUndoHabit = false; save()
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
        guard state.habits[index].isScheduled(on: target) else {
            errorMessage = "На этот день привычка не запланирована."
            return
        }
        let before = state.habits[index]
        state.habits[index].toggle(on: target)
        habitUndo = (before, state.habits[index]); canUndoHabit = true
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
        if connection == .connected { await performTaskSynchronization() }
        isSynchronizing = false
    }

    func connectTickTick() async {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        connectionState = .connecting
        do {
            try await tickTickService.authenticate()
            connectionState = await tickTickService.connectionState()
            if connectionState == .connected { await performTaskSynchronization() }
        } catch {
            connectionState = .failed(error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func synchronizeTasks() async {
        guard connectionState == .connected, !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        await performTaskSynchronization()
    }
    private func performTaskSynchronization() async {
        do {
            let tasks = try await tickTickService.todayTasks()
            if state.managedTasks.contains(where: { $0.sourceName == "TickTick" }) {
                var since = state.lastPlannerSyncAt.map { $0.addingTimeInterval(-86400) }
                    ?? Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date()
                let repairsHierarchy = state.tickTickHierarchyVersion != 2
                if repairsHierarchy {
                    since = min(since, state.managedTasks.filter { $0.sourceName == "TickTick" }.compactMap(\.completedAt).min() ?? since)
                }
                let snapshot = try await tickTickService.fullImportSnapshot(since: since, knownTaskSourceIDs: Set(state.managedTasks.compactMap(\.sourceID)))
                if state.lastPlannerSyncAt == nil || repairsHierarchy { writer.flush(); _ = try repository.createBackup(label: "before-planner-reconciliation") }
                _ = TaskEngine.importTickTick(folders: snapshot.folders, lists: snapshot.lists,
                                             records: snapshot.records, into: &state, completeSnapshot: true)
                state.tickTickHierarchyVersion = 2
                state.lastPlannerSyncAt = Date()
            }
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
        flushJournalWrites()
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
        journalRevision += 1
        let revision = journalRevision
        pendingJournalValue = (value, entry, revision)
        pendingJournalSave?.cancel()
        pendingJournalSave = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 350_000_000) } catch { return }
            self?.enqueueJournalWrite()
        }
    }
    private func enqueueJournalWrite() {
        guard let (value, entry, revision) = pendingJournalValue else { return }
        pendingJournalValue = nil
        journalWriter.async { [journalRepository, weak self] in
            let result = Result { try journalRepository.write(value, to: entry) }
            Task { @MainActor in
                guard let self, revision == self.journalRevision, self.selectedJournalEntry?.id == entry.id else { return }
                switch result {
                case .success: self.journalSaveState = .saved(Date())
                case .failure(let error): self.journalSaveState = .failed; self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    private func flushJournalWrites() {
        pendingJournalSave?.cancel(); enqueueJournalWrite(); journalWriter.sync {}
    }

    func retryJournalSave() { updateJournalDraft(journalDraft); flushJournalWrites() }

    func renameSelectedJournalEntry() {
        guard let entry = selectedJournalEntry else { return }
        flushJournalWrites()
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
        rollDisciplineForward()
        let day = Calendar.current.startOfDay(for: Date())
        if day != lastReminderDay { lastReminderDay = day; reminderService.refresh(state.managedTasks) }
        Task {
            await refreshConnectionAndTasks()
            updateBlockingRules()
            evaluateRunningApplications()
        }
    }

    @objc private func workspaceApplicationChanged(_ notification: Notification) {
        rollDisciplineForward()
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
        if state.advanceProtectionDays() { save() }
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
        guard servicesEnabled else { return }
        updateBlockingRules()
        evaluateRunningApplications()
    }

    func save() {
        guard !persistenceFailedToLoad else { return }
        if let before = pendingUndo {
            if before != state.managedTasks {
                undoEntries.append(TaskHistoryEntry(before: before, after: state.managedTasks))
                if undoEntries.count > 50 { undoEntries.removeFirst() }
                redoEntries.removeAll()
            }
            pendingUndo = nil; updateUndoAvailability()
        }
        if indexedTasks != state.managedTasks {
            indexedTasks = state.managedTasks; rebuildTaskPositions(); calendarIndex.replaceTasks(indexedTasks); calendarFallbackDays.removeAll(keepingCapacity: true); indexRequestedAnchor = nil; indexBuild?.cancel(); indexBuild = nil; indexRequest += 1
            if virtualTasks.count > 50_000 {
                let selectedVirtual = selectedTaskID.flatMap { virtualTasks[$0] }
                virtualTasks.removeAll()
                if let selectedVirtual { virtualTasks[selectedVirtual.id] = selectedVirtual }
            }
            reminderService.refresh(state.managedTasks)
        }
        prepareCalendarIndex()
        saveRevision += 1
        let revision = saveRevision
        taskSaveState = .saving
        writer.enqueue(state, revision: revision) { [weak self] revision, result in
            Task { @MainActor in
                guard let self, revision == self.saveRevision else { return }
                switch result {
                case .success: self.taskSaveState = .saved(Date())
                case .failure(let error): self.taskSaveState = .failed; self.errorMessage = "Не удалось сохранить данные: \(error.localizedDescription)"
                }
            }
        }
    }
    @objc private func flushBeforeTermination() { writer.flush(); flushJournalWrites() }
    func flushPendingWrites() { writer.flush(); flushJournalWrites() }

}
