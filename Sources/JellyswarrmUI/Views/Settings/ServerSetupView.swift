// MARK: - ServerSetupView.swift

// Jellyswarrm — GPL v3 with App Store exception

import JellyswarrmCore
import SwiftUI

public struct ServerSetupView: View {
    public init() {}

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = ""
    @State private var username = ""
    @State private var password = ""
    @State private var serverName = ""
    @State private var isConnecting = false
    @State private var errorMessage: String?
    @State private var connectionSuccess = false

    private let api = JellyfinAPIClient.shared

    public var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Server URL", text: $serverURL)
                        .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                        .textContentType(.URL)

                    TextField("Display Name (optional)", text: $serverName)
                }

                Section("Account") {
                    TextField("Username", text: $username)
                        .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                        .textContentType(.username)

                    SecureField("Password", text: $password)
                        .textContentType(.password)
                }

                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .foregroundStyle(.red)
                                .font(.callout)
                        }
                    }
                }

                if connectionSuccess {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Connected successfully!")
                                .foregroundStyle(.green)
                        }
                    }
                }

                Section {
                    Button {
                        Task { await connect() }
                    } label: {
                        HStack {
                            Spacer()
                            if isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Connecting...")
                            } else {
                                Text("Connect")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(serverURL.isEmpty || username.isEmpty || isConnecting)
                }
            }
            .navigationTitle("Add Server")
            #if !os(tvOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            #endif
        }
    }

    private func connect() async {
        guard let url = URL.normalizeJellyfinURL(serverURL) else {
            errorMessage = "Invalid server URL. Make sure it starts with http:// or https://"
            return
        }

        isConnecting = true
        errorMessage = nil
        connectionSuccess = false

        let deviceId = UIDeviceHelper.deviceId
        let deviceName = UIDeviceHelper.deviceName
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        do {
            let auth = try await api.authenticate(
                serverURL: url,
                username: username,
                password: password,
                deviceId: deviceId,
                deviceName: deviceName,
                appVersion: appVersion
            )

            let server = JellyfinServer(
                name: serverName.isEmpty ? (url.host ?? "Jellyfin") : serverName,
                baseURL: url,
                userId: auth.userId,
                username: username
            )

            try appState.addServer(server, token: auth.accessToken)
            connectionSuccess = true

            // Small delay to show success, then dismiss
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()

        } catch let netError as NetworkError {
            errorMessage = netError.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isConnecting = false
    }
}
