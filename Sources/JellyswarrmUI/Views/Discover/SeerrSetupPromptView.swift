// MARK: - SeerrSetupPromptView.swift

// Jellyswarrm — LGPL-2.1-or-later
//
// Friendly placeholder shown in the Discover tab when no Seerr URL is
// configured (plugin not installed AND no manual entry yet). Offers a
// path to the standard SeerrSetupView for manual entry.

import JellyswarrmCore
import SwiftUI

public struct SeerrSetupPromptView: View {
    private let onConfigured: () -> Void
    @State private var showManualEntry = false

    public init(onConfigured: @escaping () -> Void = {}) {
        self.onConfigured = onConfigured
    }

    public var body: some View {
        VStack(spacing: 40) {
            Image(systemName: "sparkles.tv")
                .font(.system(size: 80))
                .foregroundStyle(.white.opacity(0.6))

            Text("Discover & Request")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)

            Text("Connect to Overseerr or Jellyseerr to browse trending content and request new movies & shows.")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 700)

            VStack(spacing: 20) {
                Text("To auto-configure, ask your server admin to install the Jellyswarrm plugin.")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)

                Button {
                    showManualEntry = true
                } label: {
                    Text("Enter URL Manually")
                        .padding(.horizontal, 32)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.15))
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppleTVTheme.background.ignoresSafeArea())
        .sheet(isPresented: $showManualEntry, onDismiss: onConfigured) {
            SeerrSetupView()
        }
    }
}
