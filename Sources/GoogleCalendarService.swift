import AuthenticationServices
import AppKit
import CryptoKit
import Foundation
import Security

struct GoogleOAuthTokens: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
}

struct GoogleCalendarDescriptor: Identifiable, Codable, Equatable {
    var id: String
    var summary: String
    var backgroundColor: String?
    var isPrimary: Bool
}

final class SecureTokenStore {
    private let service = "com.hidig.focus.google-calendar"
    private let account = "oauth-tokens"
    private let secretAccount = "oauth-client-secret"

    func save(_ tokens: GoogleOAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw GoogleCalendarError.notAuthorized }
    }

    func load() throws -> GoogleOAuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw GoogleCalendarError.notAuthorized }
        return try JSONDecoder().decode(GoogleOAuthTokens.self, from: data)
    }

    func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        let secretQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secretAccount
        ]
        SecItemDelete(secretQuery as CFDictionary)
    }

    func saveClientSecret(_ secret: String?) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secretAccount
        ]
        SecItemDelete(query as CFDictionary)
        guard let secret, !secret.isEmpty else { return }
        var item = query
        item[kSecValueData as String] = Data(secret.utf8)
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw GoogleCalendarError.notAuthorized }
    }

    func loadClientSecret() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: secretAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

@MainActor
final class GoogleCalendarService: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let tokenStore = SecureTokenStore()
    private let session: URLSession
    private var authSession: ASWebAuthenticationSession?

    override init() {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
        super.init()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }

    func disconnect() {
        tokenStore.delete()
    }

    func authorize(clientID: String, clientSecret: String?) async throws {
        let cleanedID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedID.isEmpty else { throw GoogleCalendarError.notConfigured }
        let scheme = cleanedID.components(separatedBy: ".apps.googleusercontent.com").first.map { "com.googleusercontent.apps.\($0)" }
        guard let scheme else { throw GoogleCalendarError.notConfigured }
        let redirectURI = "\(scheme):/oauth2redirect"
        let verifier = Self.randomVerifier()
        let challenge = Self.challenge(for: verifier)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: cleanedID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/calendar.events https://www.googleapis.com/auth/calendar.calendarlist.readonly"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        let callback = try await callbackURL(for: components.url!, scheme: scheme)
        guard let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw GoogleCalendarError.notAuthorized
        }
        let tokens = try await exchangeCode(code, clientID: cleanedID, clientSecret: clientSecret, redirectURI: redirectURI, verifier: verifier)
        try tokenStore.save(tokens)
        try tokenStore.saveClientSecret(clientSecret)
    }

    func calendars() async throws -> [GoogleCalendarDescriptor] {
        let data = try await request(path: "users/me/calendarList", method: "GET")
        let root = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        return root.items.map { GoogleCalendarDescriptor(id: $0.id, summary: $0.summary, backgroundColor: $0.backgroundColor, isPrimary: $0.primary ?? false) }
    }

    func events(calendarID: String, from: Date, to: Date) async throws -> [GoogleCalendarEventSnapshot] {
        var query = [
            URLQueryItem(name: "timeMin", value: Self.formatter.string(from: from)),
            URLQueryItem(name: "timeMax", value: Self.formatter.string(from: to)),
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "showDeleted", value: "true"),
            URLQueryItem(name: "maxResults", value: "2500")
        ]
        query.append(URLQueryItem(name: "orderBy", value: "startTime"))
        let data = try await request(path: "calendars/\(escape(calendarID))/events", method: "GET", query: query)
        let root = try JSONDecoder().decode(EventListResponse.self, from: data)
        return root.items.compactMap { $0.snapshot(calendarID: calendarID) }
    }

    func createEvent(from task: ManagedTask, calendarID: String) async throws -> GoogleCalendarEventSnapshot {
        let body = try JSONEncoder().encode(APIEvent(task: task))
        let data = try await request(path: "calendars/\(escape(calendarID))/events", method: "POST", body: body)
        return try decodeEvent(data, calendarID: calendarID)
    }

    func updateEvent(from task: ManagedTask, calendarID: String, eventID: String) async throws -> GoogleCalendarEventSnapshot {
        let body = try JSONEncoder().encode(APIEvent(task: task))
        var headers: [String: String] = [:]
        if let etag = task.googleETag { headers["If-Match"] = etag }
        let data = try await request(path: "calendars/\(escape(calendarID))/events/\(escape(eventID))", method: "PATCH", body: body, headers: headers)
        return try decodeEvent(data, calendarID: calendarID)
    }

    func deleteEvent(calendarID: String, eventID: String) async throws {
        _ = try await request(path: "calendars/\(escape(calendarID))/events/\(escape(eventID))", method: "DELETE")
    }

    private func callbackURL(for url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let auth = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { url, error in
                if let url { continuation.resume(returning: url) }
                else { continuation.resume(throwing: error ?? GoogleCalendarError.notAuthorized) }
            }
            auth.presentationContextProvider = self
            auth.prefersEphemeralWebBrowserSession = false
            authSession = auth
            guard auth.start() else {
                continuation.resume(throwing: GoogleCalendarError.notAuthorized)
                return
            }
        }
    }

    private func exchangeCode(_ code: String, clientID: String, clientSecret: String?, redirectURI: String, verifier: String) async throws -> GoogleOAuthTokens {
        var values = [
            "code": code,
            "client_id": clientID,
            "redirect_uri": redirectURI,
            "grant_type": "authorization_code",
            "code_verifier": verifier
        ]
        if let clientSecret, !clientSecret.isEmpty { values["client_secret"] = clientSecret }
        return try await tokenRequest(values)
    }

    private func validAccessToken() async throws -> String {
        guard var tokens = try tokenStore.load() else { throw GoogleCalendarError.notAuthorized }
        if tokens.expiresAt.timeIntervalSinceNow > 60 { return tokens.accessToken }
        guard let refreshToken = tokens.refreshToken,
              let clientID = UserDefaults.standard.string(forKey: "googleOAuthClientID") else { throw GoogleCalendarError.tokenExpired }
        var values = ["refresh_token": refreshToken, "client_id": clientID, "grant_type": "refresh_token"]
        if let secret = tokenStore.loadClientSecret(), !secret.isEmpty { values["client_secret"] = secret }
        var refreshed = try await tokenRequest(values)
        refreshed.refreshToken = refreshed.refreshToken ?? refreshToken
        tokens = refreshed
        try tokenStore.save(tokens)
        return tokens.accessToken
    }

    private func tokenRequest(_ values: [String: String]) async throws -> GoogleOAuthTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = values.map { "\(Self.formEncode($0.key))=\(Self.formEncode($0.value))" }.sorted().joined(separator: "&").data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GoogleCalendarError.offline }
        guard (200..<300).contains(http.statusCode) else { throw GoogleCalendarError.api(http.statusCode, String(data: data, encoding: .utf8) ?? "") }
        let value = try JSONDecoder().decode(TokenResponse.self, from: data)
        return GoogleOAuthTokens(accessToken: value.accessToken, refreshToken: value.refreshToken, expiresAt: Date().addingTimeInterval(TimeInterval(value.expiresIn)))
    }

    private func request(path: String, method: String, query: [URLQueryItem] = [], body: Data? = nil, headers: [String: String] = [:]) async throws -> Data {
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/\(path)")!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw GoogleCalendarError.offline }
            if http.statusCode == 401 { throw GoogleCalendarError.tokenExpired }
            guard (200..<300).contains(http.statusCode) else { throw GoogleCalendarError.api(http.statusCode, String(data: data, encoding: .utf8) ?? "") }
            return data
        } catch let error as GoogleCalendarError {
            throw error
        } catch {
            throw GoogleCalendarError.offline
        }
    }

    private func decodeEvent(_ data: Data, calendarID: String) throws -> GoogleCalendarEventSnapshot {
        guard let value = try JSONDecoder().decode(APIEvent.self, from: data).snapshot(calendarID: calendarID) else { throw GoogleCalendarError.invalidResponse }
        return value
    }

    private func escape(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value }
    private static func randomVerifier() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "") }
    private static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
    private static func formEncode(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value }
    fileprivate static let formatter = ISO8601DateFormatter()
}

private struct TokenResponse: Decodable {
    var accessToken: String
    var refreshToken: String?
    var expiresIn: Int
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", refreshToken = "refresh_token", expiresIn = "expires_in" }
}

private struct CalendarListResponse: Decodable {
    struct Item: Decodable { var id: String; var summary: String; var backgroundColor: String?; var primary: Bool? }
    var items: [Item]
}

private struct EventListResponse: Decodable { var items: [APIEvent] }

private struct APIEvent: Codable {
    struct Point: Codable { var dateTime: String?; var date: String?; var timeZone: String? }
    var id: String?
    var etag: String?
    var summary: String?
    var description: String?
    var start: Point
    var end: Point
    var updated: String?
    var recurrence: [String]?
    var status: String?

    init(task: ManagedTask) {
        summary = task.title
        description = task.description
        let startDate = task.startDate ?? Date()
        let endDate = task.calendarEndDate ?? startDate.addingTimeInterval(1800)
        let formatter = ISO8601DateFormatter()
        if task.isAllDay {
            start = Point(date: DayKey.make(from: startDate), timeZone: task.timeZoneID)
            end = Point(date: DayKey.make(from: endDate), timeZone: task.timeZoneID)
        } else {
            start = Point(dateTime: formatter.string(from: startDate), timeZone: task.timeZoneID)
            end = Point(dateTime: formatter.string(from: endDate), timeZone: task.timeZoneID)
        }
        if let rule = task.repeatRule {
            recurrence = ["RRULE:FREQ=\(rule.frequency.rawValue.uppercased());INTERVAL=\(max(1, rule.interval))"]
        }
    }

    func snapshot(calendarID: String) -> GoogleCalendarEventSnapshot? {
        guard let id else { return nil }
        let parser = ISO8601DateFormatter()
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let startDate = start.dateTime.flatMap(parser.date) ?? start.date.flatMap(dateFormatter.date)
        let endDate = end.dateTime.flatMap(parser.date) ?? end.date.flatMap(dateFormatter.date)
        guard let startDate, let endDate else { return nil }
        return GoogleCalendarEventSnapshot(
            id: id,
            calendarID: calendarID,
            etag: etag,
            title: summary ?? "Без названия",
            description: description ?? "",
            startDate: startDate,
            endDate: endDate,
            isAllDay: start.date != nil,
            timeZoneID: start.timeZone ?? TimeZone.current.identifier,
            updatedAt: updated.flatMap(parser.date) ?? .distantPast,
            recurrence: recurrence ?? [],
            isDeleted: status == "cancelled"
        )
    }
}
