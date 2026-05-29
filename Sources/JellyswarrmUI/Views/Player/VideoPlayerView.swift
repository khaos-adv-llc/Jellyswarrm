// MARK: - VideoPlayerView.swift

// Jellyswarrm — GPL v3 with App Store exception

import AVKit
import JellyswarrmCore
import SwiftUI

public struct VideoPlayerView: View {
    let item: MediaItem
    let startFromBeginning: Bool
    /// When set, used in place of `@Environment(\.dismiss)`. macOS hosts the
    /// player inside a dedicated NSWindow where the SwiftUI dismiss environment
    /// is a no-op, so the window controller passes a closure that closes the
    /// window directly.
    let onClose: (() -> Void)?
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // Optional + lazy-initialized in .onAppear so we never construct a dummy
    // PlayerViewModel against a throwaway AppState. On iOS, AVPlayerViewController
    // is no longer presented from this view — PlayerPresenter handles UIKit
    // presentation directly from MediaDetailView, eliminating the previous
    // SwiftUI fullScreenCover + UIKit double-modal layering.
    @State private var playerVM: PlayerViewModel?
    @State private var player: AVPlayer?
    @State private var timeObserverToken: Any?
    @State private var controlsVisible: Bool = false
    @State private var useVLC: Bool = false
    @State private var vlcURL: URL?
    #if os(macOS)
    @State private var showControls: Bool = false
    @State private var hideTask: Task<Void, Never>? = nil
    #endif

    public init(item: MediaItem, startFromBeginning: Bool = false, onClose: (() -> Void)? = nil) {
        self.item = item
        self.startFromBeginning = startFromBeginning
        self.onClose = onClose
    }

    private func performDismiss() {
        if let onClose { onClose() } else { dismiss() }
    }

    #if os(macOS)
    @MainActor
    private func scheduleHide() {
        hideTask?.cancel()
        showControls = true
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            showControls = false
        }
    }
    #endif

    public var body: some View {
        bodyContent
            .onAppear {
                // Bind the VM to the real AppState exactly once, synchronously,
                // before .task runs. onAppear fires once per view identity and
                // finishes before .task begins, so playerVM is non-nil by the
                // time .task reads it.
                if playerVM == nil {
                    playerVM = PlayerViewModel(appState: appState)
                }
            }
            .task(id: item.id) { await loadAndStart() }
            .onDisappear { handleDisappear() }
    }

    @ViewBuilder
    private var bodyContent: some View {
        if useVLC, let url = vlcURL {
            vlcBody(url: url)
        } else {
            avFoundationBody
        }
    }

    @ViewBuilder
    private func vlcBody(url: URL) -> some View {
        let resume = Float(playerVM?.progressFraction ?? 0)
        #if canImport(VLCKit) && os(macOS)
        VLCPlayerViewMac(url: url, startPosition: resume, onStopped: {
            Task { @MainActor in
                await playerVM?.stop()
                performDismiss()
            }
        })
        .ignoresSafeArea()
        #elseif canImport(MobileVLCKit) && !os(macOS) && !os(tvOS)
        VLCPlayerView(url: url, startPosition: resume, onStopped: {
            Task { @MainActor in
                await playerVM?.stop()
                performDismiss()
            }
        })
        .ignoresSafeArea()
        #else
        // VLC requested but package not present (or tvOS — VLC has no tvOS build).
        // Show a clear message rather than silently falling back, so the user
        // knows their preference couldn't be honored.
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.yellow)
                Text("VLC Engine Unavailable")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("VLC playback is not built into this binary on this platform. Switch to AVFoundation in Settings → Playback.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                Button("Close") { performDismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        #endif
    }

    @ViewBuilder
    private var avFoundationBody: some View {
        #if os(iOS)
        // iOS no longer presents AVPlayerViewController via VideoPlayerView —
        // PlayerPresenter handles UIKit presentation directly from
        // MediaDetailView. This view is only constructed on iOS now for the
        // VLC path (hosted inside a UIHostingController by PlayerPresenter).
        Color.black.ignoresSafeArea()
        #elseif os(tvOS)
        // tvOS: AVPlayerViewController must be the top-level view returned
        // from .fullScreenCover so UIKit gives it full-screen size and
        // routes focus / Siri Remote gestures correctly. Embedding it
        // inside a ZStack (alongside Color.black, a Metal MTKView, etc.)
        // collapses its container to zero width and blocks the focus
        // engine. The HDR switch is bypassed on tvOS — VideoToolbox
        // tonemaps HDR10/HLG/DV natively on Apple TV hardware, so the
        // Metal renderer is neither needed nor wanted here.
        if let player, let vm = playerVM {
            TVPlayerRepresentable(
                player: player,
                resumeTicks: vm.positionTicks,
                onReady: {
                    Task { @MainActor in await vm.notifyPlaybackStarted() }
                },
                onDismiss: { performDismiss() }
            )
            .ignoresSafeArea()
        } else if let error = playerVM?.error {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text("Playback Error")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(error.errorDescription ?? "Unknown error")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Button("Close") { performDismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        } else {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        #else
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                #if os(macOS)
                ZStack(alignment: .topLeading) {
                    // Route HDR10 / HLG through the Metal renderer so we get
                    // proper PQ / HLG tonemapping against the display's EDR
                    // headroom. Dolby Vision and SDR stay on AVPlayerView —
                    // VideoToolbox tonemaps DV natively.
                    if let vm = playerVM, vm.hdrFormat == .hdr10 || vm.hdrFormat == .hlg {
                        HDRPlayerView(player: player, hdrFormat: vm.hdrFormat)
                            .ignoresSafeArea()
                    } else {
                        SystemPlayerView(
                            player: player,
                            onDismiss: { performDismiss() },
                            onControlsVisibilityChange: { visible in controlsVisible = visible }
                        )
                        .ignoresSafeArea()
                    }

                    MouseTrackingView(onMouseMoved: { scheduleHide() })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)

                    // Button stays in the hierarchy so .keyboardShortcut(.escape)
                    // keeps firing while the chrome is faded out.
                    Button(action: { performDismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(.white.opacity(0.85))
                            .shadow(radius: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(20)
                    .keyboardShortcut(.escape, modifiers: [])
                    .opacity(showControls ? 1 : 0)
                    .animation(.easeInOut(duration: 0.25), value: showControls)
                }
                #endif
            } else if playerVM?.isLoading == true {
                VStack(spacing: 16) {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(1.5)
                    Text("Loading...")
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else if let error = playerVM?.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.yellow)
                    Text("Playback Error")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(error.errorDescription ?? "Unknown error")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                    Button("Close") { performDismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        #endif
    }

    private func loadAndStart() async {
        guard let vm = playerVM else { return }
        await vm.loadPlayback(for: item, startFromBeginning: startFromBeginning)
        guard let url = vm.playbackURL else {
            print("[Player] ERROR: no playbackURL after loadPlayback")
            return
        }

        let asset = AVURLAsset(url: url, options: [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
        ])

        // Detect HDR transfer function before constructing the player item
        // so the view layer can decide between the AVFoundation path and the
        // Metal HDR renderer on non-iOS platforms. Also resolves
        // `vm.resolvedEngine` from the user's playback engine preference.
        await vm.detectHDR(asset: asset)

        // VLC engine: skip AVFoundation entirely. tvOS has no VLC build, so
        // fall back to AVFoundation there even if the resolver picked VLC.
        #if !os(tvOS)
        if vm.resolvedEngine == .vlc {
            vlcURL = url
            useVLC = true
            await vm.notifyPlaybackStarted()
            vm.isPlaying = true
            return
        }
        #endif

        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 10
        vm.configurePlayerItem(playerItem)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.automaticallyWaitsToMinimizeStalling = false

        // Observe AVPlayerItem status for diagnostics
        let statusObservation = playerItem.observe(\.status, options: [.new]) { item, _ in
            switch item.status {
            case .failed:
                let err = item.error
                print("[Player] AVPlayerItem FAILED: \(err?.localizedDescription ?? "unknown")")
                if let err = err as? NSError {
                    print("[Player] AVPlayerItem error domain=\(err.domain) code=\(err.code) userInfo=\(err.userInfo)")
                }
            case .readyToPlay:
                print("[Player] AVPlayerItem readyToPlay ✓")
            case .unknown:
                print("[Player] AVPlayerItem status unknown — waiting for asset load")
            @unknown default:
                break
            }
        }

        // Also observe timeControlStatus for the prohibited-icon diagnosis
        let tcObservation = avPlayer.observe(\.timeControlStatus, options: [.new]) { p, _ in
            switch p.timeControlStatus {
            case .playing:
                print("[Player] AVPlayer playing ✓")
            case .paused:
                print("[Player] AVPlayer paused (reason: \(String(describing: p.reasonForWaitingToPlay)))")
            case .waitingToPlayAtSpecifiedRate:
                print("[Player] AVPlayer waiting: \(String(describing: p.reasonForWaitingToPlay))")
            @unknown default:
                break
            }
        }

        // On iOS, AVPlayerViewController is presented by PlayerPresenter
        // directly from MediaDetailView — VideoPlayerView's iOS body is a
        // no-op black background. The AVFoundation setup below is for macOS
        // (and tvOS via the tvOS-specific avFoundationBody branch).
        _ = statusObservation
        _ = tcObservation
        #if os(tvOS)
        // On tvOS the seek + play are deferred to TVPlayerRepresentable's
        // coordinator, which observes AVPlayerViewController.isReadyForDisplay
        // — same pattern as iOS. Seeking before the layer is attached causes
        // AVPlayerViewController to reset to 0 once it mounts, and play()
        // before isReadyForDisplay can leave the view stuck on the loading
        // shimmer. Assigning `player` here is what triggers the view body to
        // render TVPlayerRepresentable; the coordinator takes over from there.
        player = avPlayer
        #else
        player = avPlayer
        // Seek-based resume for both direct-stream and HLS transcode.
        // Passing StartTimeTicks to Jellyfin breaks AVFoundation playback
        // (first .ts segment lacks a keyframe at PTS 0); transcoding from
        // the start and seeking client-side avoids the issue.
        let shouldSeek = vm.positionTicks > 0
        if shouldSeek {
            let resumeTicks = vm.positionTicks
            print("[Player] Seeking to resume position: \(resumeTicks) ticks")
            await avPlayer.seek(
                to: CMTime(value: resumeTicks, timescale: 10_000_000),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        print("[Resume] Starting from: \(vm.positionTicks) ticks (seek=\(shouldSeek))")
        avPlayer.play()
        await vm.notifyPlaybackStarted()
        #endif

        // Track position every 10s. AVPlayer is already seeked to the
        // resume point, so currentTime IS the true content position.
        // The token is stored so onDisappear can remove the observer — an
        // unremoved observer strongly retains its closure (which captures
        // vm), keeping the PlayerViewModel and its progress-reporting Task
        // alive past view teardown.
        let itemId = item.id
        let interval = CMTime(seconds: 10, preferredTimescale: 600)
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak avPlayer, weak vm] time in
            guard let player = avPlayer,
                  let vm,
                  player.timeControlStatus == .playing else { return }
            let seconds = time.seconds
            guard seconds.isFinite, seconds > 0 else { return }
            let ticks = Int64(seconds * 10_000_000)
            // addPeriodicTimeObserver's closure is @Sendable under Swift 6;
            // hop to the main actor to mutate the @MainActor PlayerViewModel.
            Task { @MainActor [weak vm] in
                vm?.positionTicks = ticks
            }
            let defaults = UserDefaults.standard
            let key = "resume_\(itemId)"
            let duration = player.currentItem?.duration.seconds
            if let duration, duration.isFinite, duration > 0, seconds > duration - 60 {
                defaults.removeObject(forKey: key)
            } else {
                defaults.set(Double(ticks), forKey: key)
            }
        }
        vm.isPlaying = true
        if let chapters = vm.currentItem?.chapters, !chapters.isEmpty {
            vm.startChapterObserver(on: avPlayer, chapters: chapters)
        }
    }

    private func handleDisappear() {
        playerVM?.stopChapterObserver()
        #if os(macOS)
        hideTask?.cancel()
        hideTask = nil
        #endif
        #if !os(iOS)
        // iOS teardown is handled either by DismissAwareAVPlayerViewController
        // (AVFoundation path, in PlayerPresenter) or by VLC's onStopped
        // callback (VLC path, in vlcBody). SwiftUI fires this onDisappear
        // spuriously on iOS 26 beta when the parent MediaDetailView
        // re-renders, which would otherwise kill the active player.
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        guard let vm = playerVM else { return }
        let outgoingPlayer = player
        outgoingPlayer?.pause()
        outgoingPlayer?.replaceCurrentItem(with: nil)
        player = nil
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000)
            await vm.stop()
        }
        #endif
    }

}

// MARK: - System AVPlayerViewController (tvOS, macOS)
// Using AVPlayerViewController on tvOS/macOS ensures:
// - Correct HDR / Dolby Vision tone-mapping via VideoToolbox
// - Native transport bar with working dismiss / done button
// - Picture-in-Picture and AirPlay support

#if os(macOS)
    import AppKit

    // Transparent NSView overlay that fires onMouseMoved on every mouse motion
    // (and on mouse-enter) within its bounds. SwiftUI's .onHover only fires on
    // boundary crossings, which is insufficient for "show controls while the
    // user is moving the mouse, hide after 3s of stillness" behavior.
    struct MouseTrackingView: NSViewRepresentable {
        var onMouseMoved: () -> Void

        func makeNSView(context _: Context) -> NSView {
            let view = TrackingNSView()
            view.onMouseMoved = onMouseMoved
            return view
        }

        func updateNSView(_ nsView: NSView, context _: Context) {
            (nsView as? TrackingNSView)?.onMouseMoved = onMouseMoved
        }

        final class TrackingNSView: NSView {
            var onMouseMoved: (() -> Void)?

            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                trackingAreas.forEach { removeTrackingArea($0) }
                let area = NSTrackingArea(
                    rect: bounds,
                    options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                    owner: self,
                    userInfo: nil
                )
                addTrackingArea(area)
            }

            override func mouseMoved(with _: NSEvent) {
                onMouseMoved?()
            }

            override func mouseEntered(with _: NSEvent) {
                onMouseMoved?()
            }
        }
    }

    // Hosts VideoPlayerView in its own borderless NSWindow and toggles native
    // fullscreen shortly after presenting. Replaces the prior .sheet()
    // presentation, which produced a small floating panel rather than a real
    // fullscreen video experience.
    @MainActor
    public final class PlayerWindowController: NSWindowController, NSWindowDelegate {
        public var onClosed: (() -> Void)?

        public init(item: MediaItem, startFromBeginning: Bool, appState: AppState) {
            let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
            let window = NSWindow(
                contentRect: screenFrame,
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = item.displayTitle
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            window.collectionBehavior.insert(.fullScreenPrimary)
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false

            super.init(window: window)

            // VideoPlayerView is wrapped so the dismiss callback closes this
            // window rather than going through SwiftUI's dismiss environment
            // (which is a no-op for an NSHostingView).
            let content = VideoPlayerView(
                item: item,
                startFromBeginning: startFromBeginning,
                onClose: { [weak self] in self?.window?.close() }
            )
            .environment(appState)

            let hosting = NSHostingView(rootView: content)
            hosting.translatesAutoresizingMaskIntoConstraints = false
            window.contentView = hosting
            window.delegate = self
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) not supported")
        }

        public func present() {
            showWindow(nil)
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Defer toggleFullScreen so the window is on screen first; calling
            // it synchronously after order-front fails silently on some macOS
            // versions.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.window?.toggleFullScreen(nil)
            }
        }

        public func windowWillClose(_: Notification) {
            onClosed?()
            onClosed = nil
        }
    }

    // macOS has no AVPlayerViewController — use AVPlayerView from AVKit (AppKit).
    struct SystemPlayerView: NSViewRepresentable {
        let player: AVPlayer
        let onDismiss: () -> Void
        var onControlsVisibilityChange: ((Bool) -> Void)? = nil

        func makeNSView(context: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.player = player
            view.controlsStyle = .inline
            view.showsFullScreenToggleButton = true
            view.allowsPictureInPicturePlayback = true
            context.coordinator.observe(player: player)
            return view
        }

        func updateNSView(_ nsView: AVPlayerView, context: Context) {
            if nsView.player !== player {
                nsView.player = player
                context.coordinator.observe(player: player)
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        @MainActor
        final class Coordinator {
            private var statusObservation: NSKeyValueObservation?

            // AVPlayerView does not auto-play once the item becomes ready (unlike
            // iOS's AVPlayerViewController). Observe AVPlayerItem.status and
            // call play() exactly once when it transitions to .readyToPlay.
            func observe(player: AVPlayer) {
                statusObservation = nil
                guard let item = player.currentItem else { return }
                if item.status == .readyToPlay {
                    player.play()
                    return
                }
                statusObservation = item.observe(\.status, options: [.new]) { [weak self, weak player] item, _ in
                    guard item.status == .readyToPlay else { return }
                    Task { @MainActor in
                        player?.play()
                        self?.statusObservation = nil
                    }
                }
            }
        }
    }
#elseif os(tvOS)
    import UIKit

    // Returned directly from VideoPlayerView.body on tvOS so SwiftUI's
    // .fullScreenCover hands AVPlayerViewController the entire screen.
    // Wrapping it in a ZStack alongside Color.black and other siblings
    // collapsed the container to zero width and disabled focus —
    // _UITemporaryLayoutWidth pinned to 0 and the Siri Remote pan gesture
    // recognizer logged "blocking subgraph". Top-level placement restores
    // both. HDR (HDR10, HLG, Dolby Vision) is tonemapped natively by
    // VideoToolbox on Apple TV, so no Metal renderer is needed here.
    struct TVPlayerRepresentable: UIViewControllerRepresentable {
        let player: AVPlayer
        let resumeTicks: Int64
        let onReady: () -> Void
        let onDismiss: () -> Void

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let vc = AVPlayerViewController()
            vc.player = player
            vc.showsPlaybackControls = true
            vc.allowsPictureInPicturePlayback = true
            // entersFullScreenWhenPlaybackBegins / exitsFullScreenWhenPlaybackEnds
            // are iOS/macOS-only — tvOS AVPlayerViewController is always full-screen.
            vc.delegate = context.coordinator
            // Defer seek + play until AVPlayerViewController reports
            // isReadyForDisplay. Seeking before the layer is attached makes
            // AVPlayerViewController snap back to 0 once it mounts, and
            // calling play() before readyForDisplay can leave the view stuck
            // on a black/loading screen on tvOS.
            context.coordinator.attach(
                playerVC: vc,
                player: player,
                resumeTicks: resumeTicks,
                onReady: onReady
            )
            return vc
        }

        func updateUIViewController(_ uiViewController: AVPlayerViewController, context _: Context) {
            if uiViewController.player !== player {
                uiViewController.player = player
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(onDismiss: onDismiss)
        }

        final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
            let onDismiss: () -> Void
            private var readyObservation: NSKeyValueObservation?

            init(onDismiss: @escaping () -> Void) {
                self.onDismiss = onDismiss
            }

            func attach(
                playerVC: AVPlayerViewController,
                player: AVPlayer,
                resumeTicks: Int64,
                onReady: @escaping () -> Void
            ) {
                let resumeSeconds = Double(resumeTicks) / 10_000_000.0
                let observation = playerVC.observe(\.isReadyForDisplay, options: [.new, .initial]) { [weak self, weak player] _, change in
                    guard change.newValue == true, let player = player else { return }
                    print("[Player] tvOS AVPlayerViewController readyForDisplay ✓")
                    self?.readyObservation = nil
                    if resumeTicks > 0, resumeSeconds > 5.0 {
                        let resumeTime = CMTime(value: resumeTicks, timescale: 10_000_000)
                        print("[Player] tvOS seeking to resume \(resumeTicks) ticks (\(resumeSeconds)s)")
                        player.seek(
                            to: resumeTime,
                            toleranceBefore: .zero,
                            toleranceAfter: .zero
                        ) { finished in
                            player.play()
                            print("[Player] tvOS resumed from \(resumeSeconds)s (seek finished=\(finished))")
                        }
                    } else {
                        player.play()
                        print("[Player] tvOS playing from start")
                    }
                    onReady()
                }
                self.readyObservation = observation
            }

            func playerViewControllerWillBeginDismissalTransition(_: AVPlayerViewController) {
                onDismiss()
            }
        }
    }
#endif
