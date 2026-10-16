import Foundation
import Observation

/// Talks to a Samsung Tizen TV (2016+) over its remote-control WebSocket.
///
/// Newer TVs listen on `wss://<ip>:8002` with a self-signed certificate and hand back a
/// token after the user accepts the pairing prompt on screen. Older models only expose
/// plain `ws://<ip>:8001`, so we fall back to that when the secure port refuses us.
@MainActor
@Observable
final class SamsungTVClient {
    enum State: Equatable {
        case disconnected
        case connecting
        case waitingForApproval
        case connected
        case failed(String)
    }

    private(set) var state: State = .disconnected

    /// Called whenever the TV issues a new pairing token, so it can be persisted.
    var onTokenUpdate: ((String) -> Void)?

    /// Called each time the TV accepts the connection.
    var onConnected: (() -> Void)?

    private static let appName = Data("Controlinho".utf8).base64EncodedString()

    private var tv: SavedTV?
    private var task: URLSessionWebSocketTask?
    private var useLegacyPort = false
    private var pending: [String] = []
    private var approvalTimer: Task<Void, Never>?

    @ObservationIgnored
    private lazy var session: URLSession = {
        let delegate = SocketDelegate()
        delegate.onOpen = { [weak self] task in
            Task { @MainActor in self?.socketDidOpen(task) }
        }
        return URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
    }()

    // MARK: Connection

    func connect(to tv: SavedTV) {
        disconnect()
        self.tv = tv
        useLegacyPort = false
        open()
    }

    func reconnectIfNeeded() {
        guard tv != nil else { return }
        switch state {
        case .disconnected, .failed: open()
        default: break
        }
    }

    func disconnect() {
        approvalTimer?.cancel()
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        pending.removeAll()
        state = .disconnected
    }

    private func open() {
        guard let tv else { return }
        var components = URLComponents()
        components.scheme = useLegacyPort ? "ws" : "wss"
        components.host = tv.host
        components.port = useLegacyPort ? 8001 : 8002
        components.path = "/api/v2/channels/samsung.remote.control"
        var query = [URLQueryItem(name: "name", value: Self.appName)]
        if let token = tv.token, !useLegacyPort {
            query.append(URLQueryItem(name: "token", value: token))
        }
        components.queryItems = query
        guard let url = components.url else {
            state = .failed("Invalid TV address.")
            return
        }

        task?.cancel(with: .goingAway, reason: nil)
        let task = session.webSocketTask(with: url)
        self.task = task
        state = .connecting
        task.resume()
        receive(on: task)

        // Give up if the TV doesn't even accept the connection within a few seconds.
        approvalTimer?.cancel()
        approvalTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled, let self, self.task === task, self.state == .connecting else { return }
            task.cancel(with: .goingAway, reason: nil)
            self.handleFailure(URLError(.timedOut))
        }
    }

    /// The socket is open but stays silent while the TV shows its "Allow" prompt.
    private func socketDidOpen(_ task: URLSessionWebSocketTask) {
        guard self.task === task, state == .connecting else { return }
        approvalTimer?.cancel()
        approvalTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled, let self, self.task === task, self.state == .connecting else { return }
            self.state = .waitingForApproval
        }
    }

    private func receive(on task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.task === task else { return }
                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receive(on: task)
                case .failure(let error):
                    self.handleFailure(error)
                }
            }
        }
    }

    private func handleFailure(_ error: Error) {
        approvalTimer?.cancel()
        task = nil
        // A never-connected secure socket usually means a pre-2018 TV without port 8002.
        if state == .connecting && !useLegacyPort {
            useLegacyPort = true
            open()
            return
        }
        if state == .connected {
            state = .disconnected
        } else {
            // Neither port answered, so the TV is likely off; try the secure port first next time.
            if state == .connecting { useLegacyPort = false }
            state = .failed("Couldn't reach the TV. Make sure it's on and on the same Wi-Fi.")
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let raw): data = raw
        @unknown default: return
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = json["event"] as? String
        else { return }

        switch event {
        case "ms.channel.connect":
            approvalTimer?.cancel()
            state = .connected
            if let token = (json["data"] as? [String: Any])?["token"] as? String {
                tv?.token = token
                onTokenUpdate?(token)
            }
            flushPending()
            onConnected?()
        case "ms.channel.unauthorized":
            approvalTimer?.cancel()
            state = .failed("The TV denied the connection. Allow Controlinho under Settings › General › External Device Manager.")
        case "ms.channel.timeOut":
            approvalTimer?.cancel()
            state = .failed("Timed out waiting for you to accept on the TV.")
        default:
            break
        }
    }

    // MARK: Commands

    func send(_ key: TVKey) {
        enqueue([
            "method": "ms.remote.control",
            "params": [
                "Cmd": "Click",
                "DataOfCmd": key.rawValue,
                "Option": "false",
                "TypeOfRemote": "SendRemoteKey",
            ],
        ])
    }

    func launch(_ app: TVApp) {
        enqueue([
            "method": "ms.channel.emit",
            "params": [
                "event": "ed.apps.launch",
                "to": "host",
                "data": ["appId": app.id, "action_type": "DEEP_LINK"],
            ],
        ])
    }

    private func enqueue(_ payload: [String: Any]) {
        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let text = String(data: data, encoding: .utf8)
        else { return }

        if state == .connected, let task {
            task.send(.string(text)) { _ in }
        } else {
            // Buffer a few presses and transparently reconnect (the TV drops idle sockets).
            pending = Array((pending + [text]).suffix(5))
            reconnectIfNeeded()
        }
    }

    private func flushPending() {
        guard let task else { return }
        for text in pending {
            task.send(.string(text)) { _ in }
        }
        pending.removeAll()
    }
}

/// Reports socket opens and accepts the self-signed certificate Samsung TVs serve on port 8002.
private final class SocketDelegate: NSObject, URLSessionWebSocketDelegate {
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
