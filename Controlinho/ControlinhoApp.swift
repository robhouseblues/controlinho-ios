import SwiftUI

@main
struct ControlinhoApp: App {
    @State private var store = TVStore()
    @State private var client = TVClient()
    @State private var purchases = Purchases()
    @State private var ads = Ads()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(client)
                .environment(purchases)
                .environment(ads)
                .preferredColorScheme(.dark)
                .tint(Palette.brass)
                .onAppear {
                    client.onTokenUpdate = { [store] token, host in store.updateToken(token, for: host) }
                    client.onPortConfirmed = { [store] legacy, host in store.updatePort(legacy: legacy, for: host) }
                    client.onConnected = { [store, client] in
                        Task {
                            if let info = await client.fetchInfo() { store.update(from: info) }
                        }
                    }
                    if let tv = store.tv { client.connect(to: tv) }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        store.reload()
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
