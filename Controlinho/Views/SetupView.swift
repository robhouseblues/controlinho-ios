import SwiftUI

/// Finds a TV on the local network (or takes an IP address) and pairs with it.
struct SetupView: View {
    @Environment(TVStore.self) private var store
    @Environment(SamsungTVClient.self) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var found: [DiscoveredTV] = []
    @State private var isScanning = false
    @State private var manualHost = ""
    @State private var manualError: String?
    @State private var isCheckingManual = false

    var body: some View {
        NavigationStack {
            PixelPage {
                PixelSection(title: "On this network", trailing: scanButton) {
                    if isScanning && found.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView().tint(Palette.text)
                            Text("Looking for Samsung TVs…").pixelFont(16).foregroundStyle(Palette.textSoft)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                    } else if found.isEmpty {
                        Text("No TVs found. Make sure the TV is on and connected to the same Wi-Fi.")
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
                                    Text(tv.name).pixelFont(17, weight: .semibold).foregroundStyle(Palette.text)
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
                    footer: manualError ?? "Find it on the TV under Settings › General › Network › Network Status.",
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
        }
    }

    private var scanButton: AnyView? {
        guard !isScanning else { return nil }
        return AnyView(
            Button { Task { await scan() } } label: {
                Text("Scan again")
                    .pixelFont(14, weight: .bold)
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
        do {
            pair(try await TVDiscovery.fetchInfo(host: host).savedTV)
        } catch {
            // Some firmwares hide the info endpoint; try the remote socket anyway.
            pair(SavedTV(host: host, name: "Samsung TV"))
        }
    }

    private func pair(_ tv: SavedTV) {
        var tv = tv
        if let current = store.tv, current.host == tv.host {
            tv.token = current.token
            tv.manualMAC = current.manualMAC
            tv.smartThingsDeviceID = current.smartThingsDeviceID
            tv.smartThingsDeviceName = current.smartThingsDeviceName
        }
        store.tv = tv
        client.connect(to: tv)
        dismiss()
    }
}
