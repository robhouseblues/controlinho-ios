import Foundation

/// Storage shared between the app and its Control Center extension through an App Group,
/// so controls can reach the paired TVs without opening the app.
enum SharedStore {
    static let appGroup = "group.com.robhouseblues.controlinho"

    private static let tvsKey = "savedTVs"
    private static let activeKey = "activeTVHost"
    /// Where versions with a single TV kept it.
    private static let singleTVKey = "savedTV"
    private static let defaults = UserDefaults(suiteName: appGroup) ?? .standard

    /// Every saved TV, and the address of the one the remote and controls are pointed at.
    static func loadTVs() -> (tvs: [SavedTV], active: String?) {
        migrate()
        let tvs = defaults.data(forKey: tvsKey).flatMap { try? JSONDecoder().decode([SavedTV].self, from: $0) } ?? []
        return (tvs, defaults.string(forKey: activeKey))
    }

    static func saveTVs(_ tvs: [SavedTV], active: String?) {
        if let data = try? JSONEncoder().encode(tvs) {
            defaults.set(data, forKey: tvsKey)
        }
        defaults.set(active, forKey: activeKey)
    }

    /// The TV the remote and the Control Center controls are pointed at.
    static func loadTV() -> SavedTV? {
        let (tvs, active) = loadTVs()
        return tvs.first { $0.host == active } ?? tvs.first
    }

    /// Replaces the stored copy of a TV, matched by its address.
    static func updateTV(_ tv: SavedTV) {
        var (tvs, active) = loadTVs()
        guard let index = tvs.firstIndex(where: { $0.host == tv.host }) else { return }
        tvs[index] = tv
        saveTVs(tvs, active: active)
    }

    private static func migrate() {
        // The first versions kept the TV in the app's own defaults, the next ones a single
        // TV in the App Group. Move either into the list once.
        guard defaults.data(forKey: tvsKey) == nil else { return }
        let data = defaults.data(forKey: singleTVKey) ?? UserDefaults.standard.data(forKey: singleTVKey)
        if let data, let tv = try? JSONDecoder().decode(SavedTV.self, from: data) {
            saveTVs([tv], active: tv.host)
        }
        defaults.removeObject(forKey: singleTVKey)
        UserDefaults.standard.removeObject(forKey: singleTVKey)
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

/// Reports socket opens and failures, and accepts the self-signed certificates TVs serve
/// on their secure ports (Samsung 8002, LG 3001).
final class TVSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    var onOpen: ((URLSessionWebSocketTask) -> Void)?
    var onFail: ((Error?) -> Void)?

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onOpen?(webSocketTask)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onFail?(error)
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
