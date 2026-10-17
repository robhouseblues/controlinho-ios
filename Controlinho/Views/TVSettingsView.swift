import SwiftUI

/// Details about the paired TV, plus the MAC address used to switch it on.
struct TVSettingsView: View {
    @Environment(TVStore.self) private var store
    @Environment(SamsungTVClient.self) private var client
    @Environment(\.dismiss) private var dismiss

    @State private var manualMAC = ""
    @State private var didWake = false
    @State private var showSetup = false

    var body: some View {
        NavigationStack {
            PixelPage {
                if let tv = store.tv {
                    PixelSection(title: "TV") {
                        PixelInfoRow(label: "Name", value: tv.name)
                        if let model = tv.model {
                            PixelDivider()
                            PixelInfoRow(label: "Model", value: model)
                        }
                        PixelDivider()
                        PixelInfoRow(label: "IP address", value: tv.host)
                        if let isWired = tv.isWired {
                            PixelDivider()
                            PixelInfoRow(label: "Connection", value: isWired ? "Ethernet cable" : "Wi-Fi")
                        }
                        PixelDivider()
                        PixelActionRow(title: "Reconnect") {
                            client.connect(to: tv)
                            dismiss()
                        }
                        PixelDivider()
                        PixelActionRow(title: "Switch to another TV") { showSetup = true }
                    }

                    PixelSection(title: "Turn on from phone", footer: footer(for: tv), footerIsWarning: footerIsWarning(tv)) {
                        PixelInfoRow(label: "Reported by TV", value: tv.mac ?? "Not read yet")
                        PixelDivider()
                        TextField("e.g. 64:1C:AE:12:34:56", text: $manualMAC)
                            .textFieldStyle(PixelFieldStyle())
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .onChange(of: manualMAC) { _, value in save(value) }
                        PixelActionRow(title: didWake ? "Wake signal sent" : "Send wake signal now") {
                            guard let mac = store.tv?.wakeMAC else { return }
                            WakeOnLAN.wake(mac: mac, host: tv.host)
                            didWake = true
                        }
                        .disabled(tv.wakeMAC == nil)
                    }

                    SmartThingsSection()

                    PixelSection {
                        PixelActionRow(title: "Forget TV", color: Palette.red) {
                            client.disconnect()
                            store.tv = nil
                            dismiss()
                        }
                    }
                }
            }
            .pixelScreen("TV Settings", trailing: PixelBarAction(title: "Done", primary: true) { dismiss() })
            .onAppear { manualMAC = store.tv?.manualMAC ?? "" }
            .fullScreenCover(isPresented: $showSetup) { SetupView() }
        }
    }

    private func save(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespaces).uppercased()
        if trimmed.isEmpty {
            store.tv?.manualMAC = nil
        } else if SavedTV.isValidMAC(trimmed) {
            store.tv?.manualMAC = trimmed
        }
    }

    private func footerIsWarning(_ tv: SavedTV) -> Bool {
        tv.wakeMAC == nil || (!manualMAC.isEmpty && !SavedTV.isValidMAC(manualMAC))
    }

    private func footer(for tv: SavedTV) -> String {
        if !manualMAC.isEmpty && !SavedTV.isValidMAC(manualMAC) {
            return "That doesn't look like a MAC address. It should be six pairs of characters like 64:1C:AE:12:34:56."
        }
        let setting = "Also turn on Power On with Mobile on the TV (Settings › General › Network › Expert Settings, or Settings › Connection › Network › Expert Settings on newer models)."
        if tv.wakeMAC == nil {
            if tv.isWired == true {
                return "Your TV is on a network cable, so it needs its Ethernet MAC address. Find it on the TV under Settings › Support › About This TV and type it above. " + setting
            }
            return "The app reads the MAC address automatically the next time it connects while the TV is on. You can also type it above. " + setting
        }
        return "Leave the field empty to use the address the TV reports. " + setting
    }
}
