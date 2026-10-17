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
        case .cantWake: "Add the TV's MAC address or SmartThings in Controlinho to turn it on."
        }
    }
}

/// Short-lived remote used by the Control Center controls: connect, press one key, disconnect.
enum QuickRemote {
    /// Presses one key on the TV.
    static func press(_ key: TVKey) async throws {
        guard var tv = SharedStore.loadTV() else { throw QuickRemoteError.noTV }
        let (session, socket) = try await open(&tv)
        defer {
            socket.cancel(with: .normalClosure, reason: nil)
            session.finishTasksAndInvalidate()
        }
        try await socket.send(.string(TVRemoteSocket.keyPayload(key)))
        // Give the message a moment to leave before the extension is suspended.
        try? await Task.sleep(for: .milliseconds(250))
    }

    /// Switches a TV in standby on, over the local network and/or SmartThings.
    static func wake(_ tv: SavedTV) async throws {
        var didSomething = false
        if let mac = tv.wakeMAC {
            WakeOnLAN.wake(mac: mac, host: tv.host)
            didSomething = true
        }
        if let deviceID = tv.smartThingsDeviceID {
            let smartThings = await SmartThings()
            if await smartThings.isSignedIn {
                try await smartThings.turnOn(deviceID: deviceID)
                didSomething = true
            }
        }
        guard didSomething else { throw QuickRemoteError.cantWake }
        // Wake-on-LAN packets are sent asynchronously; let them go out.
        try? await Task.sleep(for: .milliseconds(500))
    }

    private static func open(_ tv: inout SavedTV) async throws -> (URLSession, URLSessionWebSocketTask) {
        do {
            return try await connect(&tv, legacy: false)
        } catch QuickRemoteError.notPaired {
            throw QuickRemoteError.notPaired
        } catch {
            // Pre-2018 TVs only listen on the plain port.
            return try await connect(&tv, legacy: true)
        }
    }

    private static func connect(_ tv: inout SavedTV, legacy: Bool) async throws -> (URLSession, URLSessionWebSocketTask) {
        guard let url = TVRemoteSocket.url(for: tv, legacy: legacy) else { throw QuickRemoteError.unreachable }
        let session = URLSession(configuration: .ephemeral, delegate: TVSocketDelegate(), delegateQueue: nil)
        let socket = session.webSocketTask(with: url)
        socket.resume()
        do {
            let token = try await withThrowingTaskGroup(of: String?.self) { group in
                group.addTask { try await waitForConnect(socket) }
                group.addTask {
                    try await Task.sleep(for: .seconds(4))
                    throw QuickRemoteError.unreachable
                }
                defer { group.cancelAll() }
                return try await group.next() ?? nil
            }
            // The TV may hand out a fresh pairing token; keep the app in sync.
            if let token, token != tv.token, !legacy {
                tv.token = token
                SharedStore.saveTV(tv)
            }
            return (session, socket)
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            session.invalidateAndCancel()
            throw error
        }
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
