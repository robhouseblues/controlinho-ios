import Foundation
import Observation

/// Persists the paired TVs (including their auth tokens) in the App Group, where the
/// Control Center controls can read them too.
@MainActor
@Observable
final class TVStore {
    /// Every TV the user has connected, in the order they were added.
    private(set) var tvs: [SavedTV] = []
    /// The address of the TV the remote is pointed at.
    private(set) var activeHost: String?

    init() {
        reload()
    }

    /// The TV the remote is pointed at. Setting it saves changes to that TV's details.
    var tv: SavedTV? {
        get { tvs.first { $0.host == activeHost } ?? tvs.first }
        set {
            guard let newValue else { return }
            update(newValue.host) { $0 = newValue }
        }
    }

    /// Saves a newly paired TV and points the remote at it. Pairing again at the same
    /// address replaces the earlier entry.
    func add(_ tv: SavedTV, replacingOthers: Bool) {
        if replacingOthers {
            tvs = [tv]
        } else if let index = tvs.firstIndex(where: { $0.host == tv.host }) {
            tvs[index] = tv
        } else {
            tvs.append(tv)
        }
        activeHost = tv.host
        persist()
    }

    func select(_ host: String) {
        guard host != activeHost, tvs.contains(where: { $0.host == host }) else { return }
        activeHost = host
        persist()
    }

    func remove(_ host: String) {
        tvs.removeAll { $0.host == host }
        if activeHost == host { activeHost = tvs.first?.host }
        persist()
    }

    func updateToken(_ token: String, for host: String) {
        update(host) { $0.token = token }
    }

    func updatePort(legacy: Bool, for host: String) {
        update(host) { $0.usesLegacyPort = legacy }
    }

    /// Refreshes what the TV reports about itself (its MAC can't be read once it's off).
    func update(from info: DiscoveredTV) {
        update(info.host) { tv in
            tv.mac = info.mac ?? tv.mac
            tv.isWired = info.isWired
            tv.macMatchesConnection = info.mac != nil ? info.macMatchesConnection : tv.macMatchesConnection
            tv.model = info.model ?? tv.model
            if tv.name == DiscoveredTV.genericName(for: tv.kind) { tv.name = info.name }
        }
    }

    /// Picks up changes the Control Center controls made, such as a refreshed pairing token.
    func reload() {
        let saved = SharedStore.loadTVs()
        tvs = saved.tvs
        activeHost = saved.active ?? saved.tvs.first?.host
    }

    private func update(_ host: String, _ change: (inout SavedTV) -> Void) {
        guard let index = tvs.firstIndex(where: { $0.host == host }) else { return }
        var tv = tvs[index]
        change(&tv)
        guard tv != tvs[index] else { return }
        tvs[index] = tv
        persist()
    }

    private func persist() {
        SharedStore.saveTVs(tvs, active: activeHost)
    }
}
