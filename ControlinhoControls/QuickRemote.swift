import Foundation

enum QuickRemoteError: LocalizedError {
    case noTV
    case notPaired
    case unreachable
    case cantWake

    var errorDescription: String? {
        switch self {
        case .noTV: "Open Controlinho and connect your TV first."
        case .notPaired: "Open Controlinho to pair with your TV first."
        case .unreachable: "Couldn't reach the TV."
        case .cantWake: "Add the TV's MAC address in Controlinho to turn it on."
        }
    }
}

/// Remote used by the Control Center controls.
enum QuickRemote {
    /// Presses one key on the TV.
    static func press(_ key: TVKey) async throws {
        guard let tv = SharedStore.loadTV() else { throw QuickRemoteError.noTV }
        switch tv.kind {
        case .samsung:
            try await RemoteConnection.shared.send(TVRemoteSocket.keyPayload(key), to: tv)
        case .lg:
            try await LGQuickRemote.shared.press(key, on: tv)
        }
    }

    /// Switches a TV in standby on over the local network.
    static func wake(_ tv: SavedTV) async throws {
        guard let mac = tv.wakeMAC else { throw QuickRemoteError.cantWake }
        WakeOnLAN.wake(mac: mac, host: tv.host)
        // Wake-on-LAN packets are sent asynchronously; let them go out.
        try? await Task.sleep(for: .milliseconds(300))
    }
}

/// Keeps the TV socket open for a short while after a press, so a burst of presses
/// (say, several volume-ups) skips the connection handshake and feels instant.
actor RemoteConnection {
    static let shared = RemoteConnection()

    private static let connectTimeout: Duration = .milliseconds(2500)
    private static let idleTimeout: Duration = .seconds(20)

    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var host: String?
    private var closeTimer: Task<Void, Never>?

    func send(_ text: String, to tv: SavedTV) async throws {
        if let socket, host == tv.host, socket.state == .running {
            do {
                try await socket.send(.string(text))
                keepAlive()
                return
            } catch {
                // The TV dropped the idle connection; open a fresh one below.
                close()
            }
        }
        try await open(tv)
        try await socket?.send(.string(text))
        keepAlive()
    }

    private func open(_ tv: SavedTV) async throws {
        var tv = tv
        // Try the port this TV is known to use first; only probe the other one if unknown.
        let preferred = tv.usesLegacyPort ?? false
        do {
            try await connect(&tv, legacy: preferred)
        } catch QuickRemoteError.notPaired {
            throw QuickRemoteError.notPaired
        } catch where tv.usesLegacyPort == nil {
            try await connect(&tv, legacy: !preferred)
        }
    }

    private func connect(_ tv: inout SavedTV, legacy: Bool) async throws {
        guard let url = TVRemoteSocket.url(for: tv, legacy: legacy) else { throw QuickRemoteError.unreachable }
        let session = URLSession(configuration: .ephemeral, delegate: TVSocketDelegate(), delegateQueue: nil)
        let socket = session.webSocketTask(with: url)
        socket.resume()
        do {
            let token = try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask { try await Self.waitForConnect(socket) }
                group.addTask {
                    try await Task.sleep(for: Self.connectTimeout)
                    throw QuickRemoteError.unreachable
                }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }
            // Keep the app in sync with a fresh pairing token and the port that worked.
            var changed = false
            if let token, token != tv.token, !legacy {
                tv.token = token
                changed = true
            }
            if tv.usesLegacyPort != legacy {
                tv.usesLegacyPort = legacy
                changed = true
            }
            if changed { SharedStore.updateTV(tv) }
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            throw error
        }
        self.session = session
        self.socket = socket
        self.host = tv.host
    }

    private func keepAlive() {
        closeTimer?.cancel()
        closeTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard !Task.isCancelled else { return }
            await self?.close()
        }
    }

    private func close() {
        closeTimer?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        session?.finishTasksAndInvalidate()
        socket = nil
        session = nil
        host = nil
    }

    /// Waits for the TV to accept the connection and returns its pairing token, if any.
    private static func waitForConnect(_ socket: URLSessionWebSocketTask) async throws -> String? {
        while true {
            let message = try await socket.receive()
            let data: Data
            switch message {
            case .string(let text): data = Data(text.utf8)
            case .data(let raw): data = raw
            @unknown default: continue
            }
            guard
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let event = json["event"] as? String
            else { continue }
            switch event {
            case "ms.channel.connect":
                return (json["data"] as? [String: Any])?["token"] as? String
            case "ms.channel.unauthorized", "ms.channel.timeOut":
                throw QuickRemoteError.notPaired
            default:
                continue
            }
        }
    }
}

/// LG counterpart of `RemoteConnection`: one shared connection, kept open for a short while
/// after each press. It never shows a pairing prompt; that only happens in the app.
actor LGQuickRemote {
    static let shared = LGQuickRemote()

    private static let idleTimeout: Duration = .seconds(20)

    private var connection: LGConnection?
    private var closeTimer: Task<Void, Never>?

    func press(_ key: TVKey, on tv: SavedTV) async throws {
        let mac = tv.wakeMAC
        let host = tv.host
        let wake: @Sendable () -> Void = { if let mac { WakeOnLAN.wake(mac: mac, host: host) } }

        // A reused connection may have been dropped by the TV; retry once on a fresh one.
        for attempt in 0..<2 {
            let connection = connection(for: tv)
            do {
                try await connection.connect(allowPrompt: false)
                await remember(connection, in: tv)
                try await connection.press(key, wake: wake)
                keepAlive()
                return
            } catch LGError.notPaired {
                await close()
                throw QuickRemoteError.notPaired
            } catch {
                await close()
                if attempt == 1 { throw QuickRemoteError.unreachable }
            }
        }
    }

    private func connection(for tv: SavedTV) -> LGConnection {
        if let connection, connection.host == tv.host { return connection }
        let fresh = LGConnection(host: tv.host, clientKey: tv.token, preferLegacyPort: tv.usesLegacyPort ?? false)
        connection = fresh
        return fresh
    }

    /// Keeps the app in sync with the port that worked.
    private func remember(_ connection: LGConnection, in tv: SavedTV) async {
        let legacy = await connection.usedLegacyPort
        guard tv.usesLegacyPort != legacy, var current = SharedStore.loadTV(), current.host == tv.host else { return }
        current.usesLegacyPort = legacy
        SharedStore.updateTV(current)
    }

    private func keepAlive() {
        closeTimer?.cancel()
        closeTimer = Task { [weak self] in
            do { try await Task.sleep(for: Self.idleTimeout) } catch { return }
            await self?.close()
        }
    }

    private func close() async {
        closeTimer?.cancel()
        await connection?.close()
        connection = nil
    }
}
