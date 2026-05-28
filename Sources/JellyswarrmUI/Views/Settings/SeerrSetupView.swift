// MARK: - SeerrSetupView.swift

// Jellyswarrm — GPL v3 with App Store exception

import JellyswarrmCore
import SwiftUI

public struct SeerrSetupView: View {
    public init() {}

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = ""
    @State private var displayName = ""
    @State private var authMode: SeerrAuthMode = .apiKey
    @State private var apiKey = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isTesting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let seerrAPI = SeerrAPIClient.shared

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect Seerr")
                            .font(.headline)
                        Text(
                            "Seerr lets you browse content not yet on your server and submit requests. Your admin must have Seerr running."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section("Seerr Server") {
                    TextField("Server URL", text: $serverURL)
                        .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif

                    TextField("Display Name (optional)", text: $displayName)
                }

                Section("Sign In Method") {
                    Picker("Authentication", selection: $authMode) {
                        ForEach(SeerrAuthMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    #if os(tvOS)
                        .pickerStyle(.automatic)
                    #else
                        .pickerStyle(.segmented)
                    #endif
                }

                authFieldsSection

                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                if let success = successMessage {
                    Section {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section {
                    Button {
                        Task { await testAndSave() }
                    } label: {
                        HStack {
                            Spacer()
                            if isTesting {
                                ProgressView().controlSize(.small)
                                Text("Testing connection...")
                            } else {
                                Text("Connect")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(!canConnect || isTesting)
                }
            }
            .navigationTitle("Add Seerr")
            #if !os(tvOS) && !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            #endif
        }
    }

    @ViewBuilder
    private var authFieldsSection: some View {
        switch authMode {
        case .apiKey:
            Section {
                TextField("API Key", text: $apiKey)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                    .textContentType(.password)
            } header: {
                Text("API Key")
            } footer: {
                Text("Find your API key in Seerr → Settings → General → API Key")
                    .font(.caption)
            }
        case .jellyfinCredentials:
            Section {
                TextField("Jellyfin Username", text: $username)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                SecureField("Jellyfin Password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Jellyfin Credentials")
            } footer: {
                Text("Sign in to Seerr using your Jellyfin username and password. Future tvOS profiles will reuse their own Jellyfin credentials automatically.")
                    .font(.caption)
            }
        case .localAccount:
            Section {
                TextField("Email", text: $username)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                #endif
                SecureField("Password", text: $password)
                    .textContentType(.password)
            } header: {
                Text("Local Seerr Account")
            } footer: {
                Text("Sign in with a local Seerr account (email + password) independent from Jellyfin.")
                    .font(.caption)
            }
        }
    }

    private var canConnect: Bool {
        guard !serverURL.isEmpty else { return false }
        switch authMode {
        case .apiKey: return !apiKey.isEmpty
        case .jellyfinCredentials, .localAccount: return !username.isEmpty && !password.isEmpty
        }
    }

    private func testAndSave() async {
        guard let url = URL.normalizeJellyfinURL(serverURL) else {
            errorMessage = "Invalid server URL."
            return
        }

        isTesting = true
        errorMessage = nil
        successMessage = nil

        do {
            let server = SeerrServer(
                name: displayName.isEmpty ? (url.host ?? "Seerr") : displayName,
                baseURL: url
            )

            switch authMode {
            case .apiKey:
                let user = try await seerrAPI.testConnection(baseURL: url, apiKey: apiKey)
                try appState.addSeerrServer(server, apiKey: apiKey)
                let who = user.displayName ?? user.username ?? user.email ?? "Connected"
                successMessage = "Signed in to Seerr as \(who)"

            case .jellyfinCredentials:
                let cookie = try await seerrAPI.authenticateWithJellyfin(
                    baseURL: url,
                    username: username,
                    password: password
                )
                try appState.addSeerrServer(server, sessionCookie: cookie, authMode: .jellyfinCredentials)
                let user = try await seerrAPI.verifySession(baseURL: url, sessionCookie: cookie)
                let who = user.displayName ?? user.username ?? user.email ?? username
                successMessage = "Signed in to Seerr as \(who)"

            case .localAccount:
                let cookie = try await seerrAPI.authenticateWithLocalAccount(
                    baseURL: url,
                    email: username,
                    password: password
                )
                try appState.addSeerrServer(server, sessionCookie: cookie, authMode: .localAccount)
                let user = try await seerrAPI.verifySession(baseURL: url, sessionCookie: cookie)
                let who = user.displayName ?? user.username ?? user.email ?? username
                successMessage = "Signed in to Seerr as \(who)"
            }

            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()

        } catch let e as NetworkError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }

        isTesting = false
    }
}
