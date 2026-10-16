import AuthenticationServices
import SwiftUI

/// TV Settings section for turning the TV on through SmartThings.
struct SmartThingsSection: View {
    @Environment(TVStore.self) private var store
    @Environment(SmartThings.self) private var smartThings
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var devices: [SmartThings.Device]?
    @State private var isWorking = false
    @State private var message: String?
    @State private var messageIsError = false

    var body: some View {
        Section {
            if !smartThings.isConfigured {
                NavigationLink("Set up SmartThings") { SmartThingsCredentialsView() }
            } else if !smartThings.isSignedIn {
                Button("Sign in with Samsung account") { Task { await signIn() } }
                    .disabled(isWorking)
                NavigationLink("App credentials") { SmartThingsCredentialsView() }
            } else {
                LabeledContent("TV", value: store.tv?.smartThingsDeviceName ?? "Not chosen")
                if let devices {
                    ForEach(devices) { device in
                        Button { choose(device) } label: {
                            HStack {
                                Text(device.displayName).foregroundStyle(.primary)
                                Spacer()
                                if device.id == store.tv?.smartThingsDeviceID {
                                    Image(systemName: "checkmark").foregroundStyle(.tint)
                                }
                            }
                        }
                    }
                } else {
                    Button("Choose TV") { Task { await loadDevices() } }
                        .disabled(isWorking)
                }
                if let deviceID = store.tv?.smartThingsDeviceID {
                    Button("Turn TV on now") { Task { await turnOn(deviceID) } }
                        .disabled(isWorking)
                }
                Button("Sign out", role: .destructive) {
                    smartThings.signOut()
                    devices = nil
                    message = nil
                }
            }
        } header: {
            HStack {
                Text("SmartThings")
                if isWorking { ProgressView().controlSize(.small) }
            }
        } footer: {
            Text(message ?? footer)
                .foregroundStyle(messageIsError ? Color.orange : Color.secondary)
        }
    }

    private var footer: String {
        if !smartThings.isConfigured {
            return "Optional backup for turning the TV on. It goes through Samsung's cloud, so it works when the TV's network connection is asleep. Needs a one-time setup — see SMARTTHINGS_SETUP.md."
        }
        if !smartThings.isSignedIn {
            return "Sign in with the Samsung account your TV is added to in the SmartThings app."
        }
        return "Power uses SmartThings and the wake signal together. Open the app at least once a month to stay signed in."
    }

    private func signIn() async {
        let state = UUID().uuidString
        guard let url = smartThings.authorizeURL(state: state) else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let callback = try await webAuthenticationSession.authenticate(
                using: url,
                callbackURLScheme: SmartThings.callbackScheme,
                preferredBrowserSession: .ephemeral
            )
            try await smartThings.completeSignIn(callback: callback, expectedState: state)
            show(nil)
            await loadDevices()
        } catch ASWebAuthenticationSessionError.canceledLogin {
            show(nil)
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    private func loadDevices() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let found = try await smartThings.devices()
            devices = found
            show(found.isEmpty ? "No devices found. Add your TV in the SmartThings app first." : nil, isError: found.isEmpty)
            if found.count == 1, store.tv?.smartThingsDeviceID == nil { choose(found[0]) }
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    private func choose(_ device: SmartThings.Device) {
        store.tv?.smartThingsDeviceID = device.id
        store.tv?.smartThingsDeviceName = device.displayName
    }

    private func turnOn(_ deviceID: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await smartThings.turnOn(deviceID: deviceID)
            show("Sent. The TV should turn on in a few seconds.")
        } catch {
            show(error.localizedDescription, isError: true)
        }
    }

    private func show(_ text: String?, isError: Bool = false) {
        message = text
        messageIsError = isError
    }
}

/// Where the user pastes the OAuth app details printed by `smartthings apps:create`.
struct SmartThingsCredentialsView: View {
    @Environment(SmartThings.self) private var smartThings
    @Environment(\.dismiss) private var dismiss

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var redirectURL = ""

    var body: some View {
        Form {
            Section {
                Group {
                    TextField("Client ID", text: $clientID)
                    SecureField("Client Secret", text: $clientSecret)
                    TextField("Redirect URL (https://…)", text: $redirectURL)
                        .keyboardType(.URL)
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
            } footer: {
                Text("Copy these from the output of `smartthings apps:create`. The redirect URL must match the one you registered exactly, including any trailing slash. They're stored in the iPhone's Keychain.")
            }

            if smartThings.isConfigured {
                Section {
                    Button("Remove SmartThings", role: .destructive) {
                        smartThings.save(nil)
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle("SmartThings App")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    smartThings.save(SmartThings.Credentials(
                        clientID: clientID.trimmingCharacters(in: .whitespaces),
                        clientSecret: clientSecret.trimmingCharacters(in: .whitespaces),
                        redirectURL: redirectURL.trimmingCharacters(in: .whitespaces)
                    ))
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
        .onAppear {
            if let credentials = smartThings.credentials {
                clientID = credentials.clientID
                clientSecret = credentials.clientSecret
                redirectURL = credentials.redirectURL
            }
        }
    }

    private var isValid: Bool {
        !clientID.trimmingCharacters(in: .whitespaces).isEmpty
            && !clientSecret.trimmingCharacters(in: .whitespaces).isEmpty
            && redirectURL.lowercased().hasPrefix("https://")
    }
}
