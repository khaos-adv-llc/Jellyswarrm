// MARK: - MediaDetailView.swift

// Jellyswarrm — GPL v3 with App Store exception

import JellyswarrmCore
import SwiftUI

struct MediaDetailView: View {
    let item: MediaItem
    @Environment(LibraryViewModel.self) private var libraryVM
    @Environment(AppState.self) private var appState

    @State private var detail: MediaItem?
    @State private var isLoading = true
    @State private var showPlayer = false

    var displayItem: MediaItem { detail ?? item }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                // Backdrop
                backdropSection

                // Main content
                VStack(alignment: .leading, spacing: 20) {
                    metadataSection
                    actionButtons
                    if let overview = displayItem.overview, !overview.isEmpty {
                        overviewSection(overview)
                    }
                    if let people = displayItem.people, !people.isEmpty {
                        castSection(people)
                    }
                }
                .padding()
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            detail = try? await libraryVM.getDetail(for: item.id)
            isLoading = false
        }
        .fullScreenCover(isPresented: $showPlayer) {
            VideoPlayerView(item: displayItem)
        }
    }

    // MARK: - Backdrop

    private var backdropSection: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: libraryVM.imageURL(for: displayItem, type: .backdrop, maxWidth: 1280)) { phase in
                switch phase {
                case let .success(image):
                    image.resizable()
                        .aspectRatio(16 / 9, contentMode: .fill)
                default:
                    Rectangle().fill(Color.gray.opacity(0.2))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 280)
            .clipped()

            LinearGradient(
                colors: [.clear, .black.opacity(0.7)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 280)

            Text(displayItem.name)
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding()
                .shadow(radius: 6)
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        HStack(spacing: 12) {
            if let year = displayItem.productionYear {
                metaBadge("\(year)", icon: "calendar")
            }
            if let rating = displayItem.officialRating {
                metaBadge(rating, icon: "checkmark.seal")
            }
            if let runtime = displayItem.runtimeTicks {
                metaBadge(runtime.ticksToDurationString, icon: "clock")
            }
            if let community = displayItem.communityRating {
                metaBadge(String(format: "%.1f", community), icon: "star.fill")
                    .foregroundStyle(.yellow)
            }
        }
        .font(.caption)
    }

    private func metaBadge(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.caption2)
            Text(text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.15))
        .clipShape(Capsule())
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if displayItem.type.isPlayable {
                Button {
                    showPlayer = true
                } label: {
                    HStack {
                        Image(systemName: item.userData?.hasProgress == true ? "play.circle" : "play.fill")
                        Text(item.userData?.hasProgress == true ? "Resume" : "Play")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }

            Button {
                // Favorite toggle — implement with libraryVM.toggleFavorite
            } label: {
                Image(systemName: displayItem.userData?.isFavorite == true ? "heart.fill" : "heart")
                    .font(.title2)
                    .frame(width: 50, height: 50)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Overview

    private func overviewSection(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overview")
                .font(.headline)
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Cast

    private func castSection(_ people: [PersonInfo]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cast & Crew")
                .font(.headline)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(people.prefix(10)) { person in
                        VStack(spacing: 6) {
                            Circle()
                                .fill(Color.gray.opacity(0.2))
                                .frame(width: 60, height: 60)
                                .overlay {
                                    if let server = appState.currentServer,
                                       let tag = person.primaryImageTag
                                    {
                                        AsyncImage(url: JellyfinAPIClient.shared.imageURL(
                                            server: server,
                                            itemId: person.id,
                                            imageType: .primary,
                                            tag: tag,
                                            maxWidth: 120
                                        )) { phase in
                                            if case let .success(image) = phase {
                                                image.resizable().aspectRatio(contentMode: .fill)
                                            } else {
                                                Image(systemName: "person.fill")
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                }

                            Text(person.name)
                                .font(.caption2)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 70)

                            if let role = person.role {
                                Text(role)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 70)
                            }
                        }
                    }
                }
            }
        }
    }
}
