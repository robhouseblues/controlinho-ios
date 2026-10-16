import SwiftUI

struct RemoteView: View {
    @Environment(TVStore.self) private var store
    @Environment(SamsungTVClient.self) private var client
    @Environment(SmartThings.self) private var smartThings

    @State private var showNumbers = false
    @State private var showSettings = false
    @State private var wake: WakeStatus?
    @State private var launchingApp: String?
    @State private var appMessage: String?

    private enum WakeStatus: Equatable {
        case waking
        case failed(String?)
        case notSetUp
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                header
                statusBanner

                HStack {
                    KeyButton(symbol: "power", label: "Power", tint: .red.opacity(0.75), action: power)
                    Spacer()
                    KeyButton(symbol: "rectangle.on.rectangle", label: "Source") { client.send(.source) }
                    Spacer()
                    KeyButton(symbol: "number", label: "Numbers") { showNumbers = true }
                    Spacer()
                    KeyButton(symbol: "info.circle", label: "Info") { client.send(.info) }
                }

                DPad { client.send($0) }

                HStack {
                    KeyButton(symbol: "arrow.uturn.backward", label: "Back") { client.send(.back) }
                    Spacer()
                    KeyButton(symbol: "house.fill", label: "Home", size: 72) { client.send(.home) }
                    Spacer()
                    KeyButton(symbol: "line.3.horizontal", label: "Menu") { client.send(.menu) }
                }
                .padding(.horizontal, 24)

                HStack(alignment: .center) {
                    Rocker(title: "VOL", upSymbol: "plus", downSymbol: "minus",
                           onUp: { client.send(.volumeUp) }, onDown: { client.send(.volumeDown) })
                    Spacer()
                    VStack(spacing: 16) {
                        KeyButton(symbol: "speaker.slash.fill", label: "Mute") { client.send(.mute) }
                        KeyButton(symbol: "list.bullet.rectangle", label: "Guide") { client.send(.guide) }
                    }
                    Spacer()
                    Rocker(title: "CH", upSymbol: "chevron.up", downSymbol: "chevron.down",
                           onUp: { client.send(.channelUp) }, onDown: { client.send(.channelDown) })
                }
                .padding(.horizontal, 12)

                HStack {
                    KeyButton(symbol: "backward.fill", label: "Rewind", size: 56) { client.send(.rewind) }
                    Spacer()
                    KeyButton(symbol: "play.fill", label: "Play", size: 56) { client.send(.play) }
                    Spacer()
                    KeyButton(symbol: "pause.fill", label: "Pause", size: 56) { client.send(.pause) }
                    Spacer()
                    KeyButton(symbol: "forward.fill", label: "Fast forward", size: 56) { client.send(.fastForward) }
                }

                apps
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(
            LinearGradient(colors: [Color(white: 0.11), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .sheet(isPresented: $showNumbers) {
            NumberPad { client.send($0) }
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSettings) {
            TVSettingsView()
        }
        .onChange(of: client.state) { _, state in
            if state == .connected { wake = nil }
        }
        .onChange(of: store.tv?.wakeMAC) { _, mac in
            if mac != nil, wake == .notSetUp { wake = nil }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor, radius: 4)
            VStack(alignment: .leading, spacing: 1) {
                Text(store.tv?.name ?? "Samsung TV")
                    .font(.headline)
                    .lineLimit(1)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // A plain button rather than a Menu: menus close whenever the connection state
            // re-renders the header, which happens constantly while reconnecting.
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(RemoteStyle.surface))
            }
            .foregroundStyle(.white)
            .accessibilityLabel("TV Settings")
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let wake {
            wakeBanner(wake)
        } else {
            connectionBanner
        }
    }

    @ViewBuilder
    private func wakeBanner(_ status: WakeStatus) -> some View {
        switch status {
        case .waking:
            banner(icon: "power", text: "Turning on the TV…", color: .cyan) {
                ProgressView()
            }
        case .failed(let reason):
            banner(icon: "exclamationmark.triangle.fill",
                   text: reason ?? "The TV didn't turn on. Check that Power On with Mobile is enabled on the TV.",
                   color: .orange) {
                Button("Settings") { showSettings = true }
                    .font(.subheadline.weight(.semibold))
            }
        case .notSetUp:
            banner(icon: "exclamationmark.triangle.fill",
                   text: "To turn the TV on from your phone, add its MAC address or connect SmartThings.",
                   color: .orange) {
                Button("Add") { showSettings = true }
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    @ViewBuilder
    private var connectionBanner: some View {
        switch client.state {
        case .waitingForApproval:
            banner(icon: "hand.raised.fill", text: "Select Allow on your TV to pair Controlinho.", color: .yellow)
        case .failed(let message):
            banner(icon: "exclamationmark.triangle.fill", text: message, color: .orange) {
                Button("Retry") { client.reconnectIfNeeded() }
                    .font(.subheadline.weight(.semibold))
            }
        default:
            EmptyView()
        }
    }

    private func banner(
        icon: String, text: String, color: Color,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.subheadline).frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(color.opacity(0.15)))
    }

    private var apps: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                ForEach(TVApp.shortcuts) { app in
                    Button { open(app) } label: {
                        VStack(spacing: 6) {
                            if launchingApp == app.id {
                                ProgressView().frame(height: 26)
                            } else {
                                Image(systemName: app.symbol).font(.system(size: 22))
                            }
                            Text(app.name).font(.caption2.weight(.medium)).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 64)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(TileButtonStyle())
                    .disabled(launchingApp != nil)
                }
            }
            if let appMessage {
                Text(appMessage)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
    }

    private func open(_ app: TVApp) {
        launchingApp = app.id
        appMessage = nil
        Task {
            let result = await client.launch(app)
            launchingApp = nil
            if result == .notInstalled {
                withAnimation { appMessage = "\(app.name) isn't installed on this TV." }
                try? await Task.sleep(for: .seconds(4))
                withAnimation { if appMessage?.hasPrefix(app.name) == true { appMessage = nil } }
            }
        }
    }

    // MARK: Helpers

    private func power() {
        guard client.state != .connected, let tv = store.tv else {
            client.send(.power)
            return
        }
        let mac = tv.wakeMAC
        let smartThingsID = smartThings.isSignedIn ? tv.smartThingsDeviceID : nil
        guard mac != nil || smartThingsID != nil else {
            // With no way to wake it, the best we can do is hope the TV is only in network standby.
            client.send(.power)
            wake = .notSetUp
            return
        }
        guard wake != .waking else { return }

        // The socket is down when the TV is off, so wake it (over the LAN and/or the cloud)
        // and poll until it answers.
        wake = .waking
        Task {
            var smartThingsError: String?
            if let smartThingsID {
                do {
                    try await smartThings.turnOn(deviceID: smartThingsID)
                } catch {
                    smartThingsError = error.localizedDescription
                }
            }
            for _ in 0..<6 {
                if let mac { WakeOnLAN.wake(mac: mac, host: tv.host) }
                try? await Task.sleep(for: .seconds(3))
                if client.state == .connected { return }
                client.reconnectIfNeeded()
            }
            if client.state != .connected, wake == .waking { wake = .failed(smartThingsError) }
        }
    }

    private var statusColor: Color {
        switch client.state {
        case .connected: .green
        case .connecting, .waitingForApproval: .yellow
        case .disconnected: .gray
        case .failed: .red
        }
    }

    private var statusText: String {
        switch client.state {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .waitingForApproval: "Waiting for approval"
        case .disconnected: "Disconnected"
        case .failed: "Not connected"
        }
    }
}

private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(configuration.isPressed ? RemoteStyle.surfacePressed : RemoteStyle.surface)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(RemoteStyle.stroke))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.15), value: configuration.isPressed)
            .sensoryFeedback(.impact(weight: .light), trigger: configuration.isPressed) { _, pressed in pressed }
    }
}

private struct NumberPad: View {
    let onKey: (TVKey) -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(1...9, id: \.self) { digit($0) }
            Color.clear.frame(height: 1)
            digit(0)
        }
        .padding(28)
    }

    private func digit(_ n: Int) -> some View {
        Button { onKey(.digit(n)) } label: {
            Text("\(n)")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .contentShape(Capsule())
        }
        .buttonStyle(KeyButtonStyle())
    }
}

#Preview {
    RemoteView()
        .environment(TVStore())
        .environment(SamsungTVClient())
        .environment(SmartThings())
        .preferredColorScheme(.dark)
}
