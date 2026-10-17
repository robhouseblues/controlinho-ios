import Foundation

/// Drives an LG webOS TV (2014+) for the app, on top of the shared `LGConnection`.
@MainActor
final class LGDriver: TVDriver {
    var onStateChange: ((TVConnectionState) -> Void)?
    var onTokenUpdate: ((String) -> Void)?
    var onPortConfirmed: ((Bool) -> Void)?

    private var tv: SavedTV
    private let connection: LGConnection
    private var state: TVConnectionState = .disconnected {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    private var connecting: Task<Bool, Never>?
    /// Presses run one after another, in the order they were made.
    private var lastCommand: Task<Void, Never>?

    init(tv: SavedTV) {
        self.tv = tv
        connection = LGConnection(host: tv.host, clientKey: tv.token, preferLegacyPort: tv.usesLegacyPort ?? false)
    }

    func connect() {
        _ = ensureConnected()
    }

    func reconnectIfNeeded() {
        switch state {
        case .disconnected, .failed: connect()
        default: break
        }
    }

    func disconnect() {
        connecting?.cancel()
        connecting = nil
        let connection = connection
        Task { await connection.close() }
        state = .disconnected
    }

    func send(_ key: TVKey) {
        let previous = lastCommand
        let connection = connection
        let wake = wakeAction
        lastCommand = Task { [weak self] in
            await previous?.value
            guard let self, await self.ensureConnected().value else { return }
            try? await connection.press(key, wake: wake)
        }
    }

    func launch(_ app: TVApp) async -> TVLaunchResult {
        guard await ensureConnected().value else { return .launched }
        do {
            try await connection.launch(appID: app.lgID)
            return .launched
        } catch LGError.requestFailed {
            return .notInstalled
        } catch {
            return .launched
        }
    }

    func fetchInfo() async -> DiscoveredTV? {
        guard state == .connected else { return nil }
        let info = await connection.info()
        return DiscoveredTV(
            host: tv.host,
            name: info.model.map { "LG \($0)" } ?? tv.name,
            model: info.model,
            mac: info.mac,
            isWired: info.wired ?? false,
            brand: .lg,
            macMatchesConnection: info.mac != nil
        )
    }

    /// Connects (or joins a connection in progress) and reports whether it worked.
    private func ensureConnected() -> Task<Bool, Never> {
        if state == .connected { return Task { true } }
        if let connecting { return connecting }
        state = .connecting
        let connection = connection
        let task = Task { [weak self] () -> Bool in
            do {
                let key = try await connection.connect(
                    onPrompt: { [weak self] in Task { @MainActor in self?.state = .waitingForApproval } },
                    onClose: { [weak self] in Task { @MainActor in self?.connectionLost() } }
                )
                let legacy = await connection.usedLegacyPort
                guard let self else { return false }
                self.connecting = nil
                if !key.isEmpty, key != self.tv.token {
                    self.tv.token = key
                    self.onTokenUpdate?(key)
                }
                self.onPortConfirmed?(legacy)
                self.state = .connected
                return true
            } catch LGError.notPaired {
                self?.connecting = nil
                self?.state = .failed("The TV didn't accept the pairing request. Try again and choose Accept on the TV.")
            } catch {
                self?.connecting = nil
                self?.state = .failed("Couldn't reach the TV. Make sure it's on and on the same Wi-Fi.")
            }
            return false
        }
        connecting = task
        return task
    }

    private func connectionLost() {
        if state == .connected { state = .disconnected }
    }

    /// Wake-on-LAN, for the power key when the TV reports it's in standby.
    private var wakeAction: @Sendable () -> Void {
        let mac = tv.wakeMAC
        let host = tv.host
        return { if let mac { WakeOnLAN.wake(mac: mac, host: host) } }
    }
}
