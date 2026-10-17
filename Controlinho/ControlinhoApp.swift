import SwiftUI

@main
struct ControlinhoApp: App {
    @State private var store = TVStore()
    @State private var client = SamsungTVClient()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(client)
                .preferredColorScheme(.dark)
                .tint(Palette.brass)
                .onAppear {
                    client.onTokenUpdate = { [store] token in store.updateToken(token) }
                    client.onPortConfirmed = { [store] legacy in
                        if store.tv?.usesLegacyPort != legacy { store.tv?.usesLegacyPort = legacy }
                    }
                    client.onConnected = { [store] in
                        guard let host = store.tv?.host else { return }
                        Task {
                            if let info = try? await TVDiscovery.fetchInfo(host: host) {
                                store.update(from: info)
                            }
                        }
                    }
                    if let tv = store.tv { client.connect(to: tv) }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        client.reconnectIfNeeded()
                    case .background: client.disconnect()
                    default: break
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(TVStore.self) private var store

    var body: some View {
        if store.tv == nil {
            SetupView()
        } else {
            RemoteView()
        }
    }
}
