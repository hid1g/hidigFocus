import AppKit
import Combine
import CryptoKit
import Foundation

/// UI-only state stays out of persistence snapshots and blocking-rule updates.
final class PlannerWorkspace: ObservableObject {
    @Published var calendarRevision: UInt64 = 0
    @Published var preparingCalendar = false
    @Published var search = ""
    @Published var collapsedTaskIDs: Set<UUID> = []
    @Published var selectedIDs: Set<UUID> = []
    @Published var filter = PlannerFilter()
    @Published var sort: PlannerSort = .date
    @Published var presentation: TasksPresentation = .list
    @Published var mode: TaskCalendarMode = .fourDays
    @Published var anchor = Date()
    @Published var cancellationToken = 0
    @Published var lastSelectedID: UUID?
    var scrollPositions: [String: CGPoint] = [:]
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: "planner.filter"), let saved = try? JSONDecoder().decode(PlannerFilter.self, from: data) { filter = saved }
        // Restore history hidden by the previous default once; subsequent choices persist.
        if !defaults.bool(forKey: "planner.completedVisibilityRestored") {
            filter.showCompleted = true
            if let data = try? JSONEncoder().encode(filter) { defaults.set(data, forKey: "planner.filter") }
            defaults.set(true, forKey: "planner.completedVisibilityRestored")
        }
        sort = PlannerSort(rawValue: defaults.string(forKey: "planner.sort") ?? "") ?? .date
        presentation = TasksPresentation(rawValue: defaults.string(forKey: "planner.presentation") ?? "") ?? .list
        mode = TaskCalendarMode(rawValue: defaults.string(forKey: "planner.mode") ?? "") ?? .fourDays
        if let saved = defaults.object(forKey: "planner.anchor") as? Date { anchor = saved }
        search = defaults.string(forKey: "planner.search") ?? ""
        $filter.dropFirst().sink { if let data = try? JSONEncoder().encode($0) { defaults.set(data, forKey: "planner.filter") } }.store(in: &cancellables)
        $sort.dropFirst().sink { defaults.set($0.rawValue, forKey: "planner.sort") }.store(in: &cancellables)
        $presentation.dropFirst().sink { defaults.set($0.rawValue, forKey: "planner.presentation") }.store(in: &cancellables)
        $mode.dropFirst().sink { defaults.set($0.rawValue, forKey: "planner.mode") }.store(in: &cancellables)
        $anchor.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { defaults.set($0, forKey: "planner.anchor") }.store(in: &cancellables)
        $search.dropFirst().debounce(for: .milliseconds(300), scheduler: RunLoop.main).sink { defaults.set($0, forKey: "planner.search") }.store(in: &cancellables)
    }
}

enum PlannerSort: String, CaseIterable {
    case manual, date, priority, title
    var title: String {
        switch self { case .manual: return "Ручной порядок"; case .date: return "По дате"; case .priority: return "По приоритету"; case .title: return "По названию" }
    }
}

struct PlannerFilter: Codable, Equatable {
    var listIDs: Set<UUID> = []
    var priority: TaskPriority?
    var showCompleted = true
    var showLocal = true
    var showImported = true
    var showEvents = true
    var isActive: Bool { !listIDs.isEmpty || priority != nil || !showLocal || !showImported || !showEvents || !showCompleted }

    func matches(_ task: ManagedTask, search: String, includeTrash: Bool = false, includeCompleted: Bool = false) -> Bool {
        guard task.status != .wontDo,
              (includeTrash ? task.status == .trashed : task.status != .trashed),
              task.status != .completed || showCompleted || includeCompleted,
              listIDs.isEmpty || listIDs.contains(task.listID),
              priority == nil || task.priority == priority,
              (task.sourceID == nil && task.sourceName != "TickTick") ? showLocal : showImported else { return false }
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return term.isEmpty || ([task.title, task.description, task.notes] + task.tags).contains { $0.localizedCaseInsensitiveContains(term) }
    }
    func matches(_ event: GoogleCalendarEventSnapshot, search: String) -> Bool {
        guard showEvents, priority == nil, !event.isDeleted else { return false }
        return search.isEmpty || event.title.localizedCaseInsensitiveContains(search) || event.description.localizedCaseInsensitiveContains(search)
    }
    func sorted(_ tasks: [ManagedTask], by sort: PlannerSort) -> [ManagedTask] {
        tasks.sorted {
            switch sort {
            case .manual: if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            case .date: if ($0.startDate ?? $0.dueDate) != ($1.startDate ?? $1.dueDate) { return ($0.startDate ?? $0.dueDate ?? .distantFuture) < ($1.startDate ?? $1.dueDate ?? .distantFuture) }
            case .priority: if $0.priority != $1.priority { return $0.priority.rawValue > $1.priority.rawValue }
            case .title: if $0.title != $1.title { return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            }
            return $0.sortOrder == $1.sortOrder ? $0.id.uuidString < $1.id.uuidString : $0.sortOrder < $1.sortOrder
        }
    }
}

enum RecurrenceProjection {
    static func supportedRule(_ rule: TaskRepeatRule) -> TaskRepeatRule? {
        guard let raw = rule.sourceRule else { return rule }
        let tokens = raw.uppercased().replacingOccurrences(of: "RRULE:", with: "").split(separator: ";").map { $0.split(separator: "=", maxSplits: 1).map(String.init) }
        guard tokens.allSatisfy({ $0.count == 2 && ["FREQ", "INTERVAL", "BYDAY"].contains($0[0]) }) else { return nil }
        let fields = Dictionary(tokens.map { ($0[0], $0[1]) }, uniquingKeysWith: { _, latest in latest })
        guard let frequency = fields["FREQ"].flatMap({ TaskRepeatFrequency(rawValue: $0.lowercased()) }) else { return nil }
        var result = TaskRepeatRule(frequency: frequency, interval: max(1, Int(fields["INTERVAL"] ?? "1") ?? 1))
        if let weekdays = fields["BYDAY"] {
            guard frequency == .weekly else { return nil }
            let codes = ["SU":1, "MO":2, "TU":3, "WE":4, "TH":5, "FR":6, "SA":7]
            let values = weekdays.split(separator: ",").map(String.init)
            guard values.allSatisfy({ codes[$0] != nil }) else { return nil }
            result.weekdays = Set(values.compactMap { codes[$0] })
        }
        return result
    }
    static func occurrenceID(root: UUID, date: Date) -> UUID {
        let digest = SHA256.hash(data: Data("\(root.uuidString):\(Int64(date.timeIntervalSince1970))".utf8))
        let b = Array(digest.prefix(16))
        return UUID(uuid: (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15]))
    }
    static func tasks(_ tasks: [ManagedTask], from first: Date, to end: Date) -> [ManagedTask] {
        var result = tasks.filter {
            guard let start = $0.startDate ?? $0.dueDate else { return false }
            if $0.seriesRootID == nil && ($0.excludedOccurrences ?? []).contains(start) { return false }
            return start < end && ($0.calendarEndDate ?? start.addingTimeInterval(900)) > first
        }
        let saved = Set(tasks.compactMap { task -> String? in
            guard let root = task.seriesRootID, let date = task.occurrenceDate else { return nil }
            return "\(root):\(Int64(date.timeIntervalSince1970))"
        })
        for root in tasks where root.seriesRootID == nil && root.status != .trashed && root.status != .wontDo {
            // Retain the saved task and its history, but never invent occurrences
            // for a missing source or an ancestor fetched only to repair hierarchy.
            guard root.sourceUnavailable != true, root.tickTickBaseline?.isHierarchyContext != true,
                  let storedRule = root.repeatRule, let rule = supportedRule(storedRule),
                  let start = root.startDate ?? root.dueDate else { continue }
            var calendar = Calendar.current
            calendar.timeZone = TimeZone(identifier: root.timeZoneID) ?? .current
            var cursor = start
            var iterations = 0
            while let next = TaskEngine.nextOccurrence(after: cursor, for: rule, calendar: calendar), next < end, next > cursor {
                cursor = next; iterations += 1
                if iterations > 100_000 { break }
                guard next >= first.addingTimeInterval(-Double(root.durationMinutes * 60)),
                      !(root.excludedOccurrences ?? []).contains(next),
                      !saved.contains("\(root.id):\(Int64(next.timeIntervalSince1970))") else { continue }
                var copy = root
                copy.id = occurrenceID(root: root.id, date: next)
                copy.seriesRootID = root.id; copy.occurrenceDate = next
                copy.startDate = next
                copy.plannedEndDate = next.addingTimeInterval(Double(root.durationMinutes * 60))
                copy.dueDate = root.dueDate.map { $0.addingTimeInterval(next.timeIntervalSince(start)) }
                copy.status = .active; copy.completedAt = nil; copy.nextOccurrenceID = nil
                copy.repeatRule = nil; copy.excludedOccurrences = nil
                copy.sourceID = nil; copy.sourceListID = nil; copy.tickTickBaseline = nil
                copy.googleEventID = nil; copy.googleCalendarID = nil; copy.googleETag = nil
                copy.checklist = copy.checklist.map { var value = $0; value.isCompleted = false; return value }
                result.append(copy)
            }
        }
        return result
    }
}

struct QuickTaskInput {
    var title: String
    var date: Date?
    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> Self {
        var title = input.trimmingCharacters(in: .whitespacesAndNewlines)
        var date: Date?
        let words = [("сегодня", 0), ("завтра", 1), ("понедельник", 2), ("вторник", 3), ("среда", 4), ("четверг", 5), ("пятница", 6), ("суббота", 7), ("воскресенье", 1)]
        for (word, value) in words {
            guard let range = title.range(of: "(?i)(?<![\\p{L}])\(word)(?![\\p{L}])", options: .regularExpression) else { continue }
            let shift = word == "сегодня" || word == "завтра" ? value : (value - calendar.component(.weekday, from: now) + 7) % 7
            date = calendar.date(byAdding: .day, value: shift, to: calendar.startOfDay(for: now))
            title.removeSubrange(range); break
        }
        if let range = title.range(of: "(?<![0-9])[0-2]?[0-9]:[0-5][0-9](?![0-9])", options: .regularExpression) {
            let parts = title[range].split(separator: ":").compactMap { Int($0) }
            if parts.count == 2, parts[0] < 24 {
                date = calendar.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: date ?? now)
                title.removeSubrange(range)
            }
        }
        return Self(title: title.split(whereSeparator: { $0.isWhitespace }).joined(separator: " "), date: date)
    }
}

struct PlannerTaskTree {
    struct Row: Identifiable {
        let task: ManagedTask
        let root: ManagedTask
        let depth: Int
        let hasChildren: Bool
        var id: UUID { task.id }
    }
    static func rows(_ tasks: [ManagedTask], collapsed: Set<UUID> = []) -> [Row] {
        let ids = Set(tasks.map(\.id))
        var children: [UUID: [ManagedTask]] = [:]
        var roots: [ManagedTask] = []
        for task in tasks {
            if let parent = task.parentTaskID, parent != task.id, ids.contains(parent) { children[parent, default: []].append(task) }
            else { roots.append(task) }
        }
        var result: [Row] = [], visited: Set<UUID> = []
        func append(_ task: ManagedTask, root: ManagedTask, depth: Int) {
            guard visited.insert(task.id).inserted else { return }
            let nested = children[task.id] ?? []
            result.append(Row(task: task, root: root, depth: depth, hasChildren: !nested.isEmpty))
            if collapsed.contains(task.id) {
                func hide(_ task: ManagedTask) {
                    guard visited.insert(task.id).inserted else { return }
                    for child in children[task.id] ?? [] { hide(child) }
                }
                for child in nested { hide(child) }
            } else { for child in nested { append(child, root: root, depth: depth + 1) } }
        }
        for root in roots { append(root, root: root, depth: 0) }
        // Malformed cycles remain accessible as roots instead of disappearing.
        for task in tasks where !visited.contains(task.id) { append(task, root: task, depth: 0) }
        return result
    }
}
