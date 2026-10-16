import Foundation
import Observation

/// Persists the paired TV (including its auth token) in UserDefaults.
@MainActor
@Observable
final class TVStore {
    private static let key = "savedTV"

    var tv: SavedTV? {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key) {
            tv = try? JSONDecoder().decode(SavedTV.self, from: data)
        }
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
        if let tv, let data = try? JSONEncoder().encode(tv) {
            UserDefaults.standard.set(data, forKey: Self.key)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.key)
        }
    }
}
