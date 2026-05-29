// MARK: - SeerrDetailView.swift

// Jellyswarrm — LGPL-2.1-or-later
// Detail view for Seerr movies/TV — shows availability, ratings, and request form

import JellyswarrmCore
import SwiftUI

public struct SeerrDetailView: View {
    var movie: SeerrMovieResult?
    var tv: SeerrTvResult?

    public init(movie: SeerrMovieResult? = nil, tv: SeerrTvResult? = nil) {
        self.movie = movie
        self.tv = tv
    }

    @Environment(DiscoverViewModel.self) private var discoverVM
    @Environment(\.dismiss) private var dismiss

    @State private var showRequestForm = false
    @State private var movieRecs: [SeerrMovieResult] = []
    @State private var tvRecs: [SeerrTvResult] = []
    @State private var isLoadingRecs = true
    @State private var selectedRec: RecTarget?

    private enum RecTarget: Identifiable, Hashable {
        case movie(SeerrMovieResult)
        case tv(SeerrTvResult)
        var id: String {
            switch self {
            case let .movie(m): return "m\(m.id)"
            case let .tv(t): return "t\(t.id)"
            }
        }

        static func == (lhs: RecTarget, rhs: RecTarget) -> Bool {
            lhs.id == rhs.id
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(id)
        }
    }

    private var title: String { movie?.title ?? tv?.name ?? "" }

    private var overview: String? { movie?.overview ?? tv?.overview }

    private var posterURL: URL? { movie?.fullPosterURL ?? tv?.fullPosterURL }

    private var backdropURL: URL? { movie?.fullBackdropURL ?? tv?.fullBackdropURL }

    private var year: String? { movie?.releaseYear ?? tv?.releaseYear }

    private var rating: Double? { movie?.voteAverage ?? tv?.voteAverage }

    private var mediaInfo: SeerrMediaInfo? { movie?.mediaInfo ?? tv?.mediaInfo }

    private var mediaId: Int { movie?.id ?? tv?.id ?? 0 }

    private var isTV: Bool { tv != nil }

    public var body: some View {
        #if os(tvOS)
            // On tvOS this view is pushed inside the parent's NavigationStack,
            // so we omit the wrapping stack to avoid nesting.
            detailContent
        #else
            NavigationStack {
                detailContent
            }
        #endif
    }

    @ViewBuilder
    private var detailContent: some View {
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
                    .frame(height: backdropHeight)
                    .clipped()

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.8)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: backdropHeight)

                    Text(title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding()
                        .shadow(radius: 6)
                }

                VStack(alignment: .leading, spacing: 24) {
                    // Metadata row
                    HStack(spacing: 10) {
                        if let year { badge(year, icon: "calendar") }
                        if let rating { badge(String(format: "%.1f ★", rating), icon: nil).foregroundStyle(.yellow)
                        }
                        if let status = mediaInfo?.status {
                            availabilityBadge(status)
                        }
                    }
                    .font(.caption)

                    // Overview
                    if let ov = overview {
                        ExpandableText(ov, font: .callout)
                    }

                    // Request / Status section
                    requestSection

                    recommendationsSection
                }
                .padding(contentPadding)
            }
        }
        .ignoresSafeArea(edges: .top)
        #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showRequestForm) {
                RequestFormView(
                    mediaId: mediaId,
                    title: title,
                    isTV: isTV,
                    posterURL: posterURL
                )
                .environment(discoverVM)
            }
            .sheet(item: $selectedRec) { target in
                switch target {
                case let .movie(m): SeerrDetailView(movie: m).environment(discoverVM)
                case let .tv(t): SeerrDetailView(tv: t).environment(discoverVM)
                }
            }
        #else
            .navigationDestination(isPresented: $showRequestForm) {
                RequestFormView(
                    mediaId: mediaId,
                    title: title,
                    isTV: isTV,
                    posterURL: posterURL
                )
                .environment(discoverVM)
            }
            .navigationDestination(item: $selectedRec) { target in
                switch target {
                case let .movie(m): SeerrDetailView(movie: m).environment(discoverVM)
                case let .tv(t): SeerrDetailView(tv: t).environment(discoverVM)
                }
            }
        #endif
            .task(id: mediaId) {
                isLoadingRecs = true
                if isTV {
                    tvRecs = await discoverVM.fetchTVRecommendations(tvId: mediaId)
                } else {
                    movieRecs = await discoverVM.fetchMovieRecommendations(movieId: mediaId)
                }
                isLoadingRecs = false
            }
    }

    private var contentPadding: CGFloat {
        #if os(tvOS)
            return 48
        #else
            return 16
        #endif
    }

    private var backdropHeight: CGFloat {
        #if os(tvOS)
            return 480
        #else
            return 260
        #endif
    }

    // MARK: - Recommendations Section

    @ViewBuilder
    private var recommendationsSection: some View {
        if isLoadingRecs {
            Divider()
            Text("More like this")
                .font(.headline)
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        } else if isTV, !tvRecs.isEmpty {
            Divider()
            Text("More like this")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(tvRecs) { show in
                        SeerrMediaCardView(
                            title: show.name,
                            year: show.releaseYear,
                            posterURL: show.fullPosterURL,
                            status: show.availabilityStatus,
                            cardWidth: 120
                        )
                        .onTapGesture { selectedRec = .tv(show) }
                    }
                }
            }
        } else if !isTV, !movieRecs.isEmpty {
            Divider()
            Text("More like this")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(movieRecs) { movie in
                        SeerrMediaCardView(
                            title: movie.title,
                            year: movie.releaseYear,
                            posterURL: movie.fullPosterURL,
                            status: movie.availabilityStatus,
                            cardWidth: 120
                        )
                        .onTapGesture { selectedRec = .movie(movie) }
                    }
                }
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

public struct RequestFormView: View {
    let mediaId: Int
    let title: String
    let isTV: Bool
    let posterURL: URL?

    public init(mediaId: Int, title: String, isTV: Bool, posterURL: URL?) {
        self.mediaId = mediaId
        self.title = title
        self.isTV = isTV
        self.posterURL = posterURL
    }

    @Environment(DiscoverViewModel.self) private var discoverVM
    @Environment(\.dismiss) private var dismiss

    @State private var selectedSeasons: Set<Int> = []
    @State private var requestAllSeasons = true
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    // Quality options state
    @State private var isLoadingOptions = false
    @State private var serviceServerId: Int?
    @State private var profiles: [SeerrServiceProfile] = []
    @State private var rootFolders: [SeerrServiceRootFolder] = []
    @State private var selectedProfileId: Int?
    @State private var selectedRootFolder: String?
    @State private var request4k = false

    private let availableSeasons = Array(1 ... 5)

    private var userPermissions: Int? { discoverVM.currentSeerrUser?.permissions }

    private var canRequestAdvanced: Bool {
        SeerrPermission.has(.requestAdvanced, in: userPermissions)
    }

    private var canRequest4k: Bool {
        if SeerrPermission.has(.request4k, in: userPermissions) { return true }
        return isTV
            ? SeerrPermission.has(.request4kTv, in: userPermissions)
            : SeerrPermission.has(.request4kMovie, in: userPermissions)
    }

    private var is4kEnabledOnServer: Bool {
        let settings = discoverVM.publicSettings
        return isTV ? (settings?.series4kEnabled ?? false) : (settings?.movie4kEnabled ?? false)
    }

    private var show4kToggle: Bool { canRequest4k && is4kEnabledOnServer }

    public var body: some View {
        #if os(tvOS)
            // Pushed into the parent's NavigationStack on tvOS — no inner stack.
            requestContent
        #else
            NavigationStack {
                requestContent
            }
        #endif
    }

    @ViewBuilder
    private var requestContent: some View {
        ScrollView {
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

                    if isLoadingOptions {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Loading quality options…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    qualityOptionsSection

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

                                LazyVGrid(columns: [GridItem(.adaptive(minimum: seasonPillMinWidth))], spacing: 10) {
                                    ForEach(availableSeasons, id: \.self) { season in
                                        seasonPill(season: season)
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
            }
            .navigationTitle("Request")
            #if !os(tvOS) && !os(macOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
            #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            #endif
            .task { await loadQualityOptions() }
    }

    private var seasonPillMinWidth: CGFloat {
        #if os(tvOS)
            return 140
        #else
            return 70
        #endif
    }

    @ViewBuilder
    private func seasonPill(season: Int) -> some View {
        let isSelected = selectedSeasons.contains(season)
        Button {
            if isSelected {
                selectedSeasons.remove(season)
            } else {
                selectedSeasons.insert(season)
            }
        } label: {
            Text("Season \(season)")
                .font(.callout)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var qualityOptionsSection: some View {
        if canRequestAdvanced, !profiles.isEmpty || !rootFolders.isEmpty || show4kToggle {
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Quality Options")
                    .font(.headline)

                if !profiles.isEmpty {
                    Picker("Quality Profile", selection: $selectedProfileId) {
                        ForEach(profiles) { profile in
                            Text(profile.name ?? "Profile \(profile.id ?? 0)")
                                .tag(profile.id as Int?)
                        }
                    }
                }

                if !rootFolders.isEmpty {
                    Picker("Root Folder", selection: $selectedRootFolder) {
                        ForEach(rootFolders, id: \.path) { folder in
                            Text(folder.path ?? "—")
                                .tag(folder.path as String?)
                        }
                    }
                }

                if show4kToggle {
                    Toggle("Request in 4K", isOn: $request4k)
                }
            }
            .padding(.horizontal)
        } else if show4kToggle {
            // 4K-only users still get the toggle even without advanced perms
            Divider()
            Toggle("Request in 4K", isOn: $request4k)
                .padding(.horizontal)
        }
    }

    private func loadQualityOptions() async {
        guard canRequestAdvanced else { return }
        isLoadingOptions = true
        defer { isLoadingOptions = false }

        let servers = isTV
            ? await discoverVM.fetchSonarrServers()
            : await discoverVM.fetchRadarrServers()

        // Prefer the default non-4K server; fall back to first available
        let defaultServer = servers.first(where: { ($0.isDefault ?? false) && !($0.is4k ?? false) })
            ?? servers.first(where: { $0.isDefault ?? false })
            ?? servers.first

        guard let chosen = defaultServer, let id = chosen.id else { return }
        serviceServerId = id

        let detail = isTV
            ? await discoverVM.fetchSonarrProfiles(serverId: id)
            : await discoverVM.fetchRadarrProfiles(serverId: id)

        profiles = detail?.profiles ?? []
        rootFolders = detail?.rootFolders ?? []
        selectedProfileId = profiles.first?.id
        selectedRootFolder = rootFolders.first?.path
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil
        do {
            let profileId = canRequestAdvanced ? selectedProfileId : nil
            let rootFolder = canRequestAdvanced ? selectedRootFolder : nil
            let serverId = canRequestAdvanced ? serviceServerId : nil
            let is4k = show4kToggle && request4k
            if isTV {
                let seasons = requestAllSeasons ? nil : Array(selectedSeasons).sorted()
                try await discoverVM.requestTV(
                    tvId: mediaId,
                    seasons: seasons,
                    is4k: is4k,
                    serverId: serverId,
                    profileId: profileId,
                    rootFolder: rootFolder
                )
            } else {
                try await discoverVM.requestMovie(
                    movieId: mediaId,
                    is4k: is4k,
                    serverId: serverId,
                    profileId: profileId,
                    rootFolder: rootFolder
                )
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
