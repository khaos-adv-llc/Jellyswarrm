// MARK: - TVProfilePickerView.swift

// Jellyswarrm — LGPL-2.1-or-later
//
// Cinematic profile picker shown when multiple Jellyfin profiles are stored
// on this Apple TV. Style mirrors the Apple TV app user picker — dark
// backdrop, circular avatars, focus-driven scaling and glow.

#if os(tvOS)
import JellyswarrmCore
import SwiftUI

public struct TVProfilePickerView: View {
    @State private var profileManager: ProfileManager
    private let onSelect: (JellyfinProfile) -> Void
    private let onAddNew: () -> Void

    @FocusState private var focusedId: String?

    public init(
        profileManager: ProfileManager = .shared,
        onSelect: @escaping (JellyfinProfile) -> Void,
        onAddNew: @escaping () -> Void
    ) {
        _profileManager = State(initialValue: profileManager)
        self.onSelect = onSelect
        self.onAddNew = onAddNew
    }

    public var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(white: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 60) {
                VStack(spacing: 16) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.white)
                    Text("Jellyswarrm")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.white)
                    Text("Who's watching?")
                        .font(.system(size: 32))
                        .foregroundStyle(.white.opacity(0.7))
                }

                HStack(spacing: 48) {
                    ForEach(profileManager.profiles) { profile in
                        ProfileAvatarButton(profile: profile) {
                            onSelect(profile)
                        }
                        .focused($focusedId, equals: profile.id)
                    }

                    AddProfileButton(action: onAddNew)
                        .focused($focusedId, equals: "add_new")
                }
                .focusSection()
            }
        }
        .onAppear {
            focusedId = profileManager.profiles.first?.id ?? "add_new"
        }
    }
}

private struct ProfileAvatarButton: View {
    let profile: JellyfinProfile
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                avatar
                    .frame(width: 140, height: 140)
                    .clipShape(Circle())
                    .overlay(
                        Circle().stroke(isFocused ? Color.white : Color.clear, lineWidth: 4)
                    )
                    .scaleEffect(isFocused ? 1.12 : 1.0)
                    .shadow(color: isFocused ? .white.opacity(0.4) : .clear, radius: 20)
                    .animation(.easeInOut(duration: 0.15), value: isFocused)

                Text(profile.username)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(isFocused ? .white : .white.opacity(0.75))

                Text(profile.serverName)
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .focusEffectDisabled()
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = profile.avatarURL, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().aspectRatio(contentMode: .fill)
                default:
                    initialsAvatar
                }
            }
        } else {
            initialsAvatar
        }
    }

    private var initialsAvatar: some View {
        ZStack {
            Circle().fill(Color.white.opacity(0.15))
            Text(String(profile.username.prefix(1)).uppercased())
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

private struct AddProfileButton: View {
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(isFocused ? Color.white.opacity(0.2) : Color.white.opacity(0.08))
                        .frame(width: 140, height: 140)
                        .overlay(
                            Circle().stroke(
                                isFocused ? Color.white : Color.white.opacity(0.3),
                                lineWidth: 2
                            )
                        )
                    Image(systemName: "plus")
                        .font(.system(size: 44, weight: .medium))
                        .foregroundStyle(.white)
                }
                .scaleEffect(isFocused ? 1.12 : 1.0)
                .animation(.easeInOut(duration: 0.15), value: isFocused)

                Text("Add Profile")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(isFocused ? .white : .white.opacity(0.75))
            }
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .focusEffectDisabled()
    }
}
#endif
