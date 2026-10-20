import SwiftUI

struct RemoteView: View {
    @Environment(TVStore.self) private var store
    @Environment(TVClient.self) private var client
    @Environment(Purchases.self) private var purchases
    @Environment(Ads.self) private var ads
    @Environment(\.scenePhase) private var scenePhase

    @State private var showNumbers = false
    @State private var showTVs = false
    @State private var showSettings = false
    @State private var showSetup = false
    @State private var showPlus = false
    @State private var wake: WakeStatus?
    @State private var launchingApp: String?
    @State private var appMessage: String?

    private enum WakeStatus: Equatable {
        case waking
        case failed(String?)
        case notSetUp
    }

    var body: some View {
        GeometryReader { geo in
        ScrollView {
            VStack(spacing: 0) {
                header
                statusBanner
                    .padding(.top, 10)
                gap

                HStack {
                    KeyButton(art: .power, label: "Power", tone: .oxblood, action: power)
                    Spacer()
                    KeyButton(art: .source, label: "Source") { client.send(.source) }
                    Spacer()
                    KeyButton(art: .hash, label: "Numbers") { showNumbers = true }
                    Spacer()
                    KeyButton(art: .info, label: "Info") { client.send(.info) }
                }
                gap

                // A little smaller in the free version, to make room for the ad.
                DPad(cell: showsAds ? 58 : 64) { client.send($0) }
                gap

                HStack {
                    KeyButton(art: .back, label: "Back") { client.send(.back) }
                    Spacer()
                    KeyButton(art: .home, label: "Home", size: 66, tone: .brass) { client.send(.home) }
                    Spacer()
                    KeyButton(art: .menu, label: "Menu") { client.send(.menu) }
                }
                .padding(.horizontal, 30)
                gap

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
                gap

                HStack {
                    KeyButton(art: PixelArt.fastForward.mirrored, label: "Rewind", size: 52) { client.send(.rewind) }
                    Spacer()
                    KeyButton(art: .play, label: "Play", size: 52) { client.send(.play) }
                    Spacer()
                    KeyButton(art: .pause, label: "Pause", size: 52) { client.send(.pause) }
                    Spacer()
                    KeyButton(art: .fastForward, label: "Fast forward", size: 52) { client.send(.fastForward) }
                }
                gap

                apps
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, showsAds ? 0 : 12)
            // Fill the screen so the gaps can stretch; they shrink back when a banner shows.
            .frame(minHeight: geo.size.height)
        }
        .scrollBounceBehavior(.basedOnSize)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsAds { AdStrip() }
        }
        .background(IronFloor())
        .overlay {
            if showNumbers || showTVs {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.55)
                        .ignoresSafeArea()
                        .onTapGesture {
                            showNumbers = false
                            showTVs = false
                        }
                        .transition(.opacity)
                    if showNumbers {
                        NumberPad(onKey: { client.send($0) }, onClose: { showNumbers = false })
                            .transition(.move(edge: .bottom))
                    }
                    if showTVs {
                        TVPicker(tvs: store.tvs, selected: store.tv?.host, onSelect: select, onAdd: {
                            showTVs = false
                            showSetup = true
                        }, onClose: { showTVs = false })
                        .transition(.move(edge: .bottom))
                    }
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: showNumbers)
        .animation(.easeOut(duration: 0.18), value: showTVs)
        .fullScreenCover(isPresented: $showSettings) {
            TVSettingsView()
        }
        .fullScreenCover(isPresented: $showSetup) { SetupView() }
        .fullScreenCover(isPresented: $showPlus) { PlusView() }
        // Ads (and the consent they need) only start once StoreKit has confirmed this
        // isn't a Plus owner, and only while the app is in front, as the tracking prompt requires.
        .task(id: wantsAds) {
            if wantsAds { await ads.start() }
        }
        .onChange(of: client.state) { _, state in
            if state == .connected { wake = nil }
        }
        .onChange(of: store.tv?.host) {
            wake = nil
            appMessage = nil
        }
        .onChange(of: store.tv?.wakeMAC) { _, mac in
            if mac != nil, wake == .notSetUp { wake = nil }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            Mascot(hops: client.commandCount)
            VStack(alignment: .leading, spacing: 2) {
                if purchases.hasPlus {
                    Button { showTVs = true } label: {
                        HStack(spacing: 8) {
                            tvName
                            PixelIcon(PixelArt(rows: PixelArt.arrowUp.rows.reversed()), scale: 2)
                                .foregroundStyle(Palette.textSoft)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Choose another TV")
                } else {
                    tvName
                }
                HStack(spacing: 6) {
                    PixelIcon(.gem, scale: 2)
                        .foregroundStyle(statusColor)
                    Text(statusText)
                        .pixelFont(14)
                        .foregroundStyle(Palette.textSoft)
                }
            }
            Spacer()
            if !purchases.hasPlus {
                Button { showPlus = true } label: {
                    Text("PLUS")
                        .pixelFont(14, weight: .bold)
                        .frame(height: 40)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(PixelButtonStyle(tone: .brass, depth: Pixel.unit))
                .accessibilityLabel("Controlinho Plus: more TVs, no ads")
            }
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

    private var tvName: some View {
        Text(store.tv?.name ?? "TV")
            .pixelFont(19, weight: .bold)
            .foregroundStyle(Palette.textLight)
            .lineLimit(1)
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
                   text: reason ?? "The TV didn't turn on. Check that \(wakeSettingName) is enabled on the TV.",
                   color: Palette.red) {
                bannerButton("Settings") { showSettings = true }
            }
        case .notSetUp:
            banner(art: .warning,
                   text: "To turn the TV on from your phone, the app needs its MAC address.",
                   color: Palette.red) {
                bannerButton("Add") { showSettings = true }
            }
        }
    }

    @ViewBuilder
    private var connectionBanner: some View {
        switch client.state {
        case .waitingForApproval:
            banner(art: .warning, text: "Accept the pairing request on your TV to connect Controlinho.", color: Palette.brass)
        case .failed(let message):
            // A TV in standby can't be reached; that's normal, so only the header mentions it.
            if !isProbablyOff {
                banner(art: .warning, text: message, color: Palette.red) {
                    bannerButton("Retry") { client.reconnectIfNeeded() }
                }
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

    private var showsAds: Bool {
        ads.isReady && !purchases.hasPlus
    }

    private var wantsAds: Bool {
        scenePhase == .active && purchases.hasChecked && !purchases.hasPlus
    }

    private func select(_ tv: SavedTV) {
        showTVs = false
        guard tv.host != store.tv?.host else { return }
        store.select(tv.host)
        client.connect(to: tv)
    }

    private func power() {
        guard client.state != .connected, let tv = store.tv else {
            client.send(.power)
            return
        }
        guard let mac = tv.wakeMAC else {
            // With no way to wake it, the best we can do is hope the TV is only in network standby.
            client.send(.power)
            wake = .notSetUp
            return
        }
        guard wake != .waking else { return }

        // The socket is down when the TV is off, so wake it over the network and poll
        // until it answers.
        wake = .waking
        Task {
            for _ in 0..<6 {
                WakeOnLAN.wake(mac: mac, host: tv.host)
                try? await Task.sleep(for: .seconds(3))
                if client.state == .connected { return }
                client.reconnectIfNeeded()
            }
            if client.state != .connected, wake == .waking { wake = .failed(nil) }
        }
    }

    /// Space between rows: grows to fill the screen, shrinks to make room for a banner.
    private var gap: some View {
        Spacer(minLength: 6).frame(maxHeight: 22)
    }

    /// The TV setting that lets it be switched on over the network.
    private var wakeSettingName: String {
        store.tv?.kind == .lg ? "Turn on via Wi-Fi" : "Power On with Mobile"
    }

    /// Whether Power can switch the TV on from standby.
    private var canWake: Bool {
        store.tv?.wakeMAC != nil
    }

    /// Unreachable, but Power can wake it: most likely in standby.
    private var isProbablyOff: Bool {
        guard case .failed = client.state else { return false }
        return canWake
    }

    private var statusColor: Color {
        if isProbablyOff { return Palette.textSoft }
        return switch client.state {
        case .connected: Palette.green
        case .connecting, .waitingForApproval: Palette.yellow
        case .disconnected: Palette.textSoft
        case .failed: Palette.red
        }
    }

    private var statusText: String {
        if isProbablyOff { return "Asleep · tap power" }
        return switch client.state {
        case .connected: "Connected"
        case .connecting: "Connecting…"
        case .waitingForApproval: "Waiting for approval"
        case .disconnected: "Disconnected"
        case .failed: "Not connected"
        }
    }
}

/// The chick from the app icon, sitting on the title plate. It hops on every key press.
private struct Mascot: View {
    let hops: Int

    var body: some View {
        Image("Chick")
            .resizable()
            .interpolation(.medium)
            .scaledToFit()
            .frame(width: 44, height: 36)
            .keyframeAnimator(initialValue: CGFloat(0), trigger: hops) { content, lift in
                content.offset(y: -lift)
            } keyframes: { _ in
                CubicKeyframe(7, duration: 0.09)
                CubicKeyframe(0, duration: 0.14)
            }
            .accessibilityHidden(true)
    }
}

/// The saved TVs in a copper panel that slides up over the remote (Plus).
private struct TVPicker: View {
    let tvs: [SavedTV]
    let selected: String?
    let onSelect: (SavedTV) -> Void
    let onAdd: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Your TVs")
                    .pixelFont(17, weight: .bold)
                    .foregroundStyle(Palette.textLight)
                Spacer()
                Button(action: onClose) {
                    Text("Close")
                        .pixelFont(15, weight: .bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(PixelButtonStyle(tone: .iron, depth: Pixel.unit))
            }
            VStack(spacing: 0) {
                ForEach(Array(tvs.enumerated()), id: \.element.host) { index, tv in
                    if index > 0 { PixelDivider() }
                    PixelActionRow(title: tv.name, color: Palette.text, checked: tv.host == selected) { onSelect(tv) }
                }
                PixelDivider()
                PixelActionRow(title: "Add a TV", action: onAdd)
            }
            .pixelPanel(.iron, padding: Pixel.unit * 2)
        }
        .pixelPanel(.copper, padding: Pixel.unit * 5)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

/// Digit keys in a copper panel that slides up over the remote.
private struct NumberPad: View {
    let onKey: (TVKey) -> Void
    let onClose: () -> Void

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 3)
        VStack(spacing: 14) {
            HStack {
                Text("Channel number")
                    .pixelFont(17, weight: .bold)
                    .foregroundStyle(Palette.textLight)
                Spacer()
                Button(action: onClose) {
                    Text("Close")
                        .pixelFont(15, weight: .bold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                }
                .buttonStyle(PixelButtonStyle(tone: .iron, depth: Pixel.unit))
            }
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(1...9, id: \.self) { digit($0) }
                Color.clear.frame(height: 1)
                digit(0)
            }
        }
        .pixelPanel(.copper, padding: Pixel.unit * 5)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
        .environment(TVClient())
        .environment(Purchases())
        .environment(Ads())
}
