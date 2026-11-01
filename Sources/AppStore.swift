import AppKit
import Combine
import Foundation

@MainActor
final class AppStore: NSObject, ObservableObject {
    let journal = JournalState()
    let focusPresentation = FocusPresentationState()
    let saving = SaveState()
    let integration = IntegrationState()

    @Published var selectedSection: AppSection = .groups
    @Published private(set) var state: PersistedAppState
    private(set) var connectionState: TickTickConnectionState { get { integration.connectionState } set { integration.connectionState = newValue } }
    private(set) var journalEntries: [JournalEntry] { get { journal.journalEntries } set { journal.journalEntries = newValue } }
    private(set) var selectedJournalEntry: JournalEntry? { get { journal.selectedJournalEntry } set { journal.selectedJournalEntry = newValue } }
    private(set) var journalDraft: String { get { journal.journalDraft } set { journal.journalDraft = newValue } }
    var journalTitleDraft: String { get { journal.journalTitleDraft } set { journal.journalTitleDraft = newValue } }
    @Published var selectedGroupID: UUID?
    @Published var selectedTaskID: UUID?
    @Published var pendingTaskDeletion: Set<UUID> = []
    @Published var pendingProtectedResourceChange: ProtectedResourceChange?
    @Published var taskSidebarSelection: TaskSidebarSelection = .today
    let planner: PlannerWorkspace
    let reminderService = TaskReminderService()
    var tasksPresentation: TasksPresentation { get { planner.presentation } set { planner.presentation = newValue } }
    var taskCalendarMode: TaskCalendarMode { get { planner.mode } set { planner.mode = newValue } }
    var taskCalendarAnchor: Date { get { planner.anchor } set { planner.anchor = newValue } }
    private(set) var taskSaveState: JournalSaveState { get { saving.taskSaveState } set { saving.taskSaveState = newValue } }
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
    private var taskDataRevision: UInt64 = 0
    private let projectionCache = PlannerProjectionCache()
    var taskProjectionPreparationCount: Int { projectionCache.preparationCount }
    private var cachedCalendarContext: Calendar?
    private var calendarEventRevision: UInt64 = 0
    private var daySnapshotCache: [(PlannerDaySnapshotKey, PlannerDaySnapshot)] = []
    private var eventDayCache: [(Date, Calendar, PlannerFilter, String, UInt64, [GoogleCalendarEventSnapshot])] = []
    private var indexedTasks: [ManagedTask] = []
    private var taskPositions: [UUID: Int] = [:]
    private var listPositions: [UUID: Int] = [:]
    private var countCache: [TaskSidebarSelection: Int] = [:]
    private var visibleTasksCache: [TaskSidebarSelection: [ManagedTask]] = [:]
    private var visibleTasksCalendar: Calendar?
    private var countCalendar: Calendar?
    private var visibleTasksCacheDay: Date?
    private var visibleTasksCacheCompleted: Bool?
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
    private let journalWriteReceipt = HidigWriteReceipt()
    private let journalWriter = DispatchQueue(label: "hidigFocus.journal", qos: .utility)
    private var lastReminderDay = Calendar.current.startOfDay(for: Date())
    private var pendingJournalSave: Task<Void, Never>?
    private var pendingJournalValue: (String, JournalEntry, Int)?
    private var journalRevision = 0
    @Published var errorMessage: String?
    private(set) var isSynchronizing: Bool { get { integration.isSynchronizing } set { integration.isSynchronizing = newValue } }
    private(set) var browserExtensionLastContact: Date? { get { integration.browserExtensionLastContact } set { integration.browserExtensionLastContact = newValue } }
    private(set) var safariExtensionLastContact: Date? { get { integration.safariExtensionLastContact } set { integration.safariExtensionLastContact = newValue } }
    private(set) var journalSaveState: JournalSaveState { get { journal.journalSaveState } set { journal.journalSaveState = newValue } }
    private(set) var googleCalendars: [GoogleCalendarDescriptor] { get { integration.googleCalendars } set { integration.googleCalendars = newValue } }
    @Published private(set) var googleCalendarEvents: [GoogleCalendarEventSnapshot] = [] { didSet { calendarEventRevision &+= 1; eventDayCache.removeAll(keepingCapacity: true) } }
    private(set) var isGoogleSynchronizing: Bool { get { integration.isGoogleSynchronizing } set { integration.isGoogleSynchronizing = newValue } }
    private(set) var tickTickImportPreview: TaskImportPreview? { get { integration.tickTickImportPreview } set { integration.tickTickImportPreview = newValue } }
    private(set) var isImportingTickTick: Bool { get { integration.isImportingTickTick } set { integration.isImportingTickTick = newValue } }

    private let requestedServicesEnabled: Bool
    private var servicesEnabled: Bool { requestedServicesEnabled && !persistenceFailedToLoad }
    var dataIsReadOnly: Bool { persistenceFailedToLoad }
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
        self.init(repository: AppStateRepository(), startServices: HidigRuntime.servicesAllowed)
    }
    init(repository: AppStateRepository, startServices: Bool = true, plannerDefaults: UserDefaults = HidigRuntime.defaults) {
        self.planner = PlannerWorkspace(defaults: plannerDefaults)
        self.requestedServicesEnabled = startServices && HidigRuntime.servicesAllowed
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
        if servicesEnabled {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in self?.checkFocusCompletion() }
            }
            focusTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        if HidigRuntime.environment["HIDIGFOCUS_QA"] == "1", state.managedTasks.isEmpty,
           let count = HidigRuntime.environment["HIDIGFOCUS_QA_TASKS"].flatMap(Int.init) {
            let seriesCount = HidigRuntime.environment["HIDIGFOCUS_QA_SERIES"].flatMap(Int.init)
            state = PlannerFixtures.make(count: count, seriesCount: seriesCount)
        }
        if HidigRuntime.environment["HIDIGFOCUS_QA"] == "1" {
            selectedSection = .tasks; planner.presentation = .calendar; planner.mode = .fourDays; planner.anchor = Date()
        }
        writer = SaveCoordinator(repository: repository)
        persistenceFailedToLoad = loadError != nil
        indexedTasks = state.managedTasks
        rebuildTaskPositions()
        calendarIndex.replaceTasks(indexedTasks)
        if !persistenceFailedToLoad { reminderService.refresh(state.managedTasks) }
        errorMessage = loadError
        NotificationCenter.default.addObserver(self, selector: #selector(flushBeforeTermination), name: NSApplication.willTerminateNotification, object: nil)
        selectedGroupID = state.groups.first?.id
        rollDisciplineForward()
        loadJournalEntries(selectNewest: true)
        if servicesEnabled {
            startRulesServer(); beginApplicationMonitoring(); updateBlockingRules(); scheduleLocalMaintenance()
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
        let calendar = PlannerCalendar.current
        let first = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: .day, value: 1, to: first) ?? first.addingTimeInterval(86400)
        let lists = Dictionary(uniqueKeysWithValues: state.taskLists.map { ($0.id, $0) })
        let tasks = RecurrenceProjection.tasks(state.managedTasks, from: first, to: end)
            .filter { $0.status != .trashed && $0.status != .wontDo }
        let managed = tasks.map { task in
            TickTickTask(id: task.sourceID ?? task.id.uuidString,
                         projectID: task.listID.uuidString,
                         projectName: lists[task.listID]?.name ?? "hidigFocus",
                         title: task.title, dueDate: task.startDate ?? task.dueDate,
                         completedAt: task.completedAt, status: task.status == .completed ? 2 : 0)
        }
        let local = state.localTasks.filter { $0.dayKey == DayKey.make(from: first) }.map(\.asTask)
        // Retain legacy group selections without requiring a live account. Managed
        // tasks always win over the old import cache, including locally rescheduled ones.
        let importedIDs = Set(state.managedTasks.compactMap(\.sourceID))
        let legacy = state.cachedTasks.filter {
            !importedIDs.contains($0.id) && $0.dueDate.map { calendar.isDate($0, inSameDayAs: first) } == true
        }
        return local + managed + legacy
    }

    var groups: [BlockGroup] { state.groups.map { state.pendingGroupRules?[$0.id] ?? $0 } }
    /// Access indicators use the applied rule; the editor may contain an unapplied draft.
    func appliedGroup(_ id: UUID) -> BlockGroup? { state.groups.first { $0.id == id } }
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

    /// The board needs the complete saved task set when it groups cards by project
    /// or shows archive/trash independently from the current sidebar selection.
    var kanbanManagedTasks: [ManagedTask] { state.managedTasks.map(TaskSeriesEditing.displayedRoot) }

    private func projectionKey(search: String, kind: String, collapsed: Set<UUID> = [], now: Date) -> PlannerProjectionKey {
        let calendar = PlannerCalendar.current
        return PlannerProjectionKey(revision: taskDataRevision, selection: taskSidebarSelection,
            filter: planner.filter, sort: planner.sort, search: search, calendar: calendar,
            day: calendar.startOfDay(for: now), kind: kind, collapsed: collapsed)
    }

    func plannerKanbanSnapshot(search: String, scope: String, allProjects: Bool, now: Date = Date()) -> PlannerTaskSnapshot {
        let key = projectionKey(search: search, kind: "kanban.\(scope).\(allProjects)", now: now)
        return projectionCache.value(for: key, now: now) {
            let source = !allProjects && scope == "active" ? visibleManagedTasks : kanbanManagedTasks
            let tasks = planner.filter.sorted(source.filter { task in
                let belongs = scope == "trash" ? task.status == .trashed : (scope == "archive" ? task.status == .completed || task.status == .wontDo : task.status == .active)
                return belongs && plannerMatches(task, search: search, includeTrash: scope == "trash", includeCompleted: scope == "archive")
            }, by: planner.sort)
            var snapshot = PlannerTaskSnapshot(tasks: tasks)
            for task in tasks {
                snapshot.byProject[task.listID, default: []].append(task)
                snapshot.byStage[task.effectiveKanbanStage, default: []].append(task)
                snapshot.byStatus[task.status, default: []].append(task)
            }
            return snapshot
        }
    }

    func plannerListSnapshot(search: String, collapsed: Set<UUID>, now: Date = Date()) -> PlannerTaskSnapshot {
        let key = projectionKey(search: search, kind: "list", collapsed: collapsed, now: now)
        return projectionCache.value(for: key, now: now) {
            var matching = visibleManagedTasks.filter {
                plannerMatches($0, search: search, includeTrash: taskSidebarSelection == .trash, includeCompleted: taskSidebarSelection == .completed)
            }
            var included = Set(matching.map(\.id))
            for child in matching {
                var parentID = child.parentTaskID
                while let id = parentID, let parent = task(id: id), parent.status == .wontDo, included.insert(id).inserted {
                    matching.append(parent); parentID = parent.parentTaskID
                }
            }
            let ordered = planner.filter.sorted(matching, by: planner.sort)
            let rows = PlannerTaskTree.rows(ordered, collapsed: collapsed)
            let groups = planner.sort == .date ? Dictionary(grouping: rows) { row -> String in
                let task = row.root
                guard let date = task.dueDate ?? task.startDate else { return "Без срока" }
                if task.status == .active && task.dueDate != nil && (task.isAllDay ? date < key.day : date < now) { return "Просрочено" }
                return key.calendar.isDate(date, inSameDayAs: now) ? "Сегодня" : "Предстоящие"
            } : ["Задачи": rows]
            return PlannerTaskSnapshot(tasks: ordered, rows: rows, groupedRows: groups)
        }
    }

    private func tasks(for selection: TaskSidebarSelection) -> [ManagedTask] {
        let calendar = PlannerCalendar.current
        let start = calendar.startOfDay(for: Date())
        if visibleTasksCalendar != calendar || visibleTasksCacheDay != start || visibleTasksCacheCompleted != planner.filter.showCompleted {
            visibleTasksCache.removeAll(keepingCapacity: true)
            visibleTasksCalendar = calendar
            visibleTasksCacheDay = start
            visibleTasksCacheCompleted = planner.filter.showCompleted
        }
        if let cached = visibleTasksCache[selection] { return cached }
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
        let filtered = state.managedTasks.map(TaskSeriesEditing.displayedRoot).filter { task in
            let allowed = task.status == .active || (planner.filter.showCompleted && (task.status == .completed || task.status == .wontDo))
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
                return task.status == .completed || task.status == .wontDo
            case .trash:
                return task.status == .trashed
            }
        }
        let result: [ManagedTask]
        if selection == .completed {
            result = filtered.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
        } else {
        result = filtered.sorted {
            switch ($0.startDate, $1.startDate) {
            case let (left?, right?) where left != right: return left < right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return $0.sortOrder < $1.sortOrder
            }
        }
        }
        visibleTasksCache[selection] = result
        return result
    }

    var unscheduledManagedTasks: [ManagedTask] {
        state.managedTasks.map(TaskSeriesEditing.displayedRoot).filter { $0.status == .active && $0.startDate == nil }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var activeTaskCount: Int { state.managedTasks.filter { $0.status == .active }.count }

    func visibleCount(selection: TaskSidebarSelection) -> Int {
        let calendar = PlannerCalendar.current
        let day = calendar.startOfDay(for: Date())
        if countCalendar != calendar || day != countCacheDay || countCacheCompleted != planner.filter.showCompleted {
            countCache.removeAll(); countCalendar = calendar; countCacheDay = day; countCacheCompleted = planner.filter.showCompleted
        }
        if countCache.isEmpty { rebuildCounts(day: day) }
        return countCache[selection] ?? 0
    }
    private func rebuildCounts(day: Date) {
        let calendar = PlannerCalendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: day) ?? day
        for task in state.managedTasks.map(TaskSeriesEditing.displayedRoot) {
            if task.status == .completed || task.status == .wontDo { countCache[.completed, default: 0] += 1 }
            if task.status == .trashed { countCache[.trash, default: 0] += 1 }
            guard task.status == .active || (countCacheCompleted && (task.status == .completed || task.status == .wontDo)) else { continue }
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

    private func ensureCalendarContext(_ calendar: Calendar) {
        guard cachedCalendarContext != calendar else { return }
        cachedCalendarContext = calendar
        calendarIndex = PlannerCalendarIndex(); calendarIndex.replaceTasks(indexedTasks)
        calendarFallbackDays.removeAll(keepingCapacity: true)
        virtualTasks.removeAll(keepingCapacity: true)
        projectionGeneration = 0; indexRequestedAnchor = nil
        indexBuild?.cancel(); indexBuild = nil; indexRequest &+= 1
    }

    func calendarTasks(on day: Date) -> [ManagedTask] {
        ensureCalendarContext(PlannerCalendar.current)
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
            guard $0.status == .active || $0.status == .completed || $0.status == .wontDo,
                  let start = $0.startDate ?? $0.dueDate else { return false }
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
        let calendar = PlannerCalendar.current
        ensureCalendarContext(calendar)
        let anchor = PlannerCalendar.current.startOfDay(for: date ?? planner.anchor)
        calendarNavigationAnchor = anchor
        let leading = PlannerCalendar.current.date(byAdding: .day, value: -7, to: anchor) ?? anchor
        let visibleDays = planner.mode == .fourDays ? planner.customDayCount : (planner.mode == .week ? 7 : 1)
        let trailingDays = planner.mode == .agenda ? 29 : max(13, visibleDays + 6)
        let trailing = PlannerCalendar.current.date(byAdding: .day, value: trailingDays, to: anchor) ?? anchor
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
                let index = PlannerCalendarIndex(radius: radius); index.replaceTasks(tasks); _ = index.day(anchor, calendar: calendar); return index
            }.value
            guard let self, revision == self.indexRequest, !Task.isCancelled else { return }
            self.calendarIndex = prepared; self.projectionGeneration = 0; self.indexBuild = nil
            self.planner.preparingCalendar = false; self.planner.calendarRevision += 1
        }
    }

    func plannerMatches(_ task: ManagedTask, search: String, includeTrash: Bool = false, includeCompleted: Bool = false) -> Bool {
        planner.filter.matches(task, search: search, includeTrash: includeTrash, includeCompleted: includeCompleted)
    }
    func plannerCalendarTasks(on day: Date, search: String) -> [ManagedTask] {
        plannerDaySnapshot(on: day, search: search).tasks
    }

    func plannerDaySnapshot(on day: Date, search: String) -> PlannerDaySnapshot {
        let calendar = PlannerCalendar.current
        ensureCalendarContext(calendar)
        let first = calendar.startOfDay(for: day)
        let key = PlannerDaySnapshotKey(taskRevision: taskDataRevision, calendarRevision: planner.calendarRevision,
            eventRevision: calendarEventRevision, day: first, calendar: calendar, filter: planner.filter, search: search)
        if let cached = daySnapshotCache.first(where: { $0.0 == key }) { return cached.1 }
        let tasks = calendarTasks(on: first).filter { plannerMatches($0, search: search) }
        let snapshot = PlannerDaySnapshot(tasks: tasks, events: plannerEvents(on: first, search: search), day: first, calendar: calendar)
        if daySnapshotCache.count >= 128 { daySnapshotCache.removeFirst() }
        daySnapshotCache.append((key, snapshot))
        return snapshot
    }

    func plannerEvents(on day: Date, search: String) -> [GoogleCalendarEventSnapshot] {
        let calendar = PlannerCalendar.current
        let first = calendar.startOfDay(for: day)
        if let cached = eventDayCache.first(where: { $0.0 == first && $0.1 == calendar && $0.2 == planner.filter && $0.3 == search && $0.4 == calendarEventRevision }) { return cached.5 }
        let end = calendar.date(byAdding: .day, value: 1, to: first) ?? first
        let result = googleCalendarEvents.filter { $0.startDate < end && $0.endDate > first && planner.filter.matches($0, search: search) }
        if eventDayCache.count >= 128 { eventDayCache.removeFirst() }
        eventDayCache.append((first, calendar, planner.filter, search, calendarEventRevision, result))
        return result
    }
    func task(id: UUID) -> ManagedTask? {
        if let index = taskPositions[id], state.managedTasks.indices.contains(index), state.managedTasks[index].id == id {
            return TaskSeriesEditing.displayedRoot(state.managedTasks[index])
        }
        // Validate positions because an operation can add/remove a task before save().
        if let index = state.managedTasks.firstIndex(where: { $0.id == id }) {
            taskPositions[id] = index; return TaskSeriesEditing.displayedRoot(state.managedTasks[index])
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
        visibleTasksCache.removeAll(keepingCapacity: true)
    }
    func resolvedTask(id: UUID) -> ManagedTask? {
        guard let root = task(id: id) else { return nil }
        if root.repeatRule != nil || root.seriesVersions != nil, let date = root.occurrenceDate ?? root.startDate ?? root.dueDate, (root.excludedOccurrences ?? []).contains(date) {
            return task(id: RecurrenceProjection.occurrenceID(root: id, date: date)) ?? root
        }
        return root
    }
    private func materialize(_ id: UUID) {
        guard !state.managedTasks.contains(where: { $0.id == id }), let task = virtualTasks[id],
              let root = task.seriesRootID, let date = task.occurrenceDate,
              let index = state.managedTasks.firstIndex(where: { $0.id == root }) else { return }
        var latest = task
        latest.seriesVersions = nil
        latest.id = task.id; latest.seriesRootID = root; latest.occurrenceDate = date
        latest.startDate = task.startDate; latest.plannedEndDate = task.startDate.map { $0.addingTimeInterval(Double(latest.durationMinutes * 60)) }
        latest.status = .active; latest.completedAt = nil; latest.repeatRule = nil; latest.excludedOccurrences = nil; latest.nextOccurrenceID = nil
        latest.sourceID = nil; latest.tickTickBaseline = nil; latest.googleEventID = nil; latest.googleCalendarID = nil; latest.googleETag = nil
        state.managedTasks[index].excludedOccurrences = (state.managedTasks[index].excludedOccurrences ?? []) + [date]
        state.managedTasks.append(latest)
    }
    private func editableOccurrenceID(_ id: UUID) -> UUID {
        materialize(id)
        guard let root = task(id: id), root.repeatRule != nil || root.seriesVersions != nil, root.seriesRootID == nil,
              let date = root.occurrenceDate ?? root.startDate ?? root.dueDate,
              let index = state.managedTasks.firstIndex(where: { $0.id == id }) else { return id }
        let occurrenceID = RecurrenceProjection.occurrenceID(root: root.id, date: date)
        if !state.managedTasks.contains(where: { $0.id == occurrenceID }) {
            var copy = root; copy.seriesVersions = nil; copy.id = occurrenceID; copy.seriesRootID = id; copy.occurrenceDate = date
            copy.repeatRule = nil; copy.excludedOccurrences = nil; copy.nextOccurrenceID = nil
            copy.sourceID = nil; copy.tickTickBaseline = nil
            state.managedTasks.append(copy)
        }
        if !(state.managedTasks[index].excludedOccurrences ?? []).contains(date) {
            state.managedTasks[index].excludedOccurrences = (state.managedTasks[index].excludedOccurrences ?? []) + [date]
        }
        return occurrenceID
    }
    func updateSeriesEdits(from original: ManagedTask, to draft: ManagedTask,
                           scope: TaskEditScope = .series, replaceExceptions: Bool = false) {
        if scope == .occurrence { updateManagedTaskEdits(from: original, to: draft); return }
        guard !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        recordTaskUndo()
        TaskSeriesEditing.apply(from: original, to: draft, scope: scope,
                                replaceExceptions: replaceExceptions, in: &state)
        save()
    }

    func seriesRoot(for task: ManagedTask) -> ManagedTask? {
        let id = task.seriesRootID ?? task.id
        return state.managedTasks.first { $0.id == id && ($0.repeatRule != nil || $0.seriesVersions != nil) }
    }

    func seriesRule(for task: ManagedTask) -> TaskRepeatRule? {
        guard let root = seriesRoot(for: task), let date = task.occurrenceDate ?? task.startDate ?? task.dueDate else { return nil }
        return TaskSeriesEditing.versions(of: root).last { $0.from <= date }?.template.repeatRule
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
        for id in ids { TaskEngine.trash(editableOccurrenceID(id), in: &state) }
        planner.selectedIDs = []; selectedTaskID = nil; save()
    }
    func bulkComplete(_ ids: Set<UUID>, completed: Bool = true) {
        recordTaskUndo()
        for id in ids {
            let target = task(id: id)?.seriesVersions != nil ? editableOccurrenceID(id) : id
            materialize(target); TaskEngine.setCompleted(target, completed: completed, in: &state)
        }
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
    func subtasks(of parentID: UUID) -> [ManagedTask] {
        TaskHierarchy.children(of: parentID, in: state.managedTasks)
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
        var draft = occurrence; change(&draft)
        updateSeriesEdits(from: occurrence, to: draft)
    }

    var scheduledManagedTasks: [ManagedTask] {
        state.managedTasks.map(TaskSeriesEditing.displayedRoot).filter { $0.status != .trashed && $0.startDate != nil }
            .sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }

    func matrixTasks(in quadrant: EisenhowerQuadrant) -> [ManagedTask] {
        let now = Date()
        let key = projectionKey(search: planner.search, kind: "matrix", now: now)
        return projectionCache.value(for: key, now: now) {
            let tasks = planner.filter.sorted(visibleManagedTasks.filter {
                $0.status == .active && plannerMatches($0, search: planner.search)
            }, by: planner.sort)
            var snapshot = PlannerTaskSnapshot(tasks: tasks)
            for task in tasks { snapshot.byQuadrant[task.quadrant, default: []].append(task) }
            return snapshot
        }.byQuadrant[quadrant] ?? []
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
        if state.groups.first(where: { $0.id == id })?.resources.contains(where: { $0.kind == .domain }) == true {
            pendingProtectedResourceChange = ProtectedResourceChange(groupID: id, operation: .removeGroup)
            return
        }
        removeGroupImmediately(id)
    }
    private func removeGroupImmediately(_ id: UUID) {
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
        if state.groups[index].isEnabled && !draft.isEnabled {
            pendingProtectedResourceChange = ProtectedResourceChange(groupID: id, operation: .disableGroup)
            return
        }
        if domainCoverageChanged(from: state.groups[index], to: draft) {
            pendingProtectedResourceChange = ProtectedResourceChange(groupID: id, operation: .applyGroupRule)
            return
        }
        state.groups[index] = draft; state.pendingGroupRules?.removeValue(forKey: id); saveAndApply()
    }
    private func domainCoverageChanged(from original: BlockGroup, to proposed: BlockGroup) -> Bool {
        original.resources.contains { resource in
            resource.kind == .domain && !proposed.resources.contains(where: { $0.id == resource.id && $0.identifier == resource.identifier })
        }
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
        if !value {
            guard state.groups[index].isEnabled else { return }
            pendingProtectedResourceChange = ProtectedResourceChange(groupID: id, operation: .disableGroup)
            return
        }
        if value, let draft = state.pendingGroupRules?[id], domainCoverageChanged(from: state.groups[index], to: draft) {
            pendingProtectedResourceChange = ProtectedResourceChange(groupID: id, operation: .applyGroupRule)
            return
        }
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
        if state.groups.first(where: { $0.id == groupID })?.resources.contains(where: { $0.id == resourceID && $0.kind == .domain }) == true {
            pendingProtectedResourceChange = ProtectedResourceChange(groupID: groupID, operation: .remove(resourceID))
            return
        }
        editGroup(groupID) { $0.resources.removeAll { $0.id == resourceID } }
    }

    func updateResource(_ resourceID: UUID, in groupID: UUID, displayName rawName: String, identifier rawIdentifier: String) throws {
        guard let group = groups.first(where: { $0.id == groupID }),
              let existing = group.resources.first(where: { $0.id == resourceID }) else { return }
        let proposed = existing.kind == .domain ? LocalRulesServer.normalizedDomain(rawIdentifier) : rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.kind == .domain {
            guard proposed.contains("."), !proposed.contains(" ") else { throw AppError.invalidDomain }
            guard !group.resources.contains(where: { $0.id != resourceID && $0.kind == .domain && $0.identifier == proposed }) else { throw AppError.duplicateResource }
            if let committed = state.groups.first(where: { $0.id == groupID })?.resources.first(where: { $0.id == resourceID }), committed.identifier != proposed {
                pendingProtectedResourceChange = ProtectedResourceChange(groupID: groupID, operation: .update(resourceID, rawName, proposed))
                return
            }
        }
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

    /// Apply only after explicit confirmation; keep protection and all unrelated rules enabled.
    @discardableResult
    func confirmProtectedResourceChange(_ confirmation: String) throws -> Bool {
        guard let change = pendingProtectedResourceChange, confirmation == change.confirmationWord,
              let index = state.groups.firstIndex(where: { $0.id == change.groupID }) else { return false }
        switch change.operation {
        case .update(let resourceID, let rawName, let identifier):
            guard let resourceIndex = state.groups[index].resources.firstIndex(where: { $0.id == resourceID }) else { return false }
            let effective = state.pendingGroupRules?[change.groupID] ?? state.groups[index]
            guard !effective.resources.contains(where: { $0.id != resourceID && $0.kind == .domain && $0.identifier == identifier }) else { throw AppError.duplicateResource }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            state.groups[index].resources[resourceIndex].identifier = identifier
            state.groups[index].resources[resourceIndex].displayName = name.isEmpty ? identifier : name
            if var draft = state.pendingGroupRules?[change.groupID], let draftIndex = draft.resources.firstIndex(where: { $0.id == resourceID }) {
                draft.resources[draftIndex] = state.groups[index].resources[resourceIndex]
                state.pendingGroupRules?[change.groupID] = draft
            }
        case .remove(let resourceID):
            guard state.groups[index].resources.contains(where: { $0.id == resourceID }) else { return false }
            state.groups[index].resources.removeAll { $0.id == resourceID }
            if var draft = state.pendingGroupRules?[change.groupID] {
                draft.resources.removeAll { $0.id == resourceID }; state.pendingGroupRules?[change.groupID] = draft
            }
        case .removeGroup:
            guard state.groups.count > 1 else { return false }
            state.groups.remove(at: index); state.pendingGroupRules?.removeValue(forKey: change.groupID)
            if selectedGroupID == change.groupID { selectedGroupID = state.groups.first?.id }
        case .applyGroupRule:
            guard let draft = state.pendingGroupRules?[change.groupID] else { return false }
            state.groups[index] = draft; state.pendingGroupRules?.removeValue(forKey: change.groupID)
        case .disableGroup:
            guard state.groups[index].isEnabled else { return false }
            state.groups[index].isEnabled = false
            state.pendingGroupRules?.removeValue(forKey: change.groupID)
        }
        state.disciplineStreak = 0
        state.disciplineLastCountedDayKey = DayKey.make(from: Date())
        for index in state.habits.indices { state.habits[index].resetCurrentStreak() }
        if case .disableGroup = change.operation {
            appendEvent(.taskSync, "Правило «\(state.groups[index].name)» отключено. Серия защиты и текущие серии привычек обнулены.")
        } else {
            appendEvent(.taskSync, "Подтверждено изменение заблокированных доменов. Серия защиты и текущие серии привычек обнулены.")
        }
        pendingProtectedResourceChange = nil
        saveAndApply()
        return true
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
        _ = createPlannerTask(ManagedTask(title: title,
            startDate: PlannerCalendar.current.startOfDay(for: Date()), isAllDay: true))
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

    func setManagedTaskWontDo(_ id: UUID, skipped: Bool) {
        recordTaskUndo()
        let target = editableOccurrenceID(id)
        guard let index = state.managedTasks.firstIndex(where: { $0.id == target }) else { return }
        state.managedTasks[index].status = skipped ? .wontDo : .active
        state.managedTasks[index].completedAt = nil
        state.managedTasks[index].modifiedAt = Date()
        save()
    }

    func updateManagedTaskEdits(from original: ManagedTask, to draft: ManagedTask) {
        recordTaskUndo()
        let id = editableOccurrenceID(draft.id)
        var before = original, after = draft; before.id = id; after.id = id
        if seriesRoot(for: original) != nil { before.repeatRule = nil; after.repeatRule = nil }
        TaskEngine.applyEdits(from: before, to: after, in: &state)
        save()
    }

    func setManagedTaskCompleted(_ id: UUID, completed: Bool) {
        recordTaskUndo()
        let target = task(id: id)?.seriesVersions != nil ? editableOccurrenceID(id) : id
        materialize(target)
        TaskEngine.setCompleted(target, completed: completed, in: &state)
        save()
    }

    func moveManagedTask(_ id: UUID, toKanbanStage stage: TaskKanbanStage) {
        guard task(id: id)?.effectiveKanbanStage != stage else { return }
        recordTaskUndo()
        let target = task(id: id)?.seriesVersions != nil ? editableOccurrenceID(id) : id
        materialize(target)
        guard let initialIndex = state.managedTasks.firstIndex(where: { $0.id == target }) else { pendingUndo = nil; return }
        let now = Date()
        state.managedTasks[initialIndex].kanbanStage = stage
        if stage == .done {
            TaskEngine.setCompleted(target, completed: true, in: &state, now: now)
        } else if state.managedTasks[initialIndex].status != .active {
            TaskEngine.setCompleted(target, completed: false, in: &state, now: now)
        }
        guard let index = state.managedTasks.firstIndex(where: { $0.id == target }) else { pendingUndo = nil; return }
        state.managedTasks[index].modifiedAt = now
        state.managedTasks[index].changeHistory.insert(
            TaskChange(date: now, summary: "Этап канбана: \(stage.title)"), at: 0
        )
        save()
    }

    func moveManagedTask(_ id: UUID, toList listID: UUID) {
        guard state.taskLists.contains(where: { $0.id == listID }) || listID == TaskList.inboxID,
              task(id: id)?.listID != listID else { return }
        recordTaskUndo()
        materialize(id)
        guard let index = state.managedTasks.firstIndex(where: { $0.id == id }) else {
            pendingUndo = nil
            return
        }
        let now = Date()
        state.managedTasks[index].listID = listID
        state.managedTasks[index].modifiedAt = now
        let listName = taskList(id: listID)?.name ?? TaskList.inbox.name
        state.managedTasks[index].changeHistory.insert(
            TaskChange(date: now, summary: "Проект: \(listName)"), at: 0
        )
        save()
    }

    func duplicateManagedTask(_ id: UUID) {
        recordTaskUndo()
        materialize(id)
        if TaskEngine.duplicate(id, in: &state) != nil { save() }
    }

    func requestTaskDeletion(_ ids: Set<UUID>) {
        let existing = ids.filter { task(id: $0) != nil }
        guard !existing.isEmpty else { return }
        if existing.contains(where: { task(id: $0).map { $0.repeatRule != nil || $0.seriesRootID != nil } ?? false }) {
            pendingTaskDeletion = existing
        } else {
            bulkTrash(existing)
        }
    }

    func confirmTaskDeletion(entireSeries: Bool) {
        let ids = pendingTaskDeletion
        pendingTaskDeletion = []
        guard !ids.isEmpty else { return }
        if entireSeries {
            let targets = Set(ids.compactMap { task(id: $0).map { $0.seriesRootID ?? $0.id } })
            recordTaskUndo()
            for id in targets { TaskEngine.trash(id, in: &state) }
            planner.selectedIDs = []; selectedTaskID = nil
            save()
        } else {
            bulkTrash(ids)
        }
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

    func removeTaskFolder(_ id: UUID) {
        guard state.taskFolders.contains(where: { $0.id == id }) else { return }
        for index in state.taskLists.indices where state.taskLists[index].folderID == id {
            state.taskLists[index].folderID = nil
        }
        state.taskFolders.removeAll { $0.id == id }
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

    func removeTaskList(_ id: UUID) {
        guard id != TaskList.inboxID, state.taskLists.contains(where: { $0.id == id }) else { return }
        let now = Date()
        for index in state.managedTasks.indices where state.managedTasks[index].listID == id {
            state.managedTasks[index].listID = TaskList.inboxID
            state.managedTasks[index].modifiedAt = now
            state.managedTasks[index].changeHistory.insert(
                TaskChange(date: now, summary: "Список удалён, задача перенесена во «Входящие»"),
                at: 0
            )
        }
        state.taskLists.removeAll { $0.id == id }
        listPositions.removeValue(forKey: id)
        if taskSidebarSelection == .list(id) { taskSidebarSelection = .inbox }
        save()
    }

    func startPomodoro(for taskID: UUID) {
        if TaskEngine.startPomodoro(taskID: taskID, in: &state) { save() }
    }

    func startFocus(taskID: UUID? = nil, phase: PomodoroPhase = .work, stopwatch: Bool = false) {
        if TaskEngine.startFocus(taskID: taskID, phase: phase, stopwatch: stopwatch, in: &state) { save() }
    }
    @discardableResult
    func setFocusDurations(workMinutes: Int, breakMinutes: Int) -> Bool {
        guard activePomodoro == nil, (1...999).contains(workMinutes), (1...999).contains(breakMinutes) else { return false }
        state.taskSettings.workMinutes = workMinutes
        state.taskSettings.shortBreakMinutes = breakMinutes
        save()
        return true
    }
    func checkFocusCompletion(now: Date = Date()) {
        guard let active = state.activePomodoro, active.pausedAt == nil, active.isStopwatch != true,
              TaskEngine.focusElapsed(active, now: now) >= active.targetSeconds else { return }
        TaskEngine.finishPomodoro(in: &state, now: now)
        save()
    }
    /// The native QA app keeps the local focus clock while external services stay disabled.
    func startIsolatedFocusClock() {
        guard HidigRuntime.isIsolated, !persistenceFailedToLoad, focusTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkFocusCompletion() }
        }
        focusTimer = timer
        RunLoop.main.add(timer, forMode: .common)
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
        guard servicesEnabled else { return }
        guard connectionState == .connected, !isImportingTickTick else { return }
        isImportingTickTick = true
        defer { isImportingTickTick = false }
        pendingTickTickImport = nil
        tickTickImportPreview = nil
        integration.tickTickImportError = nil
        do {
            let start = Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date()
            let snapshot = try await tickTickService.fullImportSnapshot(since: start)
            pendingTickTickImport = snapshot
            tickTickImportPreview = snapshot.preview
        } catch {
            integration.tickTickImportError = "Не удалось подготовить импорт: \(error.localizedDescription)"
        }
    }

    func performPreparedTickTickImport() {
        guard servicesEnabled else { return }
        guard connectionState == .connected, let snapshot = pendingTickTickImport else { return }
        do {
            writer.flush()
            _ = try repository.createBackup()
            _ = TaskEngine.importTickTick(
                folders: snapshot.folders,
                lists: snapshot.lists,
                records: snapshot.records,
                into: &state, preserveExisting: true
            )
            saveAndApply()
            pendingTickTickImport = nil
            tickTickImportPreview = nil
        } catch {
            integration.tickTickImportError = "Импорт остановлен: не удалось создать резервную копию. \(error.localizedDescription)"
        }
    }

    func connectGoogleCalendar(clientID: String, clientSecret: String?) async {
        guard servicesEnabled else { return }
        guard !isGoogleSynchronizing else { return }
        isGoogleSynchronizing = true
        defer { isGoogleSynchronizing = false }
        do {
            HidigRuntime.defaults.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "googleOAuthClientID")
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
        guard servicesEnabled else { return }
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
        guard servicesEnabled else { return }
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
        guard servicesEnabled else { return }
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
        guard servicesEnabled else { return }
        guard let index = state.managedTasks.firstIndex(where: { $0.id == taskID }) else { return }
        GoogleSyncEngine.unlink(&state.managedTasks[index])
        save()
    }

    private func synchronizeGoogleCalendar() async throws {
        guard servicesEnabled else { return }
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

    /// Explicitly requested by the import screen; never called at launch or on a timer.
    func checkTickTickImportConnection() async {
        guard servicesEnabled else { return }
        guard !isSynchronizing, !isImportingTickTick else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        pendingTickTickImport = nil
        tickTickImportPreview = nil
        integration.tickTickImportError = nil
        connectionState = .checking
        connectionState = await tickTickService.connectionState()
    }

    func connectTickTick() async {
        guard servicesEnabled else { return }
        guard !isSynchronizing, !isImportingTickTick else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        pendingTickTickImport = nil
        tickTickImportPreview = nil
        integration.tickTickImportError = nil
        connectionState = .connecting
        do {
            try await tickTickService.authenticate()
            connectionState = await tickTickService.connectionState()

        } catch {
            connectionState = .failed(error.localizedDescription)
            integration.tickTickImportError = error.localizedDescription
        }
    }

    func disconnectTickTick() async {
        guard servicesEnabled else { return }
        guard !isSynchronizing, !isImportingTickTick else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        do {
            try await tickTickService.signOut()
            finishTickTickDisconnect()
        } catch {
            integration.tickTickImportError = "Не удалось отключить импорт TickTick: \(error.localizedDescription)"
        }
    }

    func finishTickTickDisconnect() {
        connectionState = .signedOut
        pendingTickTickImport = nil
        tickTickImportPreview = nil
    }

    func copyCLIInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("npm install -g @ticktick/ticktick-cli", forType: .string)
    }

    func revealBrowserExtension() {
        guard let projectURL = HidigResources.bundle.resourceURL?
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
        guard servicesEnabled else { return }
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
        guard let url = HidigResources.bundle.resourceURL?.appendingPathComponent("BrowserExtension", isDirectory: true),
              FileManager.default.fileExists(atPath: url.appendingPathComponent("manifest.json").path) else { return nil }
        return url
    }

    var safariExtensionURL: URL? {
        guard let url = HidigResources.bundle.resourceURL?.appendingPathComponent("SafariExtension", isDirectory: true),
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
        if let failure = journalWriteReceipt.failure { errorMessage = "Не удалось сохранить текущую запись: " + failure; return }
        do {
            let contents = try journalRepository.read(entry)
            isLoadingJournal = true
            selectedJournalEntry = entry
            journalTitleDraft = entry.title
            journalDraft = contents
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
        journalWriter.async { [journalRepository, journalWriteReceipt, weak self] in
            let result = Result { try journalRepository.write(value, to: entry) }
            journalWriteReceipt.record(result)
            Task { @MainActor [weak self] in
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
        if let failure = journalWriteReceipt.failure { errorMessage = failure; return }
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

    private func scheduleLocalMaintenance() {
        syncTimer = Timer.scheduledTimer(
            timeInterval: 60,
            target: self,
            selector: #selector(localMaintenanceTimerFired(_:)),
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

    @objc private func localMaintenanceTimerFired(_ timer: Timer) {
        rollDisciplineForward()
        let day = Calendar.current.startOfDay(for: Date())
        if day != lastReminderDay { lastReminderDay = day; reminderService.refresh(state.managedTasks) }
        updateBlockingRules()
        evaluateRunningApplications()
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
        // In-memory query freshness is independent of whether the loaded database
        // is safe to overwrite. A load failure must keep its write guard intact.
        let calendarChanged = indexedTasks != state.managedTasks
        if calendarChanged {
            // Keep the complete visible window until its replacement is ready.
            // Clearing it here exposes a real-task-only fallback between every autosave.
            taskDataRevision &+= 1
            indexedTasks = state.managedTasks; rebuildTaskPositions(); calendarFallbackDays.removeAll(keepingCapacity: true); indexRequestedAnchor = nil; indexBuild?.cancel(); indexBuild = nil; indexRequest += 1
            if virtualTasks.count > 50_000 {
                let selectedVirtual = selectedTaskID.flatMap { virtualTasks[$0] }
                virtualTasks.removeAll()
                if let selectedVirtual { virtualTasks[selectedVirtual.id] = selectedVirtual }
            }
        }
        prepareCalendarIndex(force: calendarChanged)
        guard !persistenceFailedToLoad else { return }
        if calendarChanged {
            reminderService.refresh(state.managedTasks)
            if servicesEnabled {
                updateBlockingRules()
                evaluateRunningApplications()
            }
        }
        if let before = pendingUndo {
            if before != state.managedTasks {
                undoEntries.append(TaskHistoryEntry(before: before, after: state.managedTasks))
                if undoEntries.count > 50 { undoEntries.removeFirst() }
                redoEntries.removeAll()
            }
            pendingUndo = nil; updateUndoAvailability()
        }
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
    var attachmentDirectoryURL: URL { repository.applicationSupportDirectory.appendingPathComponent("Attachments", isDirectory: true) }
    func prepareForTermination() -> String? {
        let failure = writer.flushFailure()
        flushJournalWrites()
        if let failure { return failure.localizedDescription }
        return journalWriteReceipt.failure
    }

}
