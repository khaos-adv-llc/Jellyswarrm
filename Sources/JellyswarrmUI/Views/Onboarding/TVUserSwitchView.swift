// MARK: - TVUserSwitchView.swift

// Jellyswarrm — LGPL-2.1-or-later
//
// Shown when a new tvOS system user is detected on this Apple TV. We offer
// either a quick-connect to the server URL the previous user(s) had configured,
// or a full new-server setup.

import JellyswarrmCore
import SwiftUI

public struct TVUserSwitchView: View {
    public init() {}

    @Environment(AppState.self) private var appState
    @State private var showFullSetup = false
    @State private var quickConnect: QuickConnectURL?

    private struct QuickConnectURL: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(white: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "person.crop.circle.badge.plus")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                    .foregroundStyle(.white, .indigo)
                    .symbolRenderingMode(.palette)

                VStack(spacing: 12) {
                    Text("Welcome!")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("It looks like you're a new user on this Apple TV.")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }

                Spacer()

                VStack(spacing: 16) {
                    if let url = appState.lastServerURL {
                        Button {
                            quickConnect = QuickConnectURL(url: url)
                        } label: {
                            VStack(spacing: 4) {
                                Text("Connect to \(url.host ?? url.absoluteString)")
                                    .fontWeight(.semibold)
                                Text(url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                        .controlSize(.large)
                    }

                    Button("Set up a new server") {
                        showFullSetup = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 80)
                .padding(.bottom, 80)
            }
        }
        .sheet(isPresented: $showFullSetup) {
            OnboardingWizardView(initialServerURL: nil)
        }
        .sheet(item: $quickConnect) { qc in
            OnboardingWizardView(initialServerURL: qc.url)
        }
    }
}
