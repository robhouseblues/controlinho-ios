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
            VStack(spacing: 13) {
                header
                statusBanner

                HStack {
                    KeyButton(art: .power, label: "Power", tone: .oxblood, action: power)
                    Spacer()
                    KeyButton(art: .source, label: "Source") { client.send(.source) }
                    Spacer()
                    KeyButton(art: .hash, label: "Numbers") { showNumbers = true }
                    Spacer()
                    KeyButton(art: .info, label: "Info") { client.send(.info) }
                }

                DPad { client.send($0) }

                HStack {
                    KeyButton(art: .back, label: "Back") { client.send(.back) }
                    Spacer()
                    KeyButton(art: .home, label: "Home", size: 66, tone: .brass) { client.send(.home) }
                    Spacer()
                    KeyButton(art: .menu, label: "Menu") { client.send(.menu) }
                }
                .padding(.horizontal, 30)

                HStack(alignment: .center) {
                    Rocker(title: "VOL", up: .plus, down: .minus,
                           onUp: { client.send(.volumeUp) }, onDown: { client.send(.volumeDown) })
                    Spacer()
                    VStack(spacing: 14) {
                        KeyButton(art: .mute, label: "Mute") { client.send(.mute) }
                        KeyButton(art: .guide, label: "Guide") { client.send(.guide) }
                    }
                    Spacer()
                    Rocker(title: "CH", up: .arrowUp, down: PixelArt(rows: PixelArt.arrowUp.rows.reversed()),
                           onUp: { client.send(.channelUp) }, onDown: { client.send(.channelDown) })
                }
                .padding(.horizontal, 12)

                HStack {
                    KeyButton(art: PixelArt.fastForward.mirrored, label: "Rewind", size: 52) { client.send(.rewind) }
                    Spacer()
                    KeyButton(art: .play, label: "Play", size: 52) { client.send(.play) }
                    Spacer()
                    KeyButton(art: .pause, label: "Pause", size: 52) { client.send(.pause) }
                    Spacer()
                    KeyButton(art: .fastForward, label: "Fast forward", size: 52) { client.send(.fastForward) }
                }

                apps
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(IronFloor())
        .sheet(isPresented: $showNumbers) {
            NumberPad { client.send($0) }
                .presentationDetents([.height(400)])
                .presentationDragIndicator(.visible)
                .presentationBackground(Palette.bar)
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
            PixelIcon(.gem)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(store.tv?.name ?? "Samsung TV")
                    .font(.pixel(19, weight: .bold))
                    .foregroundStyle(Palette.textLight)
                    .lineLimit(1)
                Text(statusText)
                    .font(.pixel(14))
                    .foregroundStyle(Palette.textSoft)
            }
            Spacer()
            // A plain button rather than a Menu: menus close whenever the connection state
            // re-renders the header, which happens constantly while reconnecting.
            Button { showSettings = true } label: {
                PixelIcon(.gear).frame(width: 42, height: 40)
            }
            .buttonStyle(PixelButtonStyle(tone: .iron, depth: Pixel.unit))
            .accessibilityLabel("TV Settings")
        }
        .padding(.leading, Pixel.unit * 2)
        .pixelPanel(.copper, padding: Pixel.unit * 3)
        .padding(.top, 6)
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
            banner(art: .power, text: "Turning on the TV…", color: Palette.brass) {
                ProgressView().tint(Palette.text)
            }
        case .failed(let reason):
            banner(art: .warning,
                   text: reason ?? "The TV didn't turn on. Check that Power On with Mobile is enabled on the TV.",
                   color: Palette.red) {
                bannerButton("Settings") { showSettings = true }
            }
        case .notSetUp:
            banner(art: .warning,
                   text: "To turn the TV on from your phone, add its MAC address or connect SmartThings.",
                   color: Palette.red) {
                bannerButton("Add") { showSettings = true }
            }
        }
    }

    @ViewBuilder
    private var connectionBanner: some View {
        switch client.state {
        case .waitingForApproval:
            banner(art: .warning, text: "Select Allow on your TV to pair Controlinho.", color: Palette.brass)
        case .failed(let message):
            banner(art: .warning, text: message, color: Palette.red) {
                bannerButton("Retry") { client.reconnectIfNeeded() }
            }
        default:
            EmptyView()
        }
    }

    private func banner(
        art: PixelArt, text: String, color: Color,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) -> some View {
        HStack(spacing: 12) {
            PixelIcon(art).foregroundStyle(color)
            Text(text)
                .font(.pixel(15))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .pixelPanel(.iron)
    }

    private func bannerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.pixel(15, weight: .bold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(PixelButtonStyle(tone: .brass, depth: Pixel.unit))
    }

    /// The app shortcuts, styled as a game hotbar of item slots.
    private var apps: some View {
        VStack(spacing: 10) {
            HStack(spacing: Pixel.unit * 2) {
                ForEach(TVApp.shortcuts) { app in
                    Button { open(app) } label: {
                        VStack(spacing: 4) {
                            ZStack {
                                Rectangle()
                                    .fill(Color(hex: app.tileColor))
                                    .overlay(Rectangle().strokeBorder(Palette.ink, lineWidth: Pixel.unit))
                                if launchingApp == app.id {
                                    ProgressView().tint(Palette.textLight)
                                } else {
                                    Text(app.initial)
                                        .font(.pixel(24, weight: .bold))
                                        .foregroundStyle(Palette.textLight)
                                }
                            }
                            .frame(width: 39, height: 39)
                            Text(app.name)
                                .pixelFont(13)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(PixelButtonStyle(tone: .slot, depth: Pixel.unit))
                    .disabled(launchingApp != nil)
                }
            }
            .pixelPanel(.copper, padding: Pixel.unit * 3)

            if let appMessage {
                Text(appMessage)
                    .font(.pixel(15))
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .pixelPanel(.iron, padding: Pixel.unit * 3)
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
        case .connected: Palette.green
        case .connecting, .waitingForApproval: Palette.yellow
        case .disconnected: Palette.textSoft
        case .failed: Palette.red
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

private struct NumberPad: View {
    let onKey: (TVKey) -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(1...9, id: \.self) { digit($0) }
            Color.clear.frame(height: 1)
            digit(0)
        }
        .pixelPanel(.copper, padding: Pixel.unit * 5)
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private func digit(_ n: Int) -> some View {
        Button { onKey(.digit(n)) } label: {
            Text("\(n)")
                .font(.pixel(28, weight: .bold))
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(PixelButtonStyle(tone: .iron))
    }
}

#Preview {
    RemoteView()
        .environment(TVStore())
        .environment(SamsungTVClient())
        .environment(SmartThings())
}
