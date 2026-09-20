import Foundation

struct TickTickCLIService {
    struct ImportSnapshot {
        var folders: [TaskFolder]
        var lists: [TaskList]
        var records: [TickTickImportRecord]
        var preview: TaskImportPreview
    }
    struct CommandResult {
        var stdout: Data
        var stderr: String
        var status: Int32
    }

    private let candidatePaths = [
        "/opt/homebrew/bin/ticktick",
        "/usr/local/bin/ticktick"
    ]

    func executableURL() -> URL? {
        for path in candidatePaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    func connectionState() async -> TickTickConnectionState {
        guard let executableURL = executableURL() else { return .cliMissing }
        do {
            let result = try await run(executableURL: executableURL, arguments: ["auth", "status"])
            guard result.status == 0 else { return .signedOut }
            return .connected
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func authenticate() async throws {
        guard let executableURL = executableURL() else { throw TickTickCLIError.cliMissing }
        let result = try await run(executableURL: executableURL, arguments: ["auth", "login"])
        guard result.status == 0 else {
            throw TickTickCLIError.commandFailed(result.stderr)
        }
    }

    func todayTasks(calendar: Calendar = .current) async throws -> [TickTickTask] {
        guard let executableURL = executableURL() else { throw TickTickCLIError.cliMissing }

        let start = calendar.startOfDay(for: Date())
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let dueFrom = formatter.string(from: start)
        let dueTo = formatter.string(from: end)

        async let projectsResult = run(executableURL: executableURL, arguments: ["project", "list", "--json"])
        async let tasksResult = run(
            executableURL: executableURL,
            arguments: [
                "task", "filter",
                "--start-date", dueFrom,
                "--end-date", dueTo,
                "--status", "0,2",
                "--json"
            ]
        )

        let (projectCommand, taskCommand) = try await (projectsResult, tasksResult)
        guard projectCommand.status == 0 else {
            throw TickTickCLIError.commandFailed(projectCommand.stderr)
        }
        guard taskCommand.status == 0 else {
            throw TickTickCLIError.commandFailed(taskCommand.stderr)
        }

        let projectNames = try parseProjectNames(projectCommand.stdout)
        return try parseTasks(taskCommand.stdout, projectNames: projectNames)
            .sorted {
                if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
                let projectOrder = $0.projectName.localizedCaseInsensitiveCompare($1.projectName)
                if projectOrder != .orderedSame { return projectOrder == .orderedAscending }
                switch ($0.dueDate, $1.dueDate) {
                case let (left?, right?) where left != right: return left < right
                case (nil, _?): return false
                case (_?, nil): return true
                case (nil, nil): return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                default: return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
            }
    }

    func fullImportSnapshot(since: Date, through endDate: Date = Date(), calendar: Calendar = .current) async throws -> ImportSnapshot {
        guard let executableURL = executableURL() else { throw TickTickCLIError.cliMissing }
        let projectsCommand = try await run(executableURL: executableURL, arguments: ["project", "list", "--json"])
        guard projectsCommand.status == 0 else { throw TickTickCLIError.commandFailed(projectsCommand.stderr) }
        let projectRows = try objectRows(from: projectsCommand.stdout, preferredKey: "projects")
        let lists: [TaskList] = projectRows.compactMap { row in
            guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
            return TaskList(
                name: name,
                colorHex: row["color"] as? String ?? "#7A9B63",
                sortOrder: Self.int64(row["sortOrder"]),
                isPinned: false,
                sourceID: id
            )
        }

        let activeCommand = try await run(executableURL: executableURL, arguments: ["task", "filter", "--status", "0", "--json"])
        guard activeCommand.status == 0 else { throw TickTickCLIError.commandFailed(activeCommand.stderr) }
        var rows = try objectRows(from: activeCommand.stdout, preferredKey: "tasks")

        var cursor = calendar.startOfDay(for: since)
        let finish = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate)) ?? endDate
        let formatter = ISO8601DateFormatter()
        while cursor < finish {
            let chunkEnd = min(calendar.date(byAdding: .day, value: 7, to: cursor) ?? finish, finish)
            if ProcessInfo.processInfo.environment["HIDIGFOCUS_RUN_LIVE_IMPORT"] == "1" {
                print("TICKTICK_IMPORT_FETCH \(DayKey.make(from: cursor))...\(DayKey.make(from: chunkEnd))")
            }
            let result = try await run(executableURL: executableURL, arguments: [
                "task", "completed",
                "--start-date", formatter.string(from: cursor),
                "--end-date", formatter.string(from: chunkEnd),
                "--json"
            ])
            guard result.status == 0 else { throw TickTickCLIError.commandFailed(result.stderr) }
            rows.append(contentsOf: try objectRows(from: result.stdout, preferredKey: "tasks"))
            cursor = chunkEnd
        }

        var seen = Set<String>()
        let records = rows.compactMap { row -> TickTickImportRecord? in
            guard let id = row["id"] as? String,
                  let projectID = row["projectId"] as? String,
                  let title = row["title"] as? String,
                  seen.insert(id).inserted else { return nil }
            return parseImportRecord(row, id: id, projectID: projectID, title: title)
        }
        return ImportSnapshot(
            folders: [],
            lists: lists,
            records: records,
            preview: TaskImportPreview(
                folders: 0,
                lists: lists.count,
                activeTasks: records.filter { $0.completedAt == nil }.count,
                completedTasks: records.filter { $0.completedAt != nil }.count
            )
        )
    }

    private func parseProjectNames(_ data: Data) throws -> [String: String] {
        let rows = try objectRows(from: data, preferredKey: "projects")
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row in
            guard let id = row["id"] as? String, let name = row["name"] as? String else { return nil }
            return (id, name)
        })
    }

    private func parseTasks(_ data: Data, projectNames: [String: String]) throws -> [TickTickTask] {
        let rows = try objectRows(from: data, preferredKey: "tasks")
        let dateParser = TickTickDateParser()
        return rows.compactMap { row in
            guard let id = row["id"] as? String,
                  let projectID = row["projectId"] as? String,
                  let title = row["title"] as? String else { return nil }

            let status = row["status"] as? Int
                ?? (row["status"] as? NSNumber)?.intValue
                ?? 0
            return TickTickTask(
                id: id,
                projectID: projectID,
                projectName: projectNames[projectID] ?? "TickTick",
                title: title,
                dueDate: dateParser.parse(row["dueDate"] as? String),
                completedAt: dateParser.parse(row["completedTime"] as? String),
                status: status
            )
        }
    }

    private func parseImportRecord(_ row: [String: Any], id: String, projectID: String, title: String) -> TickTickImportRecord {
        let dateParser = TickTickDateParser()
        let priorityRaw = (row["priority"] as? NSNumber)?.intValue ?? row["priority"] as? Int ?? 0
        let priority = TaskPriority(rawValue: priorityRaw) ?? .none
        let reminders = (row["reminders"] as? [String] ?? []).map { value in
            TaskReminder(
                date: dateParser.parse(value),
                relativeMinutes: Self.reminderMinutes(value),
                sourceValue: value
            )
        }
        let items = (row["items"] as? [[String: Any]] ?? []).compactMap { item -> TaskChecklistItem? in
            guard let name = item["title"] as? String else { return nil }
            let status = (item["status"] as? NSNumber)?.intValue ?? item["status"] as? Int ?? 0
            return TaskChecklistItem(
                title: name,
                isCompleted: status == 1 || status == 2,
                sortOrder: Self.int64(item["sortOrder"])
            )
        }
        let repeatValue = row["repeatFlag"] as? String
        let summaries = row["focusSummaries"] as? [[String: Any]] ?? []
        let estimatedPomo = summaries.reduce(0) { $0 + ((($1["estimatedPomo"] as? NSNumber)?.intValue) ?? 0) }
        let pomoCount = summaries.reduce(0) { $0 + ((($1["pomoCount"] as? NSNumber)?.intValue) ?? 0) }
        let estimatedDuration = summaries.reduce(0) { $0 + ((($1["estimatedDuration"] as? NSNumber)?.intValue) ?? 0) }
        return TickTickImportRecord(
            sourceID: id,
            projectSourceID: projectID,
            title: title,
            description: row["desc"] as? String ?? "",
            notes: row["content"] as? String ?? "",
            startDate: dateParser.parse(row["startDate"] as? String),
            dueDate: dateParser.parse(row["dueDate"] as? String),
            completedAt: dateParser.parse(row["completedTime"] as? String),
            isAllDay: row["isAllDay"] as? Bool ?? false,
            timeZoneID: row["timeZone"] as? String ?? TimeZone.current.identifier,
            priority: priority,
            reminders: reminders,
            repeatRule: repeatValue.flatMap(Self.repeatRule),
            tags: row["tags"] as? [String] ?? [],
            checklist: items,
            sortOrder: Self.int64(row["sortOrder"]),
            plannedPomodoros: estimatedPomo,
            completedPomodoros: pomoCount,
            durationMinutes: estimatedDuration > 0 ? max(15, estimatedDuration / 60) : 30
        )
    }

    private static func int64(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        return 0
    }

    private static func repeatRule(_ raw: String) -> TaskRepeatRule? {
        let upper = raw.uppercased()
        let frequency: TaskRepeatFrequency
        if upper.contains("FREQ=DAILY") { frequency = .daily }
        else if upper.contains("FREQ=WEEKLY") { frequency = .weekly }
        else if upper.contains("FREQ=MONTHLY") { frequency = .monthly }
        else if upper.contains("FREQ=YEARLY") { frequency = .yearly }
        else { return nil }
        let interval = upper.split(separator: ";")
            .first(where: { $0.hasPrefix("INTERVAL=") })
            .flatMap { Int($0.dropFirst("INTERVAL=".count)) } ?? 1
        return TaskRepeatRule(frequency: frequency, interval: interval, sourceRule: raw)
    }

    private static func reminderMinutes(_ raw: String) -> Int? {
        guard raw.hasPrefix("TRIGGER:") else { return nil }
        let duration = raw.dropFirst("TRIGGER:".count)
        let sign = duration.hasPrefix("-") ? -1 : 1
        var value = String(duration).replacingOccurrences(of: "-", with: "")
        guard value.hasPrefix("P") else { return nil }
        value.removeFirst()
        var number = ""
        var minutes = 0
        var inTime = false
        for character in value {
            if character == "T" { inTime = true; continue }
            if character.isNumber { number.append(character); continue }
            guard let amount = Int(number) else { continue }
            number = ""
            switch character {
            case "D": minutes += amount * 24 * 60
            case "H" where inTime: minutes += amount * 60
            case "M" where inTime: minutes += amount
            case "S" where inTime: minutes += amount >= 30 ? 1 : 0
            default: break
            }
        }
        return sign * minutes
    }

    private func objectRows(from data: Data, preferredKey: String) throws -> [[String: Any]] {
        let object = try JSONSerialization.jsonObject(with: data)
        if let rows = object as? [[String: Any]] { return rows }
        if let dictionary = object as? [String: Any],
           let rows = dictionary[preferredKey] as? [[String: Any]] {
            return rows
        }
        throw TickTickCLIError.invalidResponse
    }

    private func run(executableURL: URL, arguments: [String]) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()
                process.executableURL = executableURL
                process.arguments = arguments
                process.standardOutput = stdout
                process.standardError = stderr
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                process.environment = environment

                do {
                    try process.run()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 30) {
                        if process.isRunning { process.terminate() }
                    }
                    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                    process.waitUntilExit()
                    continuation.resume(returning: CommandResult(
                        stdout: outputData,
                        stderr: String(data: errorData, encoding: .utf8) ?? "",
                        status: process.terminationStatus
                    ))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

private struct TickTickDateParser {
    private let internetFormatter = ISO8601DateFormatter()
    private let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private let compactZoneFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        return formatter
    }()
    private let compactZoneWithoutFractionalFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }()

    func parse(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractionalFormatter.date(from: value)
            ?? internetFormatter.date(from: value)
            ?? compactZoneFormatter.date(from: value)
            ?? compactZoneWithoutFractionalFormatter.date(from: value)
    }
}

enum TickTickCLIError: LocalizedError {
    case cliMissing
    case invalidResponse
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .cliMissing:
            return "TickTick CLI не установлен."
        case .invalidResponse:
            return "TickTick вернул неизвестный формат данных."
        case let .commandFailed(message):
            return message.isEmpty ? "Команда TickTick завершилась с ошибкой." : message
        }
    }
}
