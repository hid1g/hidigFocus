import Foundation
import UserNotifications

struct ScheduledReminder: Equatable {
    let id: String
    let title: String
    let date: Date
}
enum ReminderPlan {
    static func requests(tasks: [ManagedTask], now: Date = Date()) -> [ScheduledReminder] {
        tasks.filter { $0.status == .active }.flatMap { task in
            task.reminders.compactMap { reminder in
                let date = reminder.date ?? reminder.relativeMinutes.flatMap { minutes in
                    task.startDate.map { $0.addingTimeInterval(-Double(minutes * 60)) }
                }
                guard let date, date > now else { return nil }
                return ScheduledReminder(id: "hidigFocus.task.\(task.id).\(reminder.id)", title: task.title, date: date)
            }
        }.sorted { $0.date < $1.date }
    }
}
@MainActor final class TaskReminderService: ObservableObject {
    @Published private(set) var authorized = false
    @Published private(set) var error: String?
    private var generation = 0
    private var pending: Task<Void, Never>?
    private var latestTasks: [ManagedTask] = []
    // UNUserNotificationCenter requires a packaged application, never a SwiftPM test process.
    private var center: UNUserNotificationCenter? { Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil }
    func requestPermission() async {
        guard let center else { return }
        do { authorized = try await center.requestAuthorization(options: [.alert, .sound, .badge]); if authorized { refresh(latestTasks) } }
        catch { self.error = error.localizedDescription }
    }
    func refresh(_ tasks: [ManagedTask]) {
        latestTasks = tasks; generation += 1; let revision = generation
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 200_000_000) } catch { return }
            guard let self, let center = self.center else { return }
            let settings = await center.notificationSettings()
            guard revision == self.generation else { return }
            self.authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            let existing = await center.pendingNotificationRequests()
            guard revision == self.generation else { return }
            let planned = await Task.detached(priority: .utility) {
                let now = Date()
                let horizon = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
                let actualIDs = Set(tasks.map(\.id))
                let future = RecurrenceProjection.tasks(tasks, from: now, to: horizon).filter { !actualIDs.contains($0.id) }
                return Array(ReminderPlan.requests(tasks: tasks + future, now: now).prefix(64))
            }.value
            guard revision == self.generation, self.authorized else { return }
            let ids = Set(planned.map(\.id))
            center.removePendingNotificationRequests(withIdentifiers: existing.map(\.identifier).filter { $0.hasPrefix("hidigFocus.task.") && !ids.contains($0) })
            for request in planned {
                guard revision == self.generation, !Task.isCancelled else { return }
                let content = UNMutableNotificationContent(); content.title = request.title; content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, request.date.timeIntervalSinceNow), repeats: false)
                do { try await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger)) }
                catch { self.error = error.localizedDescription }
            }
        }
    }
}
