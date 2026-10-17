import AppIntents

// One parameterless intent per key. A single intent with a "key" parameter lost its value
// when Control Center ran it (the system logged `RemoteKey(nil)` and skipped perform).

struct VolumeUpIntent: AppIntent {
    static let title: LocalizedStringResource = "TV Volume Up"

    func perform() async throws -> some IntentResult {
        try await QuickRemote.press(.volumeUp)
        return .result()
    }
}

struct VolumeDownIntent: AppIntent {
    static let title: LocalizedStringResource = "TV Volume Down"

    func perform() async throws -> some IntentResult {
        try await QuickRemote.press(.volumeDown)
        return .result()
    }
}

struct MuteIntent: AppIntent {
    static let title: LocalizedStringResource = "TV Mute"

    func perform() async throws -> some IntentResult {
        try await QuickRemote.press(.mute)
        return .result()
    }
}

struct PauseIntent: AppIntent {
    static let title: LocalizedStringResource = "TV Pause"

    func perform() async throws -> some IntentResult {
        try await QuickRemote.press(.pause)
        return .result()
    }
}

struct OKIntent: AppIntent {
    static let title: LocalizedStringResource = "TV OK"

    func perform() async throws -> some IntentResult {
        try await QuickRemote.press(.enter)
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
