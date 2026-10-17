import AppIntents

/// The keys offered as Control Center controls.
enum RemoteKey: String, AppEnum {
    case volumeUp
    case volumeDown
    case mute

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "TV Key"
    static let caseDisplayRepresentations: [RemoteKey: DisplayRepresentation] = [
        .volumeUp: "Volume Up",
        .volumeDown: "Volume Down",
        .mute: "Mute",
    ]

    var tvKey: TVKey {
        switch self {
        case .volumeUp: .volumeUp
        case .volumeDown: .volumeDown
        case .mute: .mute
        }
    }
}

/// Presses one remote key on the paired TV.
struct SendKeyIntent: AppIntent {
    static let title: LocalizedStringResource = "Press TV Key"
    static let description = IntentDescription("Presses a key on your Samsung TV.")

    @Parameter(title: "Key")
    var key: RemoteKey

    init() {}

    init(key: RemoteKey) {
        self.key = key
    }

    func perform() async throws -> some IntentResult {
        try await QuickRemote.press(key.tvKey)
        return .result()
    }
}

/// Turns the TV off if it's on, or wakes it if it's in standby.
struct PowerIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle TV Power"
    static let description = IntentDescription("Turns your Samsung TV on or off.")

    func perform() async throws -> some IntentResult {
        guard let tv = SharedStore.loadTV() else { throw QuickRemoteError.noTV }
        do {
            // Reachable means it's on (or in network standby): the power key toggles it.
            try await QuickRemote.press(.power)
        } catch QuickRemoteError.notPaired {
            throw QuickRemoteError.notPaired
        } catch {
            // Unreachable means it's off.
            try await QuickRemote.wake(tv)
        }
        return .result()
    }
}
