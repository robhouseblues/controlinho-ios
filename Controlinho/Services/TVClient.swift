import Foundation
import Observation

enum TVConnectionState: Equatable {
    case disconnected
    case connecting
    case waitingForApproval
    case connected
    case failed(String)
}

enum TVLaunchResult {
    case launched
    case notInstalled
}

/// One brand's way of talking to a TV. The app only sees `TVClient`, which picks the
/// driver for the paired TV's brand.
@MainActor
protocol TVDriver: AnyObject {
    var onStateChange: ((TVConnectionState) -> Void)? { get set }
    /// The TV issued a new pairing token or key, so it can be persisted.
    var onTokenUpdate: ((String) -> Void)? { get set }
    /// Whether the TV only accepted its older, unencrypted port.
    var onPortConfirmed: ((Bool) -> Void)? { get set }
    /// The TV opened (true) or closed (false) its on-screen keyboard.
    var onKeyboardChange: ((Bool) -> Void)? { get set }

    func connect()
    func reconnectIfNeeded()
    func disconnect()
    func send(_ key: TVKey)
    func launch(_ app: TVApp) async -> TVLaunchResult
    /// Makes the text box the TV's keyboard is filling read `text`.
    func setText(_ text: String)
    /// Submits that text, like Done on the TV's own keyboard.
    func submitText()
    /// What the TV reports about itself (name, model, MAC), read while it's on.
    func fetchInfo() async -> DiscoveredTV?
}

/// The remote the app talks to, whatever the TV's brand.
@MainActor
@Observable
final class TVClient {
    typealias State = TVConnectionState

    private(set) var state: State = .disconnected

    /// Goes up by one for every key press or app launch, so the UI can react to it.
    private(set) var commandCount = 0

    /// Whether the TV is showing its keyboard and waiting for text.
    private(set) var isKeyboardOpen = false

    /// Called with a new pairing token and the address of the TV that issued it.
    var onTokenUpdate: ((String, String) -> Void)?
    /// Called each time the TV accepts the connection.
    var onConnected: (() -> Void)?
    /// Called with whether the TV only accepted its older port, and the TV's address.
    var onPortConfirmed: ((Bool, String) -> Void)?

    @ObservationIgnored private var driver: TVDriver?

    func connect(to tv: SavedTV) {
        if let previous = driver {
            previous.disconnect()
            previous.onStateChange = nil
            previous.onTokenUpdate = nil
            previous.onPortConfirmed = nil
            previous.onKeyboardChange = nil
        }
        isKeyboardOpen = false
        let driver: TVDriver = switch tv.kind {
        case .samsung: SamsungDriver(tv: tv)
        case .lg: LGDriver(tv: tv)
        }
        driver.onStateChange = { [weak self] state in self?.update(state) }
        // Tagged with the address, so a late update from the previous TV can't land on this one.
        let host = tv.host
        driver.onTokenUpdate = { [weak self] token in self?.onTokenUpdate?(token, host) }
        driver.onPortConfirmed = { [weak self] legacy in self?.onPortConfirmed?(legacy, host) }
        driver.onKeyboardChange = { [weak self] open in self?.isKeyboardOpen = open }
        self.driver = driver
        driver.connect()
    }

    func reconnectIfNeeded() {
        driver?.reconnectIfNeeded()
    }

    func disconnect() {
        driver?.disconnect()
        state = .disconnected
        isKeyboardOpen = false
    }

    func send(_ key: TVKey) {
        commandCount += 1
        driver?.send(key)
    }

    func launch(_ app: TVApp) async -> TVLaunchResult {
        commandCount += 1
        return await driver?.launch(app) ?? .launched
    }

    func setText(_ text: String) {
        driver?.setText(text)
    }

    func submitText() {
        commandCount += 1
        driver?.submitText()
    }

    func fetchInfo() async -> DiscoveredTV? {
        await driver?.fetchInfo()
    }

    private func update(_ newState: State) {
        let wasConnected = state == .connected
        state = newState
        if newState == .connected && !wasConnected { onConnected?() }
    }
}
