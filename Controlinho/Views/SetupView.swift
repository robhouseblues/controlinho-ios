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
            List {
                Section {
                    if isScanning && found.isEmpty {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Looking for Samsung TVs…").foregroundStyle(.secondary)
                        }
                    } else if found.isEmpty {
                        Text("No TVs found. Make sure the TV is on and connected to the same Wi-Fi.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(found) { tv in
                        Button { pair(tv.savedTV) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: "tv")
                                    .font(.title2)
                                    .foregroundStyle(.tint)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tv.name).foregroundStyle(.primary)
                                    Text([tv.model, tv.host].compactMap { $0 }.joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("On this network")
                        Spacer()
                        if !isScanning {
                            Button("Scan again") { Task { await scan() } }
                                .font(.caption)
                                .textCase(nil)
                        }
                    }
                }

                Section {
                    TextField("192.168.0.42", text: $manualHost)
                        .keyboardType(.numbersAndPunctuation)
                        .submitLabel(.go)
                        .onSubmit { Task { await addManual() } }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button {
                        Task { await addManual() }
                    } label: {
                        if isCheckingManual {
                            ProgressView()
                        } else {
                            Text("Connect")
                        }
                    }
                    .disabled(!LocalNetwork.isPrivateIPv4(manualHost) || isCheckingManual)
                } header: {
                    Text("Enter IP address")
                } footer: {
                    Text(manualError ?? "Find it on the TV under Settings › General › Network › Network Status.")
                        .foregroundStyle(manualError == nil ? Color.secondary : Color.red)
                }
            }
            .navigationTitle("Connect a TV")
            .toolbar {
                if store.tv != nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .task { await scan() }
        }
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
