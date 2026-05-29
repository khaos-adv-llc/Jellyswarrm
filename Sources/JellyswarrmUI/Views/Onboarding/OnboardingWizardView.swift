// MARK: - OnboardingWizardView.swift

// Jellyswarrm — LGPL-2.1-or-later
//
// Multi-step onboarding wizard covering Jellyfin server setup, sign-in,
// and optional Seerr connection. Used on first launch and on tvOS
// when a new system user picks "set up a new server".

import JellyswarrmCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public enum OnboardingStep: Int, CaseIterable {
    case welcome
    case serverURL
    case jellyfinLogin
    case seerrPrompt
    case seerrURL
    case seerrAuthMode
    case seerrAPIKey
    case seerrJellyfinConfirm
    case done
}

public struct OnboardingWizardView: View {
    let initialServerURL: URL?

    public init(initialServerURL: URL? = nil) {
        self.initialServerURL = initialServerURL
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var step: OnboardingStep = .welcome

    // Server / Jellyfin
    @State private var serverURL: String = ""
    @State private var serverDisplayName: String = ""
    @State private var verifiedServerURL: URL?
    @State private var username: String = ""
    @State private var password: String = ""

    // Seerr
    @State private var seerrURL: String = ""
    @State private var verifiedSeerrURL: URL?
    @State private var seerrAuthMode: SeerrAuthMode = .jellyfinCredentials
    @State private var seerrAPIKey: String = ""

    // UI
    @State private var isWorking = false
    @State private var errorMessage: String?

    private let jellyfin = JellyfinAPIClient.shared
    private let seerr = SeerrAPIClient.shared

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(white: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(stepPadding)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))

                stepIndicator
                    .padding(.bottom, 24)
            }
        }
        .task {
            appState.isOnboarding = true
            if let url = initialServerURL {
                serverURL = url.absoluteString
                step = .serverURL
            }
        }
    }

    private var stepPadding: CGFloat {
        #if os(tvOS)
            return 60
        #else
            return 40
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome: WelcomeStep(next: { advance(to: .serverURL) })
        case .serverURL:
            ServerURLStep(
                serverURL: $serverURL,
                serverDisplayName: $serverDisplayName,
                isWorking: $isWorking,
                errorMessage: $errorMessage,
                verify: verifyServerURL
            )
        case .jellyfinLogin:
            JellyfinLoginStep(
                serverHost: verifiedServerURL?.host ?? serverURL,
                username: $username,
                password: $password,
                isWorking: $isWorking,
                errorMessage: $errorMessage,
                signIn: signIn
            )
        case .seerrPrompt:
            SeerrPromptStep(
                onYes: { advance(to: .seerrURL) },
                onSkip: { advance(to: .done) }
            )
        case .seerrURL:
            SeerrURLStep(
                seerrURL: $seerrURL,
                isWorking: $isWorking,
                errorMessage: $errorMessage,
                verify: verifySeerrURL
            )
        case .seerrAuthMode:
            SeerrAuthModeStep(select: { mode in
                seerrAuthMode = mode
                switch mode {
                case .apiKey: advance(to: .seerrAPIKey)
                case .jellyfinCredentials: advance(to: .seerrJellyfinConfirm)
                case .localAccount: advance(to: .seerrAPIKey) // collected the same way (text fields)
                }
            })
        case .seerrAPIKey:
            SeerrAPIKeyStep(
                mode: seerrAuthMode,
                apiKey: $seerrAPIKey,
                username: $username,
                password: $password,
                isWorking: $isWorking,
                errorMessage: $errorMessage,
                connect: connectSeerr
            )
        case .seerrJellyfinConfirm:
            SeerrJellyfinConfirmStep(
                isWorking: $isWorking,
                errorMessage: $errorMessage,
                connect: connectSeerrJellyfin
            )
        case .done:
            DoneStep(start: {
                appState.completeOnboarding()
                dismiss()
            })
        }
    }

    // MARK: - Step indicator

    private var stepIndicator: some View {
        let steps = OnboardingStep.allCases
        return HStack(spacing: 8) {
            ForEach(steps, id: \.rawValue) { s in
                Circle()
                    .fill(dotColor(for: s))
                    .frame(width: 8, height: 8)
            }
        }
    }

    private func dotColor(for s: OnboardingStep) -> Color {
        if s.rawValue < step.rawValue { return .gray }
        if s == step { return .indigo }
        return .white.opacity(0.25)
    }

    // MARK: - Transitions

    private func advance(to next: OnboardingStep) {
        errorMessage = nil
        withAnimation(.easeInOut(duration: 0.4)) {
            step = next
        }
    }

    // MARK: - Actions

    private func verifyServerURL() async {
        errorMessage = nil
        guard let url = URL.normalizeJellyfinURL(serverURL) else {
            errorMessage = "Invalid server URL."
            return
        }
        isWorking = true
        defer { isWorking = false }
        // We don't have a public-info API in core; the auth step validates the URL.
        verifiedServerURL = url
        advance(to: .jellyfinLogin)
    }

    private func signIn() async {
        errorMessage = nil
        guard let url = verifiedServerURL else {
            errorMessage = "Server URL missing."
            return
        }
        isWorking = true
        defer { isWorking = false }

        let deviceId = UIDeviceHelper.deviceId
        let deviceName = UIDeviceHelper.deviceName
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        do {
            let auth = try await jellyfin.authenticate(
                serverURL: url,
                username: username,
                password: password,
                deviceId: deviceId,
                deviceName: deviceName,
                appVersion: appVersion
            )

            let server = JellyfinServer(
                name: serverDisplayName.isEmpty ? (url.host ?? "Jellyfin") : serverDisplayName,
                baseURL: url,
                userId: auth.userId,
                username: username
            )
            try appState.addServer(server, token: auth.accessToken)

            // If we already have a Seerr server configured (e.g. set up by another
            // tvOS profile), offer to re-auth automatically with the same creds.
            if appState.seerrServer != nil {
                await appState.autoAuthSeerr(username: username, password: password)
                advance(to: .done)
            } else if appState.lastSeerrURL != nil {
                // Pre-fill the Seerr step using the shared hint.
                seerrURL = appState.lastSeerrURL?.absoluteString ?? ""
                if let mode = appState.lastSeerrAuthMode {
                    seerrAuthMode = mode
                }
                advance(to: .seerrPrompt)
            } else {
                advance(to: .seerrPrompt)
            }
        } catch let e as NetworkError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifySeerrURL() async {
        errorMessage = nil
        guard let url = URL.normalizeJellyfinURL(seerrURL) else {
            errorMessage = "Invalid Seerr URL."
            return
        }
        verifiedSeerrURL = url
        advance(to: .seerrAuthMode)
    }

    private func connectSeerr() async {
        errorMessage = nil
        guard let url = verifiedSeerrURL else {
            errorMessage = "Seerr URL missing."
            return
        }
        isWorking = true
        defer { isWorking = false }

        let server = SeerrServer(name: url.host ?? "Seerr", baseURL: url)
        do {
            switch seerrAuthMode {
            case .apiKey:
                _ = try await seerr.testConnection(baseURL: url, apiKey: seerrAPIKey)
                try appState.addSeerrServer(server, apiKey: seerrAPIKey)
            case .jellyfinCredentials:
                let cookie = try await seerr.authenticateWithJellyfin(
                    baseURL: url, username: username, password: password
                )
                try appState.addSeerrServer(server, sessionCookie: cookie, authMode: .jellyfinCredentials)
            case .localAccount:
                let cookie = try await seerr.authenticateWithLocalAccount(
                    baseURL: url, email: username, password: password
                )
                try appState.addSeerrServer(server, sessionCookie: cookie, authMode: .localAccount)
            }
            advance(to: .done)
        } catch let e as NetworkError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func connectSeerrJellyfin() async {
        seerrAuthMode = .jellyfinCredentials
        await connectSeerr()
    }
}

// MARK: - Step subviews

private struct WelcomeStep: View {
    let next: () -> Void
    @State private var appeared = false

    @ViewBuilder
    private var appLogo: some View {
        #if os(macOS)
        if let nsImage = NSImage(named: "AppIcon") {
            Image(nsImage: nsImage)
                .resizable()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else {
            fallbackLogo
        }
        #elseif canImport(UIKit)
        if let uiImage = UIImage(named: "AppIcon") {
            Image(uiImage: uiImage)
                .resizable()
                .frame(width: 120, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        } else {
            fallbackLogo
        }
        #else
        fallbackLogo
        #endif
    }

    private var fallbackLogo: some View {
        Image(systemName: "play.circle.fill")
            .resizable()
            .scaledToFit()
            .frame(width: 140, height: 140)
            .foregroundStyle(.white, .indigo)
            .symbolRenderingMode(.palette)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            appLogo
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
                .padding(.top, 8)

            VStack(spacing: 8) {
                Text("Welcome to Jellyswarrm")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Your media, beautifully organized.")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Spacer()

            Button("Get Started", action: next)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.indigo)
                .padding(.bottom, 16)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeIn(duration: 0.3)) { appeared = true } }
    }
}

private struct ServerURLStep: View {
    @Binding var serverURL: String
    @Binding var serverDisplayName: String
    @Binding var isWorking: Bool
    @Binding var errorMessage: String?
    let verify: () async -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Your Jellyfin Server")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Enter the URL of your Jellyfin server")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))

            VStack(spacing: 12) {
                TextField("https://jellyfin.example.com", text: $serverURL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    #endif
                    .textContentType(.URL)
                    #if !os(tvOS)
                        .textFieldStyle(.roundedBorder)
                    #endif
                TextField("Display name (optional)", text: $serverDisplayName)
                    #if !os(tvOS)
                        .textFieldStyle(.roundedBorder)
                    #endif
            }
            .padding(.horizontal, 16)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()

            Button {
                Task { await verify() }
            } label: {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text("Verify & Continue")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)
            .disabled(serverURL.isEmpty || isWorking)
            .padding(.bottom, 16)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeIn(duration: 0.3)) { appeared = true } }
    }
}

private struct JellyfinLoginStep: View {
    let serverHost: String
    @Binding var username: String
    @Binding var password: String
    @Binding var isWorking: Bool
    @Binding var errorMessage: String?
    let signIn: () async -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Sign In")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(serverHost)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    .textContentType(.username)
                    #if !os(tvOS)
                        .textFieldStyle(.roundedBorder)
                    #endif
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    #if !os(tvOS)
                        .textFieldStyle(.roundedBorder)
                    #endif
            }
            .padding(.horizontal, 16)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()

            Button {
                Task { await signIn() }
            } label: {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text("Sign In")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)
            .disabled(username.isEmpty || password.isEmpty || isWorking)
            .padding(.bottom, 16)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeIn(duration: 0.3)) { appeared = true } }
    }
}

private struct SeerrPromptStep: View {
    let onYes: () -> Void
    let onSkip: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Do you use Seerr?")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Seerr lets you request movies and shows")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))

            VStack(spacing: 16) {
                Button("Yes, set it up", action: onYes)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.indigo)
                Button("Skip for now", action: onSkip)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            .padding(.horizontal, 16)

            Text("You can always add this later in Settings")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            Spacer()
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeIn(duration: 0.3)) { appeared = true } }
    }
}

private struct SeerrURLStep: View {
    @Binding var seerrURL: String
    @Binding var isWorking: Bool
    @Binding var errorMessage: String?
    let verify: () async -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Your Seerr Server")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            TextField("https://requests.example.com", text: $seerrURL)
                .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                #endif
                .textContentType(.URL)
                #if !os(tvOS)
                    .textFieldStyle(.roundedBorder)
                #endif
                .padding(.horizontal, 16)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()

            Button {
                Task { await verify() }
            } label: {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text("Verify & Continue")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)
            .disabled(seerrURL.isEmpty || isWorking)
            .padding(.bottom, 16)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeIn(duration: 0.3)) { appeared = true } }
    }
}

private struct SeerrAuthModeStep: View {
    let select: (SeerrAuthMode) -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("How do you want to sign in to Seerr?")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                modeCard(
                    title: "Jellyfin Account",
                    subtitle: "Use your Jellyfin username and password",
                    systemImage: "checkmark.shield.fill",
                    action: { select(.jellyfinCredentials) }
                )
                modeCard(
                    title: "API Key",
                    subtitle: "Use a Seerr API key",
                    systemImage: "key.fill",
                    action: { select(.apiKey) }
                )
                modeCard(
                    title: "Local Account",
                    subtitle: "Use a Seerr-specific account",
                    systemImage: "person.fill",
                    action: { select(.localAccount) }
                )
            }
            .padding(.horizontal, 16)

            Spacer()
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeIn(duration: 0.3)) { appeared = true } }
    }

    private func modeCard(title: String, subtitle: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(.indigo)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
            }
            .padding()
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct SeerrAPIKeyStep: View {
    let mode: SeerrAuthMode
    @Binding var apiKey: String
    @Binding var username: String
    @Binding var password: String
    @Binding var isWorking: Bool
    @Binding var errorMessage: String?
    let connect: () async -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(mode == .apiKey ? "API Key" : "Sign in to Seerr")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                if mode == .apiKey {
                    TextField("API Key", text: $apiKey)
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                        #if !os(tvOS)
                            .textFieldStyle(.roundedBorder)
                        #endif
                } else {
                    TextField(mode == .localAccount ? "Email" : "Username", text: $username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                        #if !os(tvOS)
                            .textFieldStyle(.roundedBorder)
                        #endif
                    SecureField("Password", text: $password)
                        #if !os(tvOS)
                            .textFieldStyle(.roundedBorder)
                        #endif
                }
            }
            .padding(.horizontal, 16)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()

            Button {
                Task { await connect() }
            } label: {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)
            .disabled(isWorking || (mode == .apiKey ? apiKey.isEmpty : (username.isEmpty || password.isEmpty)))
            .padding(.bottom, 16)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeIn(duration: 0.3)) { appeared = true } }
    }
}

private struct SeerrJellyfinConfirmStep: View {
    @Binding var isWorking: Bool
    @Binding var errorMessage: String?
    let connect: () async -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Connect with Jellyfin")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Seerr will use your Jellyfin credentials automatically.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()

            Button {
                Task { await connect() }
            } label: {
                HStack {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.indigo)
            .disabled(isWorking)
            .padding(.bottom, 16)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeIn(duration: 0.3)) { appeared = true } }
    }
}

private struct DoneStep: View {
    let start: () -> Void
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 120, height: 120)
                .foregroundStyle(.white, .indigo)
                .symbolRenderingMode(.palette)
                .scaleEffect(appeared ? 1.0 : 0.6)
                .animation(.spring(response: 0.5, dampingFraction: 0.6), value: appeared)

            Text("You're all set!")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Enjoy your media with Jellyswarrm")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))

            Spacer()

            Button("Start Watching", action: start)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.indigo)
                .padding(.bottom, 16)
        }
        .opacity(appeared ? 1 : 0)
        .onAppear { withAnimation(.easeIn(duration: 0.3)) { appeared = true } }
    }
}
