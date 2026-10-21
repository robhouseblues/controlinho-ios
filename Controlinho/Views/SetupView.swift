import SwiftUI

/// Finds a TV on the local network (or takes an IP address) and pairs with it.
struct SetupView: View {
    @Environment(TVStore.self) private var store
    @Environment(TVClient.self) private var client
    @Environment(Purchases.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    @State private var found: [DiscoveredTV] = []
    @State private var isScanning = false
    @State private var manualHost = ""
    @State private var manualError: String?
    @State private var isCheckingManual = false
    @State private var showPlus = false

    var body: some View {
        NavigationStack {
            PixelPage {
                if let current = store.tv, !purchases.hasPlus {
                    PixelSection(title: "One TV in the free version") {
                        Text("Connecting another TV replaces \(current.name). Plus keeps them all.")
                            .pixelFont(15)
                            .foregroundStyle(Palette.textSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                        PixelDivider()
                        PixelActionRow(title: "Get Plus") { showPlus = true }
                    }
                }

                PixelSection(title: "On this network", trailing: scanButton) {
                    if isScanning && found.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView().tint(Palette.text)
                            Text("Looking for Samsung and LG TVs…").pixelFont(16).foregroundStyle(Palette.textSoft)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    } else if found.isEmpty {
                        Text("No TVs found. Make sure the TV is on and connected to the same Wi-Fi. On an LG TV, also turn on LG Connect Apps in its network settings.")
                            .pixelFont(16)
                            .foregroundStyle(Palette.textSoft)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    ForEach(Array(found.enumerated()), id: \.element.id) { index, tv in
                        if index > 0 { PixelDivider() }
                        Button { pair(tv.savedTV) } label: {
                            HStack(spacing: 14) {
                                PixelIcon(.source).foregroundStyle(Palette.accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 8) {
                                        Text(pixel: tv.name, size: 17, weight: .semibold).foregroundStyle(Palette.text)
                                        if tv.brand.isBeta { PixelBadge(text: "BETA") }
                                    }
                                    Text([tv.model, tv.host].compactMap { $0 }.joined(separator: " · "))
                                        .pixelFont(13)
                                        .foregroundStyle(Palette.textSoft)
                                }
                                Spacer()
                                PixelIcon(.arrowUp, scale: 2)
                                    .rotationEffect(.degrees(90))
                                    .foregroundStyle(Palette.textSoft)
                            }
                            .padding(12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PixelRowButtonStyle())
                    }
                }

                PixelSection(
                    title: "Enter IP address",
                    footer: manualError ?? "Find it in your TV's network settings, usually under Network Status or Connection Status.",
                    footerIsWarning: manualError != nil
                ) {
                    TextField("192.168.0.42", text: $manualHost)
                        .textFieldStyle(PixelFieldStyle())
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.go)
                        .onSubmit { Task { await addManual() } }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if isCheckingManual {
                        ProgressView().tint(Palette.text).padding(12)
                    } else {
                        PixelActionRow(title: "Connect") { Task { await addManual() } }
                            .disabled(!LocalNetwork.isPrivateIPv4(manualHost))
                    }
                }
            }
            .pixelScreen("Connect a TV", leading: store.tv == nil ? nil : PixelBarAction(title: "Cancel") { dismiss() })
            .task { await scan() }
            .fullScreenCover(isPresented: $showPlus) { PlusView() }
        }
    }

    private var scanButton: AnyView? {
        guard !isScanning else { return nil }
        return AnyView(
            Button { Task { await scan() } } label: {
                Text(pixel: "Scan again", size: 14, weight: .bold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(PixelButtonStyle(tone: .brass, depth: Pixel.unit))
        )
    }

    private func scan() async {
        isScanning = true
        found = await TVDiscovery.scan()
        isScanning = false
    }

    private func addManual() async {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        guard LocalNetwork.isPrivateIPv4(host), !isCheckingManual else { return }
        isCheckingManual = true
        manualError = nil
        defer { isCheckingManual = false }
        if let found = await TVDiscovery.identify(host: host) {
            pair(found.savedTV)
        } else {
            manualError = "Couldn't find a Samsung or LG TV at that address. Make sure the TV is on. On an LG TV, also turn on LG Connect Apps in its network settings."
        }
    }

    private func pair(_ tv: SavedTV) {
        var tv = tv
        if let earlier = store.tvs.first(where: { $0.host == tv.host }) {
            tv.token = earlier.token
            tv.manualMAC = earlier.manualMAC
        }
        store.add(tv, replacingOthers: !purchases.hasPlus)
        client.connect(to: tv)
        dismiss()
    }
}
