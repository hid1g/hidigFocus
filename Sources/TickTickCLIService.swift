import Foundation

struct TickTickCLIService {
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
                    process.waitUntilExit()
                    let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                    let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
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
