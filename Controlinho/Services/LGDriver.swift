import Foundation

/// Drives an LG webOS TV (2014+) for the app, on top of the shared `LGConnection`.
@MainActor
final class LGDriver: TVDriver {
    var onStateChange: ((TVConnectionState) -> Void)?
    var onTokenUpdate: ((String) -> Void)?
    var onPortConfirmed: ((Bool) -> Void)?
    var onKeyboardChange: ((Bool) -> Void)?

    private var tv: SavedTV
    private let connection: LGConnection
    private var state: TVConnectionState = .disconnected {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    private var connecting: Task<Bool, Never>?
    /// Presses run one after another, in the order they were made.
    private var lastCommand: Task<Void, Never>?
    /// What the TV's text box holds, as far as we know, so each edit sends only the change.
    private var sentText = ""
    private var keyboardOpen = false

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
        let wake = wakeAction
        perform { try await $0.press(key, wake: wake) }
    }

    func setText(_ text: String) {
        // Keep what both versions start with; delete the rest and type the new ending.
        let kept = zip(sentText, text).prefix { $0 == $1 }.count
        let deleting = sentText.count - kept
        let inserting = String(text.dropFirst(kept))
        sentText = text
        perform { try await $0.type(deleting: deleting, inserting: inserting) }
    }

    func submitText() {
        sentText = ""
        perform { try await $0.sendEnter() }
    }

    /// Runs a command once connected, after the ones before it.
    private func perform(_ command: @escaping @Sendable (LGConnection) async throws -> Void) {
        let previous = lastCommand
        let connection = connection
        lastCommand = Task { [weak self] in
            await previous?.value
            guard let self, await self.ensureConnected().value else { return }
            try? await command(connection)
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
                try? await connection.watchKeyboard { [weak self] open in
                    Task { @MainActor in self?.keyboardChanged(open) }
                }
                return true
            } catch LGError.notPaired {
                self?.connecting = nil
                self?.state = .failed("The TV didn't accept the pairing request. Try again and choose Accept on the TV.")
            } catch {
                self?.connecting = nil
                self?.state = .failed("Couldn't reach the TV. Make sure it's on and on the same Wi-Fi, and that LG Connect Apps is turned on in its network settings.")
            }
            return false
        }
        connecting = task
        return task
    }

    private func keyboardChanged(_ open: Bool) {
        // The TV repeats its keyboard state as the text changes; only react to it opening
        // or closing. A newly opened box starts empty as far as we know.
        guard open != keyboardOpen else { return }
        keyboardOpen = open
        sentText = ""
        onKeyboardChange?(open)
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
