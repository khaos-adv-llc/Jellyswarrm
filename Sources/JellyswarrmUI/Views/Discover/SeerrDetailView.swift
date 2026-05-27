// MARK: - SeerrDetailView.swift

// Jellyswarrm — GPL v3 with App Store exception
// Detail view for Seerr movies/TV — shows availability, ratings, and request form

import JellyswarrmCore
import SwiftUI

struct SeerrDetailView: View {
    @Environment(DiscoverViewModel.self) private var discoverVM
    @Environment(\.dismiss) private var dismiss

    // One of these is provided
    var movie: SeerrMovieResult?
    var tv: SeerrTvResult?

    @State private var showRequestForm = false

    private var title: String { movie?.title ?? tv?.name ?? "" }

    private var overview: String? { movie?.overview ?? tv?.overview }

    private var posterURL: URL? { movie?.fullPosterURL ?? tv?.fullPosterURL }

    private var backdropURL: URL? { movie?.fullBackdropURL ?? tv?.fullBackdropURL }

    private var year: String? { movie?.releaseYear ?? tv?.releaseYear }

    private var rating: Double? { movie?.voteAverage ?? tv?.voteAverage }

    private var mediaInfo: SeerrMediaInfo? { movie?.mediaInfo ?? tv?.mediaInfo }

    private var mediaId: Int { movie?.id ?? tv?.id ?? 0 }

    private var isTV: Bool { tv != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Backdrop
                    ZStack(alignment: .bottomLeading) {
                        AsyncImage(url: backdropURL ?? posterURL) { phase in
                            if case let .success(image) = phase {
                                image.resizable()
                                    .aspectRatio(16 / 9, contentMode: .fill)
                            } else {
                                Rectangle().fill(Color.gray.opacity(0.2))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                        .clipped()

                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 260)

                        Text(title)
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding()
                            .shadow(radius: 6)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        // Metadata row
                        HStack(spacing: 10) {
                            if let year { badge(year, icon: "calendar") }
                            if let rating { badge(String(format: "%.1f ★", rating), icon: nil).foregroundStyle(.yellow)
                            }
                            if let info = mediaInfo {
                                availabilityBadge(info.status)
                            }
                        }
                        .font(.caption)

                        // Overview
                        if let ov = overview {
                            Text(ov)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }

                        // Request / Status section
                        requestSection

                        Divider()

                        // Recommendations (placeholder for future loading)
                        Text("More like this")
                            .font(.headline)

                        Text("Recommendations load here once detail is fetched.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
            .ignoresSafeArea(edges: .top)
            #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            #endif
                .sheet(isPresented: $showRequestForm) {
                    RequestFormView(
                        mediaId: mediaId,
                        title: title,
                        isTV: isTV,
                        posterURL: posterURL
                    )
                    .environment(discoverVM)
                }
        }
    }

    // MARK: - Request Section

    @ViewBuilder
    private var requestSection: some View {
        let state = discoverVM.buttonState(for: mediaInfo, mediaId: mediaId)
        switch state {
        case .onServer:
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Available on your server")
                    .fontWeight(.medium)
                    .foregroundStyle(.green)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.green.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        case .pending:
            HStack {
                Image(systemName: "clock.fill").foregroundStyle(.yellow)
                Text("Request pending approval")
                    .fontWeight(.medium)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        case .requested:
            HStack {
                Image(systemName: "paperplane.fill").foregroundStyle(.blue)
                Text("Request submitted!")
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.blue.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        case .requesting:
            HStack {
                ProgressView().controlSize(.small)
                Text("Submitting request...")
                    .fontWeight(.medium)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))

        case .available:
            Button {
                showRequestForm = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(isTV ? "Request TV Show" : "Request Movie")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func badge(_ text: String, icon: String?) -> some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.caption2) }
            Text(text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.15))
        .clipShape(Capsule())
    }

    private func availabilityBadge(_ status: SeerrMediaStatus) -> some View {
        Text(status.displayName)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(status.isOnServer ? Color.green.opacity(0.2) : Color.gray.opacity(0.15))
            .foregroundStyle(status.isOnServer ? .green : .secondary)
            .clipShape(Capsule())
    }
}

// MARK: - Request Form

struct RequestFormView: View {
    let mediaId: Int
    let title: String
    let isTV: Bool
    let posterURL: URL?

    @Environment(DiscoverViewModel.self) private var discoverVM
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSeasons: Set<Int> = []
    @State private var requestAllSeasons = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    // For TV: mock seasons 1-5 (real app would fetch from SeerrAPIClient)
    private let availableSeasons = Array(1 ... 5)

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Poster + title
                HStack(spacing: 16) {
                    AsyncImage(url: posterURL) { phase in
                        if case let .success(img) = phase {
                            img.resizable()
                                .aspectRatio(2 / 3, contentMode: .fill)
                                .frame(width: 80, height: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.title3)
                            .fontWeight(.bold)
                        Text(isTV ? "TV Series Request" : "Movie Request")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding()

                if isTV {
                    Divider()

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Request all seasons", isOn: $requestAllSeasons)
                            .padding(.horizontal)

                        if !requestAllSeasons {
                            Text("Select seasons to request:")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 10) {
                                ForEach(availableSeasons, id: \.self) { season in
                                    Toggle("S\(season)", isOn: Binding(
                                        get: { selectedSeasons.contains(season) },
                                        set: { checked in
                                            if checked { selectedSeasons.insert(season) }
                                            else { selectedSeasons.remove(season) }
                                        }
                                    ))
                                    .toggleStyle(.button)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }

                if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                        .padding(.horizontal)
                }

                Spacer()

                // Submit button
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Submitting...")
                        } else {
                            Image(systemName: "paperplane.fill")
                            Text("Submit Request")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
                .padding()
            }
            .navigationTitle("Request")
            #if !os(tvOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            #endif
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            if isTV {
                let seasons = requestAllSeasons ? nil : Array(selectedSeasons).sorted()
                try await discoverVM.requestTV(tvId: mediaId, seasons: seasons)
            } else {
                try await discoverVM.requestMovie(movieId: mediaId)
            }
            dismiss()
        } catch let e as NetworkError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}
