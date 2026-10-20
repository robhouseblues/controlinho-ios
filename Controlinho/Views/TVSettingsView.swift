import SwiftUI

/// The saved TVs, details about the selected one, and the MAC address used to switch it on.
struct TVSettingsView: View {
    @Environment(TVStore.self) private var store
    @Environment(TVClient.self) private var client
    @Environment(Purchases.self) private var purchases
    @Environment(Ads.self) private var ads
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var manualMAC = ""
    @State private var didWake = false
    @State private var showSetup = false
    @State private var showPlus = false

    var body: some View {
        NavigationStack {
            PixelPage {
                if purchases.hasPlus {
                    PixelSection(title: "Your TVs", trailing: AnyView(PixelBadge(text: "PLUS"))) {
                        ForEach(Array(store.tvs.enumerated()), id: \.element.host) { index, tv in
                            if index > 0 { PixelDivider() }
                            PixelActionRow(title: tv.name, color: Palette.text, checked: tv.host == store.tv?.host) {
                                select(tv)
                            }
                        }
                        PixelDivider()
                        PixelActionRow(title: "Add a TV") { showSetup = true }
                    }
                } else {
                    PixelSection(title: "Controlinho Plus", footer: "Keep every TV in the house and remove the ads, with one purchase.") {
                        PixelActionRow(title: "Get Plus") { showPlus = true }
                    }
                }

                if let tv = store.tv {
                    PixelSection(title: purchases.hasPlus ? "This TV" : "TV") {
                        PixelInfoRow(label: "Name", value: tv.name)
                        PixelDivider()
                        PixelInfoRow(label: "Brand", value: tv.kind.displayName, badge: tv.kind.isBeta ? "BETA" : nil)
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
                        if !purchases.hasPlus {
                            PixelDivider()
                            PixelActionRow(title: "Switch to another TV") { showSetup = true }
                        }
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

                    PixelSection(title: "Privacy") {
                        PixelActionRow(title: "Privacy policy") { openURL(Self.privacyPolicy) }
                        if !purchases.hasPlus && ads.offersPrivacyChoices {
                            PixelDivider()
                            PixelActionRow(title: "Ad privacy choices") {
                                Task { await ads.showPrivacyChoices() }
                            }
                        }
                    }

                    PixelSection {
                        PixelActionRow(title: store.tvs.count > 1 ? "Forget this TV" : "Forget TV", color: Palette.red) {
                            forget(tv)
                        }
                    }
                }
            }
            .pixelScreen("TV Settings", trailing: PixelBarAction(title: "Done", primary: true) { dismiss() })
            .onAppear { manualMAC = store.tv?.manualMAC ?? "" }
            .onChange(of: store.tv?.host) {
                manualMAC = store.tv?.manualMAC ?? ""
                didWake = false
            }
            .fullScreenCover(isPresented: $showSetup) { SetupView() }
            .fullScreenCover(isPresented: $showPlus) { PlusView() }
        }
    }

    /// Hosted on GitHub Pages from `privacy/index.html`; also the App Store listing's privacy link.
    private static let privacyPolicy = URL(string: "https://robhouseblues.github.io/controlinho-ios/privacy/")!

    private func select(_ tv: SavedTV) {
        guard tv.host != store.tv?.host else { return }
        store.select(tv.host)
        client.connect(to: tv)
    }

    private func forget(_ tv: SavedTV) {
        client.disconnect()
        store.remove(tv.host)
        if let next = store.tv {
            client.connect(to: next)
        } else {
            dismiss()
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
        let setting = "Also turn on \(tv.kind.wakeSettingHint)."
        if tv.wakeMAC == nil {
            if tv.isWired == true {
                return "Your TV is on a network cable, so it needs its Ethernet MAC address. Find it in the TV's network or support settings and type it above. " + setting
            }
            return "The app reads the MAC address automatically the next time it connects while the TV is on. You can also type it above. " + setting
        }
        return "Leave the field empty to use the address the TV reports. " + setting
    }
}
