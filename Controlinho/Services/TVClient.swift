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

    func connect()
    func reconnectIfNeeded()
    func disconnect()
    func send(_ key: TVKey)
    func launch(_ app: TVApp) async -> TVLaunchResult
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

    var onTokenUpdate: ((String) -> Void)?
    /// Called each time the TV accepts the connection.
    var onConnected: (() -> Void)?
    var onPortConfirmed: ((Bool) -> Void)?

    @ObservationIgnored private var driver: TVDriver?

    func connect(to tv: SavedTV) {
        driver?.disconnect()
        let driver: TVDriver = switch tv.kind {
        case .samsung: SamsungDriver(tv: tv)
        case .lg: LGDriver(tv: tv)
        }
        driver.onStateChange = { [weak self] state in self?.update(state) }
        driver.onTokenUpdate = { [weak self] token in self?.onTokenUpdate?(token) }
        driver.onPortConfirmed = { [weak self] legacy in self?.onPortConfirmed?(legacy) }
        self.driver = driver
        driver.connect()
    }

    func reconnectIfNeeded() {
        driver?.reconnectIfNeeded()
    }

    func disconnect() {
        driver?.disconnect()
        state = .disconnected
    }

    func send(_ key: TVKey) {
        commandCount += 1
        driver?.send(key)
    }

    func launch(_ app: TVApp) async -> TVLaunchResult {
        commandCount += 1
        return await driver?.launch(app) ?? .launched
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
