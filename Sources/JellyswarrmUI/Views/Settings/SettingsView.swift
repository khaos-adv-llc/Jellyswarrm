// MARK: - SettingsView.swift

// Jellyswarrm — GPL v3 with App Store exception

import JellyswarrmCore
import SwiftUI

public struct SettingsView: View {
    public init() {}

    @Environment(AppState.self) private var appState
    @State private var showAddServer = false
    @State private var showAddSeerr = false
    @State private var showSignOutConfirm = false

    private var fadeBackground: Color {
        #if os(macOS)
            return Color(nsColor: .windowBackgroundColor)
        #elseif os(tvOS)
            return Color.black
        #else
            return Color(uiColor: .systemBackground)
        #endif
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                formContent
                VStack(spacing: 0) {
                    LinearGradient(
                        colors: [fadeBackground, .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 32)
                    Spacer()
                    LinearGradient(
                        colors: [.clear, fadeBackground],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 48)
                }
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var formContent: some View {
        Form {
                // MARK: Jellyfin Servers

                Section("Jellyfin Servers") {
                    if appState.savedServers.isEmpty {
                        Text("No servers configured")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.savedServers) { server in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(server.name)
                                        .fontWeight(.medium)
                                    Text(server.baseURL.absoluteString)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text("Signed in as \(server.username)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if appState.currentServer?.id == server.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                appState.setActiveServer(server)
                            }
                        }
                        .onDelete { indices in
                            for i in indices {
                                appState.removeServer(appState.savedServers[i])
                            }
                        }
                    }

                    Button {
                        showAddServer = true
                    } label: {
                        Label("Add Server", systemImage: "plus.circle")
                    }
                }

                // MARK: Seerr

                Section("Seerr") {
                    if let seerr = appState.seerrServer {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(seerr.name)
                                    .fontWeight(.medium)
                                Text(seerr.baseURL.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }

                        Button(role: .destructive) {
                            appState.removeSeerrServer(seerr)
                        } label: {
                            Label("Remove Seerr", systemImage: "trash")
                        }
                    } else {
                        Text("Not configured")
                            .foregroundStyle(.secondary)
                        Button {
                            showAddSeerr = true
                        } label: {
                            Label("Connect Seerr", systemImage: "plus.circle")
                        }
                    }
                }

                // MARK: Playback

                Section("Playback") {
                    NavigationLink("Playback Quality") {
                        PlaybackSettingsView()
                    }
                }

                // MARK: About

                Section("About") {
                    LabeledContent(
                        "Version",
                        value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                    )
                    LabeledContent("License", value: "GPL v3")
                    Link("Source Code", destination: URL(string: "https://github.com/khaos-adv-llc/jellyswarrm")!)
                    Link("Based on Fladder", destination: URL(string: "https://github.com/DonutWare/Fladder")!)
                }

                // MARK: Sign Out

                if appState.isAuthenticated {
                    Section {
                        Button(role: .destructive) {
                            showSignOutConfirm = true
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            #if os(tvOS)
                .padding(.top, 40)
            #endif
            .sheet(isPresented: $showAddServer) {
                ServerSetupView()
            }
            .sheet(isPresented: $showAddSeerr) {
                SeerrSetupView()
            }
            .confirmationDialog(
                "Sign Out?",
                isPresented: $showSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out from Current Server", role: .destructive) {
                    appState.signOut()
                }
                Button("Sign Out from All Servers", role: .destructive) {
                    appState.signOutAll()
                }
                Button("Cancel", role: .cancel) {}
            }
    }
}

public struct PlaybackSettingsView: View {
    public init() {}

    @AppStorage("preferDirectPlay") private var preferDirectPlay = true
    @AppStorage("maxBitrateMbps") private var maxBitrateMbps = 140
    @AppStorage("defaultSubtitleMode") private var defaultSubtitleMode = "off"

    public var body: some View {
        Form {
            Section("Streaming") {
                Toggle("Prefer Direct Play", isOn: $preferDirectPlay)
                Picker("Max Bitrate", selection: $maxBitrateMbps) {
                    Text("4 Mbps").tag(4)
                    Text("8 Mbps").tag(8)
                    Text("20 Mbps").tag(20)
                    Text("40 Mbps").tag(40)
                    Text("80 Mbps").tag(80)
                    Text("140 Mbps (Max)").tag(140)
                }
            }

            Section("Subtitles") {
                Picker("Default Subtitles", selection: $defaultSubtitleMode) {
                    Text("Off").tag("off")
                    Text("Always On").tag("always")
                    Text("Forced Only").tag("forced")
                    Text("Smart (hearing impaired)").tag("smart")
                }
            }
        }
        .navigationTitle("Playback")
        #if !os(tvOS) && !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
