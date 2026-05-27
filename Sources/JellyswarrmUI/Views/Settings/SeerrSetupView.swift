// MARK: - SeerrSetupView.swift
// Jellyswarrm — GPL v3 with App Store exception

import SwiftUI
import JellyswarrmCore

struct SeerrSetupView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL = ""
    @State private var apiKey = ""
    @State private var displayName = ""
    @State private var isTesting = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private let seerrAPI = SeerrAPIClient.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Connect Jellyseerr")
                            .font(.headline)
                        Text("Jellyseerr lets you browse content not yet on your server and submit requests. Your admin must have Jellyseerr running.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(.init(top: 8, leading: 0, bottom: 8, trailing: 0))
                }

                Section("Jellyseerr Server") {
                    TextField("Server URL", text: $serverURL)
                        .autocorrectionDisabled()
                        #if !os(tvOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif

                    TextField("Display Name (optional)", text: $displayName)
                }

                Section {
                    TextField("API Key", text: $apiKey)
                        .autocorrectionDisabled()
                        #if !os(tvOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .textContentType(.password)
                } header: {
                    Text("API Key")
                } footer: {
                    Text("Find your API key in Jellyseerr → Settings → General → API Key")
                        .font(.caption)
                }

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
                    .disabled(serverURL.isEmpty || apiKey.isEmpty || isTesting)
                }
            }
            .navigationTitle("Add Jellyseerr")
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

    private func testAndSave() async {
        guard let url = URL.normalizeJellyfinURL(serverURL) else {
            errorMessage = "Invalid server URL."
            return
        }

        isTesting = true
        errorMessage = nil
        successMessage = nil

        do {
            let status = try await seerrAPI.testConnection(baseURL: url, apiKey: apiKey)
            let server = SeerrServer(
                name: displayName.isEmpty ? (url.host ?? "Jellyseerr") : displayName,
                baseURL: url
            )
            try appState.addSeerrServer(server, apiKey: apiKey)
            successMessage = "Connected to Jellyseerr v\(status.version)"

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
