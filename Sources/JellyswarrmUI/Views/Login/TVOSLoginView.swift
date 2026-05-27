// MARK: - TVOSLoginView.swift
// Jellyswarrm — GPL v3 with App Store exception
//
// Primary login screen for tvOS.  Quick Connect is the default path (no keyboard
// needed); password entry is available as a fallback.  After a successful Jellyfin
// auth the view hands off to TVOSSeerrOnboardingView when Seerr needs per-user setup.

#if os(tvOS)
import SwiftUI
import JellyswarrmCore

public struct TVOSLoginView: View {

    let server: JellyfinServer

    @Environment(AppState.self) private var appState

    // Navigation to Seerr onboarding after login
    @State private var seerrResult: SeerrOnboardingResult?
    @State private var showSeerrOnboarding = false

    // Quick Connect state
    @State private var quickConnectState: QuickConnectPhase = .idle
    @State private var qcCode: String = ""
    @State private var qcSecret: String = ""
    @State private var qcPollingTask: Task<Void, Never>?

    // Password fallback
    @State private var showPasswordEntry = false
    @State private var username = ""
    @State private var password = ""
    @State private var isAuthenticating = false
    @State private var authError: String?

    public init(server: JellyfinServer) {
        self.server = server
    }

    public var body: some View {
        ZStack {
            backgroundGradient

            VStack(spacing: 0) {
                serverHeader
                    .padding(.top, 60)
                    .padding(.bottom, 48)

                if showPasswordEntry {
                    passwordSection
                } else {
                    quickConnectSection
                }

                Spacer()
            }
            .padding(.horizontal, 120)
        }
        .ignoresSafeArea()
        .onDisappear { qcPollingTask?.cancel() }
        // Navigate to Seerr onboarding when needed
        .navigationDestination(isPresented: $showSeerrOnboarding) {
            if let result = seerrResult {
                TVOSSeerrOnboardingView(result: result, server: server)
            }
        }
    }

    // MARK: - Background

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

    // MARK: - Server Header

    private var serverHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text("Sign in to \(server.name)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text(server.baseURL.host ?? server.baseURL.absoluteString)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Quick Connect Section

    private var quickConnectSection: some View {
        VStack(spacing: 40) {
            switch quickConnectState {
            case .idle:
                idleQuickConnect

            case .waitingForApproval:
                waitingQuickConnect

            case .failed(let message):
                errorQuickConnect(message: message)
            }
        }
    }

    private var idleQuickConnect: some View {
        VStack(spacing: 32) {
            // Explanation card
            explanationCard(
                icon: "qrcode",
                title: "Quick Connect",
                body: "Open Jellyfin on your phone or browser, go to\nSettings → Quick Connect, then enter the code shown here."
            )

            Button("Get Quick Connect Code") {
                startQuickConnect()
            }
            .buttonStyle(TVOSPrimaryButtonStyle())

            passwordToggleButton
        }
    }

    private var waitingQuickConnect: some View {
        VStack(spacing: 40) {
            // Large animated code display
            VStack(spacing: 16) {
                Text("Enter this code in Jellyfin")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))

                Text(qcCode)
                    .font(.system(size: 96, weight: .bold, design: .monospaced))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .tracking(12)

                // Animated pulse ring
                Circle()
                    .stroke(.purple.opacity(0.4), lineWidth: 2)
                    .frame(width: 12, height: 12)
                    .modifier(PulsingModifier())
            }
            .padding(48)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                    )
            )

            HStack(spacing: 24) {
                Button("Cancel") {
                    cancelQuickConnect()
                }
                .buttonStyle(TVOSSecondaryButtonStyle())

                Button("Use Password Instead") {
                    cancelQuickConnect()
                    showPasswordEntry = true
                }
                .buttonStyle(TVOSSecondaryButtonStyle())
            }
        }
    }

    private func errorQuickConnect(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)

            Text(message)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)

            HStack(spacing: 24) {
                Button("Try Again") {
                    quickConnectState = .idle
                }
                .buttonStyle(TVOSPrimaryButtonStyle())

                Button("Use Password") {
                    showPasswordEntry = true
                }
                .buttonStyle(TVOSSecondaryButtonStyle())
            }
        }
    }

    // MARK: - Password Section

    private var passwordSection: some View {
        VStack(spacing: 32) {
            explanationCard(
                icon: "key.fill",
                title: "Sign in with Password",
                body: "Enter your Jellyfin username and password."
            )

            VStack(spacing: 20) {
                // Username field
                TVOSInputField(
                    placeholder: "Username",
                    text: $username,
                    systemImage: "person"
                )

                // Password field
                TVOSInputField(
                    placeholder: "Password",
                    text: $password,
                    systemImage: "lock",
                    isSecure: true
                )
            }

            if let error = authError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red.opacity(0.9))
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 24) {
                Button("Back") {
                    showPasswordEntry = false
                    authError = nil
                }
                .buttonStyle(TVOSSecondaryButtonStyle())

                Button(isAuthenticating ? "Signing in…" : "Sign In") {
                    authenticateWithPassword()
                }
                .buttonStyle(TVOSPrimaryButtonStyle())
                .disabled(username.isEmpty || isAuthenticating)
            }
        }
    }

    private var passwordToggleButton: some View {
        Button("Sign in with password instead") {
            showPasswordEntry = true
        }
        .font(.callout)
        .foregroundStyle(.white.opacity(0.5))
        .buttonStyle(.plain)
    }

    // MARK: - Helper Views

    private func explanationCard(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 24) {
            Image(systemName: icon)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.purple)
                .frame(width: 48)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)

                Text(body)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.06))
        )
    }

    // MARK: - Quick Connect Logic

    private func startQuickConnect() {
        quickConnectState = .waitingForApproval
        qcPollingTask?.cancel()

        qcPollingTask = Task {
            do {
                let deviceId  = UIDeviceHelper.deviceId
                let deviceName = UIDeviceHelper.deviceName
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

                // 1. Initiate
                let initiated = try await JellyfinAPIClient.shared.initiateQuickConnect(
                    serverURL: server.baseURL,
                    deviceId: deviceId,
                    deviceName: deviceName,
                    appVersion: appVersion
                )
                guard !Task.isCancelled else { return }
                qcCode = initiated.code
                qcSecret = initiated.secret

                // 2. Poll every 5 seconds for up to 10 minutes
                let deadline = Date().addingTimeInterval(600)
                while Date() < deadline {
                    try await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }

                    let state = try await JellyfinAPIClient.shared.checkQuickConnect(
                        serverURL: server.baseURL,
                        secret: qcSecret,
                        deviceId: deviceId,
                        deviceName: deviceName,
                        appVersion: appVersion
                    )
                    guard !Task.isCancelled else { return }

                    if state.authenticated {
                        // 3. Exchange secret for token
                        let authResponse = try await JellyfinAPIClient.shared.authenticateWithQuickConnect(
                            serverURL: server.baseURL,
                            secret: qcSecret,
                            deviceId: deviceId,
                            deviceName: deviceName,
                            appVersion: appVersion
                        )
                        guard !Task.isCancelled else { return }
                        await handleSuccessfulAuth(authResponse)
                        return
                    }
                }
                // Timed out
                quickConnectState = .failed("The Quick Connect code expired. Please try again.")
            } catch is CancellationError {
                // Silently cancelled
            } catch {
                quickConnectState = .failed(error.localizedDescription)
            }
        }
    }

    private func cancelQuickConnect() {
        qcPollingTask?.cancel()
        qcPollingTask = nil
        qcCode = ""
        qcSecret = ""
        quickConnectState = .idle
    }

    // MARK: - Password Auth Logic

    private func authenticateWithPassword() {
        isAuthenticating = true
        authError = nil

        Task {
            do {
                let deviceId   = UIDeviceHelper.deviceId
                let deviceName = UIDeviceHelper.deviceName
                let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

                let authResponse = try await JellyfinAPIClient.shared.authenticate(
                    serverURL: server.baseURL,
                    username: username,
                    password: password,
                    deviceId: deviceId,
                    deviceName: deviceName,
                    appVersion: appVersion
                )
                await handleSuccessfulAuth(authResponse)
            } catch {
                authError = error.localizedDescription
            }
            isAuthenticating = false
        }
    }

    // MARK: - Post-Auth Seerr Routing

    @MainActor
    private func handleSuccessfulAuth(_ authResponse: AuthResponse) async {
        // Persist login into AppState — use userId/username returned by the server
        let updatedServer = JellyfinServer(
            id: server.id,
            name: server.name,
            baseURL: server.baseURL,
            userId: authResponse.user.id,
            username: authResponse.user.name
        )
        appState.completeLogin(server: updatedServer, token: authResponse.accessToken)

        // Determine whether Seerr onboarding is needed
        let result = await appState.seerrOnboardingNeeded()
        switch result {
        case .notNeeded:
            // All done — AppState is now authenticated, RootView will transition
            break
        case .needsJellyfinAuth, .needsLocalCredentials:
            seerrResult = result
            showSeerrOnboarding = true
        }
    }
}

// MARK: - Phase Enum

private enum QuickConnectPhase {
    case idle
    case waitingForApproval
    case failed(String)
}

// MARK: - Pulsing Modifier

private struct PulsingModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                    scale = 2.5
                }
            }
    }
}

// MARK: - TVOSSecondaryButtonStyle

public struct TVOSSecondaryButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .fontWeight(.medium)
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 32)
            .padding(.vertical, 16)
            .background(
                Capsule()
                    .fill(.white.opacity(configuration.isPressed ? 0.15 : 0.08))
                    .overlay(
                        Capsule()
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - TVOSInputField

private struct TVOSInputField: View {
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
                    .textContentType(isSecure ? .password : .username)
                    .focused($isFocused)
            } else {
                TextField(placeholder, text: $text)
                    .textContentType(.username)
                    .focused($isFocused)
            }
        }
        .font(.title3)
        .foregroundStyle(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(isFocused ? 0.12 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isFocused ? .purple.opacity(0.8) : .white.opacity(0.12), lineWidth: isFocused ? 2 : 1)
                )
        )
        .animation(.easeInOut(duration: 0.2), value: isFocused)
    }
}
#endif
