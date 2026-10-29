import Foundation

enum LGError: Error {
    case unreachable
    case notPaired
    case requestFailed(String)
}

/// A connection to an LG webOS TV's remote API ("SSAP" over WebSocket), shared by the app
/// and the Control Center controls.
///
/// Newer TVs listen on `wss://<ip>:3001` with a self-signed certificate; older ones on plain
/// `ws://<ip>:3000`. The first connection shows an Accept prompt on the TV, which hands back
/// a client key that skips the prompt from then on. Arrows, OK, Back and Home go through a
/// second "pointer input" socket; everything else is a request on the main one.
actor LGConnection {
    let host: String
    private(set) var clientKey: String?
    private(set) var usedLegacyPort = false
    private var preferLegacyPort: Bool

    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var pointerSession: URLSession?
    private var pointer: URLSessionWebSocketTask?
    private var registered = false
    private var registration: CheckedContinuation<String, Error>?
    private var promptSeen = false
    private var pending: [String: CheckedContinuation<[String: Any], Error>] = [:]
    private var nextID = 1
    private var onPrompt: (@Sendable () -> Void)?
    private var onClose: (@Sendable () -> Void)?
    private var onKeyboard: (@Sendable (Bool) -> Void)?

    private static let keyboardID = "keyboard"

    init(host: String, clientKey: String?, preferLegacyPort: Bool) {
        self.host = host
        self.clientKey = clientKey
        self.preferLegacyPort = preferLegacyPort
    }

    var isReady: Bool {
        registered && socket?.state == .running
    }

    /// Whether something at `host` speaks the LG remote protocol, without pairing.
    static func probe(host: String) async -> Bool {
        for address in ["wss://\(host):3001/", "ws://\(host):3000/"] {
            guard let url = URL(string: address) else { continue }
            if let opened = try? await WebSocketOpener.open(url, timeout: .milliseconds(1500)) {
                opened.1.cancel(with: .normalClosure, reason: nil)
                opened.0.invalidateAndCancel()
                return true
            }
        }
        return false
    }

    // MARK: Connecting

    /// Connects and registers, returning the client key. With `allowPrompt` false it fails
    /// instead of showing the pairing prompt (the Control Center controls can't show one).
    @discardableResult
    func connect(
        allowPrompt: Bool = true,
        onPrompt: (@Sendable () -> Void)? = nil,
        onClose: (@Sendable () -> Void)? = nil
    ) async throws -> String {
        if isReady, let clientKey { return clientKey }
        close()
        if !allowPrompt && clientKey == nil { throw LGError.notPaired }
        self.onPrompt = onPrompt
        self.onClose = onClose

        var lastError: Error = LGError.unreachable
        for legacy in [preferLegacyPort, !preferLegacyPort] {
            guard let url = URL(string: legacy ? "ws://\(host):3000/" : "wss://\(host):3001/") else { continue }
            do {
                let (session, socket) = try await WebSocketOpener.open(url, timeout: .milliseconds(2500))
                self.session = session
                self.socket = socket
                usedLegacyPort = legacy
                preferLegacyPort = legacy
                break
            } catch {
                lastError = error
            }
        }
        guard let socket else { throw lastError }
        startReceiving(socket)

        let key = try await register(on: socket)
        clientKey = key
        registered = true
        return key
    }

    func close() {
        registered = false
        finishRegistration(.failure(LGError.unreachable))
        for (_, continuation) in pending { continuation.resume(throwing: LGError.unreachable) }
        pending.removeAll()
        socket?.cancel(with: .normalClosure, reason: nil)
        session?.finishTasksAndInvalidate()
        pointer?.cancel(with: .normalClosure, reason: nil)
        pointerSession?.finishTasksAndInvalidate()
        socket = nil
        session = nil
        pointer = nil
        pointerSession = nil
    }

    private func register(on socket: URLSessionWebSocketTask) async throws -> String {
        var payload = Self.registrationPayload
        if let clientKey { payload["client-key"] = clientKey }
        let text = Self.json(["type": "register", "id": "register_0", "payload": payload])
        promptSeen = false

        // A known key registers right away. Otherwise the TV shows a prompt; give the
        // person a minute to accept it.
        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self else { return }
            if await self.promptSeen {
                do { try await Task.sleep(for: .seconds(52)) } catch { return }
                await self.finishRegistration(.failure(LGError.notPaired))
            } else {
                await self.finishRegistration(.failure(LGError.unreachable))
            }
        }
        defer { timeout.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            registration = continuation
            Task {
                do {
                    try await socket.send(.string(text))
                } catch {
                    self.finishRegistration(.failure(error))
                }
            }
        }
    }

    private func finishRegistration(_ result: Result<String, Error>) {
        let continuation = registration
        registration = nil
        continuation?.resume(with: result)
    }

    // MARK: Receiving

    private func startReceiving(_ socket: URLSessionWebSocketTask) {
        Task { [weak self] in
            while true {
                do {
                    let message = try await socket.receive()
                    await self?.handle(message)
                } catch {
                    await self?.socketClosed(socket)
                    return
                }
            }
        }
    }

    private func socketClosed(_ closed: URLSessionWebSocketTask) {
        guard closed === socket else { return }
        let onClose = onClose
        close()
        onClose?()
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data
        switch message {
        case .string(let text): data = Data(text.utf8)
        case .data(let raw): data = raw
        @unknown default: return
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        let type = json["type"] as? String
        let id = json["id"] as? String
        let payload = json["payload"] as? [String: Any] ?? [:]

        if id == "register_0" {
            switch type {
            case "response" where payload["pairingType"] as? String == "PROMPT":
                promptSeen = true
                onPrompt?()
            case "registered":
                finishRegistration(.success(payload["client-key"] as? String ?? clientKey ?? ""))
            case "error":
                finishRegistration(.failure(LGError.notPaired))
            default:
                break
            }
            return
        }

        if id == Self.keyboardID {
            if let widget = payload["currentWidget"] as? [String: Any] {
                onKeyboard?(widget["focus"] as? Bool ?? false)
            }
            return
        }

        guard let id, let continuation = pending.removeValue(forKey: id) else { return }
        if type == "error" {
            continuation.resume(throwing: LGError.requestFailed(json["error"] as? String ?? "Request failed"))
        } else if payload["returnValue"] as? Bool == false {
            continuation.resume(throwing: LGError.requestFailed(payload["errorText"] as? String ?? "Request failed"))
        } else {
            continuation.resume(returning: payload)
        }
    }

    // MARK: Requests

    /// Sends an `ssap://` request and waits for its reply.
    @discardableResult
    private func request(_ uri: String, _ payload: [String: Any]? = nil) async throws -> [String: Any] {
        guard let socket, registered else { throw LGError.unreachable }
        let id = "req_\(nextID)"
        nextID += 1
        var message: [String: Any] = ["type": "request", "id": id, "uri": "ssap://\(uri)"]
        if let payload { message["payload"] = payload }
        let text = Self.json(message)

        let timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            await self?.failRequest(id, LGError.unreachable)
        }
        defer { timeout.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            Task {
                do {
                    try await socket.send(.string(text))
                } catch {
                    self.failRequest(id, error)
                }
            }
        }
    }

    /// Sends a request without waiting, for commands the TV may not answer (like turning off).
    private func fire(_ uri: String) async throws {
        guard let socket, registered else { throw LGError.unreachable }
        let id = "req_\(nextID)"
        nextID += 1
        try await socket.send(.string(Self.json(["type": "request", "id": id, "uri": "ssap://\(uri)"])))
    }

    private func failRequest(_ id: String, _ error: Error) {
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    /// Presses a button over the pointer input socket, opening it the first time.
    private func button(_ name: String) async throws {
        if pointer?.state != .running {
            let reply = try await request("com.webos.service.networkinput/getPointerInputSocket")
            guard let path = reply["socketPath"] as? String, let url = URL(string: path) else {
                throw LGError.requestFailed("The TV didn't offer a remote input socket.")
            }
            let (session, socket) = try await WebSocketOpener.open(url, timeout: .seconds(3))
            pointerSession = session
            pointer = socket
            // The TV may send messages on this socket too; read and drop them.
            Task { while (try? await socket.receive()) != nil {} }
        }
        try await pointer?.send(.string("type:button\nname:\(name)\n\n"))
    }

    // MARK: Commands

    /// Presses a remote key. `wake` switches the TV on from standby (Wake-on-LAN), since
    /// the LG API itself can only turn TVs off.
    func press(_ key: TVKey, wake: @Sendable () -> Void) async throws {
        switch key {
        case .power: try await togglePower(wake: wake)
        case .volumeUp: try await request("audio/volumeUp")
        case .volumeDown: try await request("audio/volumeDown")
        case .channelUp: try await request("tv/channelUp")
        case .channelDown: try await request("tv/channelDown")
        case .play: try await request("media.controls/play")
        case .pause: try await request("media.controls/pause")
        case .rewind: try await request("media.controls/rewind")
        case .fastForward: try await request("media.controls/fastForward")
        default:
            if let name = Self.buttonName(for: key) { try await button(name) }
        }
    }

    private func togglePower(wake: @Sendable () -> Void) async throws {
        // In quick-start standby the API stays reachable while the TV is off.
        let state = (try? await request("com.webos.service.tvpower/power/getPowerState"))?["state"] as? String
        switch state {
        case "Active Standby", "Suspend", "Power Off":
            wake()
        case "Screen Off":
            try await request("com.webos.service.tvpower/power/turnOnScreen")
        default:
            try await fire("system/turnOff")
        }
    }

    /// Reports when the TV shows or hides its on-screen keyboard. Needs a new call after
    /// each reconnect.
    func watchKeyboard(_ onChange: @escaping @Sendable (Bool) -> Void) async throws {
        guard let socket, registered else { throw LGError.unreachable }
        onKeyboard = onChange
        let message = ["type": "subscribe", "id": Self.keyboardID, "uri": "ssap://com.webos.service.ime/registerRemoteKeyboard"]
        try await socket.send(.string(Self.json(message)))
    }

    /// Edits the text box the TV's keyboard is filling: deletes `count` characters before
    /// the cursor, then types `text`.
    func type(deleting count: Int, inserting text: String) async throws {
        if count > 0 { try await request("com.webos.service.ime/deleteCharacters", ["count": count]) }
        if !text.isEmpty { try await request("com.webos.service.ime/insertText", ["text": text, "replace": 0]) }
    }

    func sendEnter() async throws {
        try await request("com.webos.service.ime/sendEnterKey")
    }

    func launch(appID: String) async throws {
        try await request("system.launcher/launch", ["id": appID])
    }

    /// The TV's model and the MAC of the interface it's connected with.
    func info() async -> (model: String?, mac: String?, wired: Bool?) {
        let system = try? await request("system/getSystemInfo")
        let network = try? await request("com.webos.service.connectionmanager/getinfo")
        let wired = network?["wiredInfo"] as? [String: Any]
        let wifi = network?["wifiInfo"] as? [String: Any]
        let isWired = (wired?["state"] as? String) == "connected"
        let mac = (isWired ? wired?["macAddress"] : wifi?["macAddress"]) as? String
        return (system?["modelName"] as? String, mac, network == nil ? nil : isWired)
    }

    private static func buttonName(for key: TVKey) -> String? {
        switch key {
        case .up: "UP"
        case .down: "DOWN"
        case .left: "LEFT"
        case .right: "RIGHT"
        case .enter: "ENTER"
        case .back: "BACK"
        case .home: "HOME"
        case .menu: "MENU"
        case .source: "INPUT_HUB"
        case .info: "INFO"
        case .guide: "GUIDE"
        case .exit: "EXIT"
        case .mute: "MUTE"
        default:
            // Digits: KEY_0 … KEY_9 map to "0" … "9".
            key.rawValue.hasPrefix("KEY_") ? Int(key.rawValue.dropFirst(4)).map(String.init) : nil
        }
    }

    // MARK: Messages

    private static func json(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// Permissions requested when pairing (the same set the Home Assistant integration uses).
    private static let registrationPayload: [String: Any] = [
        "forcePairing": false,
        "pairingType": "PROMPT",
        "manifest": [
            "manifestVersion": 1,
            "appVersion": "1.1",
            "permissions": [
                "APP_TO_APP", "CLOSE", "CONTROL_AUDIO", "CONTROL_DISPLAY", "CONTROL_INPUT_JOYSTICK",
                "CONTROL_INPUT_MEDIA_PLAYBACK", "CONTROL_INPUT_MEDIA_RECORDING", "CONTROL_INPUT_TEXT",
                "CONTROL_INPUT_TV", "CONTROL_MOUSE_AND_KEYBOARD", "CONTROL_POWER", "CONTROL_TV_SCREEN",
                "LAUNCH", "LAUNCH_WEBAPP", "READ_APP_STATUS", "READ_COUNTRY_INFO", "READ_CURRENT_CHANNEL",
                "READ_INPUT_DEVICE_LIST", "READ_INSTALLED_APPS", "READ_LGE_SDX", "READ_LGE_TV_INPUT_EVENTS",
                "READ_NETWORK_STATE", "READ_NOTIFICATIONS", "READ_POWER_STATE", "READ_RUNNING_APPS",
                "READ_SETTINGS", "READ_TV_CHANNEL_LIST", "READ_TV_CURRENT_TIME", "READ_UPDATE_INFO",
                "SEARCH", "TEST_OPEN", "TEST_PROTECTED", "TEST_SECURE", "UPDATE_FROM_REMOTE_APP",
                "WRITE_NOTIFICATION_ALERT", "WRITE_NOTIFICATION_TOAST", "WRITE_SETTINGS",
            ],
        ],
    ]
}

/// Opens a WebSocket and waits until the server accepts it.
enum WebSocketOpener {
    static func open(_ url: URL, timeout: Duration) async throws -> (URLSession, URLSessionWebSocketTask) {
        let waiter = OpenWaiter()
        let delegate = TVSocketDelegate()
        delegate.onOpen = { _ in waiter.finish(nil) }
        delegate.onFail = { error in waiter.finish(error ?? LGError.unreachable) }
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        let socket = session.webSocketTask(with: url)
        do {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask { try await waiter.wait { socket.resume() } }
                group.addTask {
                    try await Task.sleep(for: timeout)
                    throw LGError.unreachable
                }
                defer { group.cancelAll() }
                _ = try await group.next()
            }
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            throw error
        }
        return (session, socket)
    }
}

/// Bridges the socket delegate's open/fail callbacks to async code, resuming exactly once.
private final class OpenWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var result: Result<Void, Error>?

    func wait(starting start: () -> Void) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result)
                    return
                }
                self.continuation = continuation
                lock.unlock()
                start()
            }
        } onCancel: {
            finish(CancellationError())
        }
    }

    func finish(_ error: Error?) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        let outcome: Result<Void, Error> = error.map { .failure($0) } ?? .success(())
        result = outcome
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: outcome)
    }
}
