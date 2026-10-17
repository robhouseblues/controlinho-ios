import Foundation

/// Storage shared between the app and its Control Center extension through an App Group,
/// so controls can reach the paired TV without opening the app.
enum SharedStore {
    static let appGroup = "group.com.robhouseblues.controlinho"

    private static let tvKey = "savedTV"
    private static let defaults = UserDefaults(suiteName: appGroup) ?? .standard

    static func loadTV() -> SavedTV? {
        // Earlier versions kept the TV in the app's own defaults; move it over once.
        if defaults.data(forKey: tvKey) == nil, let old = UserDefaults.standard.data(forKey: tvKey) {
            defaults.set(old, forKey: tvKey)
            UserDefaults.standard.removeObject(forKey: tvKey)
        }
        guard let data = defaults.data(forKey: tvKey) else { return nil }
        return try? JSONDecoder().decode(SavedTV.self, from: data)
    }

    static func saveTV(_ tv: SavedTV?) {
        if let tv, let data = try? JSONEncoder().encode(tv) {
            defaults.set(data, forKey: tvKey)
        } else {
            defaults.removeObject(forKey: tvKey)
        }
    }
}

/// How the TV's remote-control socket is addressed. The app and the controls must use the
/// same client name so the TV recognizes both with the same pairing token.
enum TVRemoteSocket {
    static let clientName = Data("Controlinho".utf8).base64EncodedString()

    /// Newer TVs use `wss://…:8002` with a pairing token; pre-2018 models only `ws://…:8001`.
    static func url(for tv: SavedTV, legacy: Bool) -> URL? {
        var components = URLComponents()
        components.scheme = legacy ? "ws" : "wss"
        components.host = tv.host
        components.port = legacy ? 8001 : 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        var query = [URLQueryItem(name: "name", value: clientName)]
        if let token = tv.token, !legacy {
            query.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = query
        return components.url
    }

    /// The JSON message that presses a remote key.
    static func keyPayload(_ key: TVKey) -> String {
        let payload: [String: Any] = [
            "method": "ms.remote.control",
            "params": [
                "Cmd": "Click",
                "DataOfCmd": key.rawValue,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey",
            ],
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

/// Reports socket opens and accepts the self-signed certificate Samsung TVs serve on port 8002.
final class TVSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    var onOpen: ((URLSessionWebSocketTask) -> Void)?

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onOpen?(webSocketTask)
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let trust = challenge.protectionSpace.serverTrust,
            LocalNetwork.isPrivateIPv4(challenge.protectionSpace.host)
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}
