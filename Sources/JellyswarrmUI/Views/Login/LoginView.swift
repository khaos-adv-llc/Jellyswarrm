// MARK: - LoginView.swift

// Jellyswarrm — GPL v3 with App Store exception

import JellyswarrmCore
import SwiftUI

struct LoginView: View {
    @Environment(AppState.self) private var appState
    @State private var showServerSetup = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.05, blue: 0.15), Color(red: 0.02, green: 0.02, blue: 0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Logo area
                VStack(spacing: 16) {
                    Image(systemName: "play.circle.fill")
                        .resizable()
                        .frame(width: 80, height: 80)
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)

                    Text("Jellyswarrm")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("Your Jellyfin media, beautifully reimagined")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }

                Spacer()

                // Actions
                VStack(spacing: 16) {
                    Button {
                        showServerSetup = true
                    } label: {
                        HStack {
                            Image(systemName: "server.rack")
                            Text("Connect to Jellyfin Server")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white)
                        .foregroundStyle(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)

                    Text("You'll need a running Jellyfin server to use this app.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showServerSetup) {
            ServerSetupView()
        }
    }
}
