// MARK: - TVOSSeerrOnboardingView.swift

// Jellyswarrm — GPL v3 with App Store exception
//
// Handles per-user Seerr authentication after a successful Jellyfin login on tvOS.
//
// Two cases land here (from AppState.seerrOnboardingNeeded()):
//
//   .needsJellyfinAuth   — Seerr is configured with Jellyfin credentials mode but
//                          the user authenticated via Quick Connect (no plaintext
//                          password available). Offer to try auto-auth via a new
//                          Jellyfin username+password prompt, OR skip Seerr for now.
//
//   .needsLocalCredentials — Seerr uses local accounts; prompt for Seerr email +
//                            password, offer skip.

#if os(tvOS)
    import JellyswarrmCore
    import SwiftUI

    public struct TVOSSeerrOnboardingView: View {
        let result: SeerrOnboardingResult
        let server: JellyfinServer

        @Environment(AppState.self) private var appState
        @Environment(\.dismiss) private var dismiss

        // Shared form state
        @State private var email = ""
        @State private var password = ""
        @State private var isWorking = false
        @State private var errorMessage: String?
        @State private var didSucceed = false

        public init(result: SeerrOnboardingResult, server: JellyfinServer) {
            self.result = result
            self.server = server
        }

        public var body: some View {
            ZStack {
                backgroundGradient

                if didSucceed {
                    successView
                } else {
                    mainContent
                }
            }
            .ignoresSafeArea()
        }

        // MARK: - Background

        private var backgroundGradient: some View {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.12),
                    Color(red: 0.10, green: 0.08, blue: 0.20),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }

        // MARK: - Main content switch

        @ViewBuilder
        private var mainContent: some View {
            switch result {
            case let .needsJellyfinAuth(seerrServer):
                jellyfinAuthView(seerrServer: seerrServer)
            case let .needsLocalCredentials(seerrServer):
                localCredentialsView(seerrServer: seerrServer)
            case .notNeeded:
                // Should never be shown for this case — dismiss immediately
                Color.clear.onAppear { dismiss() }
            }
        }

        // MARK: - Case: Jellyfin credentials

        private func jellyfinAuthView(seerrServer: SeerrServer) -> some View {
            formLayout(
                icon: "film.stack",
                title: "Connect \(seerrServer.name) to your account",
                subtitle: "\(seerrServer.name) is configured to use Jellyfin credentials.\nEnter your Jellyfin username and password to link your requests.",
                seerrName: seerrServer.name
            ) {
                VStack(spacing: 20) {
                    TVOSOnboardingInputField(
                        placeholder: "Jellyfin Username",
                        text: $email,
                        systemImage: "person",
                        isSecure: false
                    )
                    TVOSOnboardingInputField(
                        placeholder: "Jellyfin Password",
                        text: $password,
                        systemImage: "lock",
                        isSecure: true
                    )
                }
            } primaryAction: {
                await authenticateJellyfin(seerrServer: seerrServer)
            } skipAction: {
                dismiss()
            }
        }

        // MARK: - Case: Local Seerr account

        private func localCredentialsView(seerrServer: SeerrServer) -> some View {
            formLayout(
                icon: "person.badge.key.fill",
                title: "Sign in to \(seerrServer.name)",
                subtitle: "\(seerrServer.name) uses its own account system.\nEnter your \(seerrServer.name) email and password.",
                seerrName: seerrServer.name
            ) {
                VStack(spacing: 20) {
                    TVOSOnboardingInputField(
                        placeholder: "Email Address",
                        text: $email,
                        systemImage: "envelope",
                        isSecure: false
                    )
                    TVOSOnboardingInputField(
                        placeholder: "Password",
                        text: $password,
                        systemImage: "lock",
                        isSecure: true
                    )
                }
            } primaryAction: {
                await authenticateLocal(seerrServer: seerrServer)
            } skipAction: {
                dismiss()
            }
        }

        // MARK: - Shared Form Layout

        private func formLayout(
            icon: String,
            title: String,
            subtitle: String,
            seerrName _: String,
            @ViewBuilder fields: () -> some View,
            primaryAction: @escaping () async -> Void,
            skipAction: @escaping () -> Void
        ) -> some View {
            VStack(spacing: 48) {
                // Header
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [.purple.opacity(0.5), .blue.opacity(0.5)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 100, height: 100)

                        Image(systemName: icon)
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.white)
                    }
                    .padding(.top, 60)

                    Text(title)
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 120)

                // Form fields
                VStack(spacing: 20) {
                    fields()

                    if let error = errorMessage {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 160)

                // Buttons
                HStack(spacing: 32) {
                    Button("Skip for now") {
                        skipAction()
                    }
                    .buttonStyle(TVOSSecondaryButtonStyle())

                    Button(isWorking ? "Connecting…" : "Connect") {
                        Task { await primaryAction() }
                    }
                    .buttonStyle(TVOSPrimaryButtonStyle())
                    .disabled(email.isEmpty || password.isEmpty || isWorking)
                }

                Spacer()
            }
        }

        // MARK: - Success View

        private var successView: some View {
            VStack(spacing: 32) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple.opacity(0.5), .blue.opacity(0.5)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 120, height: 120)

                    Image(systemName: "checkmark")
                        .font(.system(size: 56, weight: .light))
                        .foregroundStyle(.white)
                }

                Text("All set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)

                Text("Your requests account is connected.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()
            }
            .onAppear {
                // Auto-dismiss after a short celebration beat
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    dismiss()
                }
            }
        }

        // MARK: - Auth Actions

        private func authenticateJellyfin(seerrServer: SeerrServer) async {
            isWorking = true
            errorMessage = nil
            do {
                try await SeerrAPIClient.shared.authenticateWithJellyfin(
                    seerrServer: seerrServer,
                    username: email,
                    password: password
                )
                didSucceed = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }

        private func authenticateLocal(seerrServer: SeerrServer) async {
            isWorking = true
            errorMessage = nil
            do {
                try await SeerrAPIClient.shared.authenticateWithLocalAccount(
                    seerrServer: seerrServer,
                    email: email,
                    password: password
                )
                didSucceed = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    // MARK: - TVOSOnboardingInputField

    // A slightly wider variant of TVOSInputField for the onboarding context.

    private struct TVOSOnboardingInputField: View {
        let placeholder: String
        @Binding var text: String
        let systemImage: String
        var isSecure: Bool = false

        @FocusState private var isFocused: Bool

        var body: some View {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(isFocused ? .purple : .white.opacity(0.4))
                    .frame(width: 28)
                    .animation(.easeInOut(duration: 0.2), value: isFocused)

                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textContentType(.password)
                        .focused($isFocused)
                } else {
                    TextField(placeholder, text: $text)
                        .textContentType(.emailAddress)
                        .focused($isFocused)
                }
            }
            .font(.title3)
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(isFocused ? 0.12 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(
                                isFocused ? .purple.opacity(0.8) : .white.opacity(0.12),
                                lineWidth: isFocused ? 2 : 1
                            )
                    )
            )
            .animation(.easeInOut(duration: 0.2), value: isFocused)
        }
    }
#endif
