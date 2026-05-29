// MARK: - SettingsView.swift

// Jellyswarrm — LGPL-2.1-or-later

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
                    LabeledContent("License", value: "LGPL v2.1")
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
                .toolbar(.hidden, for: .navigationBar)
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
    @AppStorage("maxBitrateMbps") private var maxBitrateMbps = 0
    @AppStorage("defaultSubtitleMode") private var defaultSubtitleMode = "off"
    @AppStorage("playbackEngine") private var playbackEngineRaw = PlaybackEngine.auto.rawValue
    @AppStorage("allowHDRDirectPlay") private var allowHDRDirectPlay = true
    @AppStorage("vlcDirectPlay") private var vlcDirectPlay = true

    private var playbackEngine: Binding<PlaybackEngine> {
        Binding(
            get: { PlaybackEngine(rawValue: playbackEngineRaw) ?? .auto },
            set: { playbackEngineRaw = $0.rawValue }
        )
    }

    public var body: some View {
        Form {
            Section("Playback Engine") {
                Picker("Engine", selection: playbackEngine) {
                    ForEach(PlaybackEngine.allCases, id: \.self) { engine in
                        Text(engine.displayName).tag(engine)
                    }
                }
                #if !os(tvOS)
                .pickerStyle(.segmented)
                #endif

                Text(playbackEngine.wrappedValue.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Streaming") {
                Toggle("Prefer Direct Play", isOn: $preferDirectPlay)
            }

            Section("Quality & HDR") {
                Toggle("Allow HDR Direct Play", isOn: $allowHDRDirectPlay)
                Text("When on, HDR10, HLG, and Dolby Vision content plays with full HDR — requires a compatible display. Turn off to force SDR on all content.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if playbackEngine.wrappedValue != .avFoundation {
                    Toggle("VLC Direct Play (No Transcode)", isOn: $vlcDirectPlay)
                    Text("VLC plays files directly without server transcoding, preserving original audio (TrueHD, DTS-HD, Atmos) and HDR video.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Picker("Max Streaming Bitrate", selection: $maxBitrateMbps) {
                    Text("4 Mbps (SD)").tag(4)
                    Text("8 Mbps (HD)").tag(8)
                    Text("20 Mbps (Full HD)").tag(20)
                    Text("40 Mbps (4K)").tag(40)
                    Text("80 Mbps (4K HDR)").tag(80)
                    Text("Unlimited").tag(0)
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
        .onAppear {
            if maxBitrateMbps == 140 { maxBitrateMbps = 0 }
        }
    }
}
