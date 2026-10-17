import Foundation
import Observation

/// Persists the paired TV (including its auth token) in the App Group, where the
/// Control Center controls can read it too.
@MainActor
@Observable
final class TVStore {
    var tv: SavedTV? {
        didSet { persist() }
    }

    init() {
        tv = SharedStore.loadTV()
    }

    func updateToken(_ token: String) {
        tv?.token = token
    }

    /// Refreshes what the TV reports about itself (its MAC can't be read once it's off).
    func update(from info: DiscoveredTV) {
        guard var tv, tv.host == info.host else { return }
        tv.mac = info.mac ?? tv.mac
        tv.isWired = info.isWired
        tv.model = info.model ?? tv.model
        if tv.name == "Samsung TV" { tv.name = info.name }
        if tv != self.tv { self.tv = tv }
    }

    private func persist() {
        SharedStore.saveTV(tv)
    }
}
