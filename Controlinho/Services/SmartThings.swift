import Foundation
import Observation

/// Turns the TV on through Samsung's SmartThings cloud, which works even when the
/// TV's local network connection is asleep.
///
/// Uses an OAuth-In app the user registers with the SmartThings CLI. Access tokens last
/// 24 hours; the refresh token lasts about a month and is renewed on every refresh, so
/// the app stays signed in as long as it's opened at least once a month.
@MainActor
@Observable
final class SmartThings {
    struct Credentials: Codable, Equatable {
        var clientID: String
        var clientSecret: String
        var redirectURL: String
    }

    struct Device: Identifiable, Hashable, Decodable {
        struct OCF: Hashable, Decodable { let ocfDeviceType: String? }
        let deviceId: String
        let label: String?
        let name: String?
        let ocf: OCF?

        var id: String { deviceId }
        var displayName: String { label ?? name ?? "Unnamed device" }
        var isTV: Bool {
            ocf?.ocfDeviceType == "oic.d.tv" || displayName.localizedCaseInsensitiveContains("tv")
        }
    }

    enum Failure: LocalizedError {
        case notSignedIn
        case sessionExpired
        case badCallback
        case server(Int, String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: "Sign in to SmartThings first."
            case .sessionExpired: "Your SmartThings sign-in expired. Sign in again in TV Settings."
            case .badCallback: "SmartThings didn't return a sign-in code. Check the redirect URL."
            case .server(let status, let message): "SmartThings error \(status): \(message)"
            }
        }
    }

    static let callbackScheme = "controlinho"
    static let scopes = "r:devices:* x:devices:*"

    private struct Tokens: Codable {
        var access: String
        var refresh: String
        var expiresAt: Date
    }

    private static let credentialsKey = "smartthings.credentials"
    private static let tokensKey = "smartthings.tokens"
    private static let api = URL(string: "https://api.smartthings.com")!

    private(set) var credentials: Credentials?
    private var tokens: Tokens?
    @ObservationIgnored private var refreshTask: Task<Tokens, Error>?

    var isConfigured: Bool { credentials != nil }
    var isSignedIn: Bool { tokens != nil }

    init() {
        credentials = Keychain.value(Credentials.self, for: Self.credentialsKey)
        tokens = Keychain.value(Tokens.self, for: Self.tokensKey)
    }

    // MARK: Setup

    func save(_ newCredentials: Credentials?) {
        if newCredentials != credentials { signOut() }
        credentials = newCredentials
        Keychain.setValue(newCredentials, for: Self.credentialsKey)
    }

    func signOut() {
        setTokens(nil)
    }

    /// The Samsung login page to show in a web authentication session.
    func authorizeURL(state: String) -> URL? {
        guard let credentials else { return nil }
        var components = URLComponents(url: Self.api.appending(path: "oauth/authorize"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: credentials.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: credentials.redirectURL),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "state", value: state),
        ]
        return components?.url
    }

    /// Exchanges the code in the `controlinho://oauth?code=…` callback for tokens.
    func completeSignIn(callback: URL, expectedState: String) async throws {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard
            let credentials,
            items.first(where: { $0.name == "state" })?.value == expectedState,
            let code = items.first(where: { $0.name == "code" })?.value
        else { throw Failure.badCallback }

        setTokens(try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": credentials.clientID,
            "redirect_uri": credentials.redirectURL,
        ]))
    }

    /// Refreshes an expired access token. Calling this on launch keeps the refresh token alive.
    func refreshIfNeeded() async {
        _ = try? await validAccessToken()
    }

    // MARK: API

    func devices() async throws -> [Device] {
        struct Page: Decodable { let items: [Device] }
        let data = try await call("v1/devices?capability=switch")
        let devices = try JSONDecoder().decode(Page.self, from: data).items
        let tvs = devices.filter(\.isTV)
        return (tvs.isEmpty ? devices : tvs).sorted { $0.displayName < $1.displayName }
    }

    func turnOn(deviceID: String) async throws {
        let body: [String: Any] = [
            "commands": [["component": "main", "capability": "switch", "command": "on"]],
        ]
        _ = try await call("v1/devices/\(deviceID)/commands", body: body)
    }

    private func call(_ path: String, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: path, relativeTo: Self.api)!)
        request.setValue("Bearer \(try await validAccessToken())", forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            signOut()
            throw Failure.sessionExpired
        }
        guard (200..<300).contains(status) else {
            throw Failure.server(status, String(decoding: data.prefix(200), as: UTF8.self))
        }
        return data
    }

    // MARK: Tokens

    private func validAccessToken() async throws -> String {
        guard let tokens, let credentials else { throw Failure.notSignedIn }
        if tokens.expiresAt > .now.addingTimeInterval(300) { return tokens.access }

        // Refresh tokens are single-use, so concurrent callers must share one refresh.
        if let refreshTask { return try await refreshTask.value.access }
        let task = Task {
            try await requestTokens([
                "grant_type": "refresh_token",
                "refresh_token": tokens.refresh,
                "client_id": credentials.clientID,
            ])
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            setTokens(fresh)
            return fresh.access
        } catch Failure.server(let status, _) where (400..<500).contains(status) {
            // The refresh token was revoked or unused for too long.
            signOut()
            throw Failure.sessionExpired
        }
    }

    private func requestTokens(_ form: [String: String]) async throws -> Tokens {
        guard let credentials else { throw Failure.notSignedIn }
        var request = URLRequest(url: Self.api.appending(path: "oauth/token"))
        request.httpMethod = "POST"
        let basic = Data("\(credentials.clientID):\(credentials.clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = Data(form.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
        }.joined(separator: "&").utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw Failure.server(status, String(decoding: data.prefix(200), as: UTF8.self))
        }

        struct Response: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Double
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return Tokens(
            access: decoded.access_token,
            refresh: decoded.refresh_token,
            expiresAt: .now.addingTimeInterval(decoded.expires_in)
        )
    }

    private func setTokens(_ newTokens: Tokens?) {
        tokens = newTokens
        Keychain.setValue(newTokens, for: Self.tokensKey)
    }
}
