// MARK: - TVOSUserWelcomeView.swift
// Jellyswarrm — GPL v3 with App Store exception
//
// Shown on tvOS when a new system profile (user account) is detected and the
// app has at least one server already configured by another profile.
// The user chooses whether to reuse a known server or add a new one.

#if os(tvOS)
import SwiftUI
import JellyswarrmCore

public struct TVOSUserWelcomeView: View {

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // The servers discovered from the shared App Group store
    private var knownServers: [JellyfinServer] { appState.sharedServerConfigs }

    @State private var selectedServer: JellyfinServer?
    @State private var showAddNew = false

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                // Cinematic background gradient
                backgroundGradient

                VStack(spacing: 48) {
                    // Header
                    headerSection

                    if knownServers.isEmpty {
                        // Edge case: shared store was cleared between launches
                        emptyServerPrompt
                    } else {
                        serverGrid
                        addNewButton
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
            }
            .navigationDestination(item: $selectedServer) { server in
                TVOSLoginView(server: server)
            }
            .navigationDestination(isPresented: $showAddNew) {
                ServerSetupView()
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Subviews

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.06, blue: 0.12),
                Color(red: 0.10, green: 0.08, blue: 0.20)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var headerSection: some View {
        VStack(spacing: 16) {
            // App wordmark / logo placeholder
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 72, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Welcome to Jellyswarrm")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("Which server would you like to connect to?")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private var serverGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 24), count: min(knownServers.count, 3)),
            spacing: 24
        ) {
            ForEach(knownServers) { server in
                ServerTileButton(server: server) {
                    selectedServer = server
                }
            }
        }
    }

    private var addNewButton: some View {
        Button {
            showAddNew = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                Text("Connect to a different server")
                    .font(.title3)
            }
            .foregroundStyle(.white.opacity(0.6))
            .padding(.top, 8)
        }
        .buttonStyle(.plain)
    }

    private var emptyServerPrompt: some View {
        VStack(spacing: 24) {
            Text("No servers found.")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.7))
            Button("Set up a server") {
                showAddNew = true
            }
            .buttonStyle(TVOSPrimaryButtonStyle())
        }
    }
}

// MARK: - ServerTileButton

private struct ServerTileButton: View {
    let server: JellyfinServer
    let action: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 20) {
                // Server icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.6), .blue.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "server.rack")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white)
                }

                VStack(spacing: 6) {
                    Text(server.name)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(server.baseURL.host ?? server.baseURL.absoluteString)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.white.opacity(isFocused ? 0.15 : 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(.white.opacity(isFocused ? 0.35 : 0.10), lineWidth: 1)
                    )
            )
            .scaleEffect(isFocused ? 1.05 : 1.0)
            .shadow(color: .purple.opacity(isFocused ? 0.5 : 0), radius: 24, x: 0, y: 8)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
    }
}

// MARK: - Shared Button Style

/// A bold pill-shaped primary button suitable for tvOS focus engine.
public struct TVOSPrimaryButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 40)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
#endif
