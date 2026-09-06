import Foundation
import Network

final class LocalRulesServer {
    static let port: UInt16 = 17_321
    var onRulesRequest: ((String) -> Void)?

    private let queue = DispatchQueue(label: "hidigFocus.rules-server")
    private let stateLock = NSLock()
    private var listener: NWListener?
    private var blockRules: [BrowserBlockRule] = []

    func start() throws {
        guard listener == nil else { return }
        guard let port = NWEndpoint.Port(rawValue: Self.port) else { return }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.stateUpdateHandler = { state in
            if case let .failed(error) = state {
                NSLog("hidigFocus rules server failed: %@", error.localizedDescription)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func update(rules: [BrowserBlockRule]) {
        var expandedByDomain: [String: BrowserBlockRule] = [:]
        for rule in rules {
            for domain in Self.expandedDomains(for: rule.domain) where expandedByDomain[domain] == nil {
                var expanded = rule
                expanded.domain = domain
                expandedByDomain[domain] = expanded
            }
        }
        stateLock.lock()
        blockRules = expandedByDomain.values.sorted { $0.domain < $1.domain }
        stateLock.unlock()
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let response: Data
            if path == "/rules" || path.hasPrefix("/rules?") {
                self.onRulesRequest?(self.clientName(from: path))
                response = self.rulesResponse()
            } else if path == "/health" {
                response = self.httpResponse(body: Data("{\"ok\":true}".utf8), contentType: "application/json")
            } else {
                response = self.httpResponse(
                    status: "404 Not Found",
                    body: Data("Not found".utf8),
                    contentType: "text/plain; charset=utf-8"
                )
            }
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func clientName(from path: String) -> String {
        guard let components = URLComponents(string: "http://localhost\(path)") else { return "chromium" }
        return components.queryItems?.first(where: { $0.name == "client" })?.value ?? "chromium"
    }

    private func rulesResponse() -> Data {
        stateLock.lock()
        let rules = blockRules
        stateLock.unlock()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payload = (try? encoder.encode(RulesPayload(
            blockedDomains: rules.map(\.domain),
            rules: rules
        ))) ?? Data("{\"blockedDomains\":[],\"rules\":[]}".utf8)
        return httpResponse(body: payload, contentType: "application/json")
    }

    private func httpResponse(
        status: String = "200 OK",
        body: Data,
        contentType: String
    ) -> Data {
        let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    static func normalizedDomain(_ rawValue: String) -> String {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let url = URL(string: value), let host = url.host {
            value = host
        }
        value = value
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
        value = value.split(separator: "/").first.map(String.init) ?? value
        if value.hasPrefix("www.") { value.removeFirst(4) }
        return value
    }

    static func expandedDomains(for rawValue: String) -> [String] {
        let domain = normalizedDomain(rawValue)
        guard !domain.isEmpty else { return [] }

        let aliasGroups: [[String]] = [
            ["vk.com", "vk.ru"],
            ["x.com", "twitter.com", "t.co"],
            ["youtube.com", "youtu.be", "youtube-nocookie.com"]
        ]
        return aliasGroups.first(where: { $0.contains(domain) }) ?? [domain]
    }

    private struct RulesPayload: Encodable {
        let blockedDomains: [String]
        let rules: [BrowserBlockRule]
    }
}
