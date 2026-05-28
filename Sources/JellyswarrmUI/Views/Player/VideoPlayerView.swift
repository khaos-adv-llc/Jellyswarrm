// MARK: - VideoPlayerView.swift

// Jellyswarrm — GPL v3 with App Store exception

import AVKit
import JellyswarrmCore
import SwiftUI

public struct VideoPlayerView: View {
    let item: MediaItem
    let startFromBeginning: Bool
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // Optional + lazy-initialized in .onAppear so we never construct a dummy
    // PlayerViewModel against a throwaway AppState. iOS presents
    // AVPlayerViewController directly from .task via MainActor.run rather
    // than routing through a Color.clear.onAppear block — the onAppear
    // indirection caused a double presentation that tripped iOS -12860 when
    // SwiftUI re-rendered after `player` was assigned.
    @State private var playerVM: PlayerViewModel?
    @State private var player: AVPlayer?
    @State private var timeObserverToken: Any?
    @State private var controlsVisible: Bool = false

    public init(item: MediaItem, startFromBeginning: Bool = false) {
        self.item = item
        self.startFromBeginning = startFromBeginning
    }

    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let player {
                #if os(iOS)
                // On iOS, AVPlayerViewController is presented directly via
                // UIKit from .task (see presentAVPlayerViewController). The
                // @State `player` is retained solely so onDisappear can tear
                // down the AVPlayer; the body itself renders nothing for it.
                Color.clear
                #else
                SystemPlayerView(
                    player: player,
                    onDismiss: { dismiss() },
                    onControlsVisibilityChange: { visible in controlsVisible = visible }
                )
                .ignoresSafeArea()
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
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .onAppear {
            // Bind the VM to the real AppState exactly once, synchronously,
            // before .task runs. onAppear fires once per view identity and
            // finishes before .task begins, so playerVM is non-nil by the
            // time .task reads it.
            if playerVM == nil {
                playerVM = PlayerViewModel(appState: appState)
            }
        }
        .task(id: item.id) {
            guard let vm = playerVM else { return }
            await vm.loadPlayback(for: item, startFromBeginning: startFromBeginning)
            guard let url = vm.playbackURL else {
                print("[Player] ERROR: no playbackURL after loadPlayback")
                return
            }

            let asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: false,
            ])

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

            #if os(iOS)
            // On iOS, seek + play are deferred to isReadyForDisplay (see
            // presentAVPlayerViewController). Seeking before the layer is
            // attached to a real window causes AVPlayerViewController to
            // reset position to 0 once it mounts.
            //
            // Present AVPlayerViewController directly from here on the main
            // actor, BEFORE assigning @State player. Routing presentation
            // through Color.clear.onAppear caused a double presentation: the
            // @State assignment re-rendered the body, the newly-inserted
            // Color.clear subtree's onAppear fired, and SwiftUI's view-identity
            // semantics could fire it twice — producing a second
            // AVPlayerViewController that killed the first with iOS -12860.
            await MainActor.run {
                presentAVPlayerViewController(
                    player: avPlayer,
                    vm: vm,
                    statusObservation: statusObservation,
                    tcObservation: tcObservation
                )
            }
            player = avPlayer
            #else
            _ = statusObservation
            _ = tcObservation
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
                vm.positionTicks = ticks
                let defaults = UserDefaults.standard
                let key = "resume_\(itemId)"
                let duration = player.currentItem?.duration.seconds
                if let duration, duration.isFinite, duration > 0, seconds > duration - 60 {
                    defaults.removeObject(forKey: key)
                } else {
                    defaults.set(Double(ticks), forKey: key)
                }
            }
            #endif
            vm.isPlaying = true
            if let chapters = vm.currentItem?.chapters, !chapters.isEmpty {
                vm.startChapterObserver(on: avPlayer, chapters: chapters)
            }
        }
        .onDisappear {
            playerVM?.stopChapterObserver()
            #if !os(iOS)
            // iOS teardown is handled by DismissAwareAVPlayerViewController
            // .viewDidDisappear — SwiftUI fires this onDisappear spuriously on
            // iOS 26 beta when the parent MediaDetailView re-renders, which
            // would otherwise kill the active player mid-playback.
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

    #if os(iOS)
    private func presentAVPlayerViewController(
        player: AVPlayer,
        vm: PlayerViewModel,
        statusObservation: NSKeyValueObservation,
        tcObservation: NSKeyValueObservation
    ) {
        print("[Player] UIKit-presenting AVPlayerViewController, player=\(player), item=\(String(describing: player.currentItem))")

        let playerVC = DismissAwareAVPlayerViewController()
        playerVC.player = player
        playerVC.showsPlaybackControls = true
        playerVC.videoGravity = .resizeAspect
        playerVC.allowsPictureInPicturePlayback = true
        playerVC.updatesNowPlayingInfoCenter = false
        playerVC.modalPresentationStyle = .fullScreen
        playerVC.entersFullScreenWhenPlaybackBegins = true
        playerVC.exitsFullScreenWhenPlaybackEnds = true
        playerVC.onDismissed = { dismiss() }
        playerVC.onStop = { [weak vm] in
            // Mirror the non-iOS teardown sequence: pause + drop the item to
            // cancel in-flight proxy fetches, brief sleep, then stop the VM.
            await MainActor.run {
                player.pause()
                player.replaceCurrentItem(with: nil)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            await vm?.stop()
        }
        playerVC.itemId = item.id
        // Retain the diagnostic KVO tokens for the session — without this
        // they deinit immediately after .task returns, which can interfere
        // with AVPlayerItem/AVPlayer internal state. viewDidDisappear nils
        // them at teardown.
        playerVC.statusObservation = statusObservation
        playerVC.tcObservation = tcObservation
        playerVC.resumeSeconds = vm.positionTicks.ticksToSeconds
        // Both direct-stream and HLS-transcode resume by seeking the local
        // AVPlayer after isReadyForDisplay fires. Passing StartTimeTicks to
        // Jellyfin causes the first .ts segment to lack a keyframe at PTS 0,
        // which AVFoundation rejects with the "Playback Prohibited" icon.
        playerVC.shouldSeekForResume = true

        let vmRef = vm
        let readyObservation = playerVC.observe(\.isReadyForDisplay, options: [.new]) { [weak playerVC, weak player] vc, change in
            print("[Player] AVPlayerViewController readyForDisplay → \(vc.isReadyForDisplay)")
            guard change.newValue == true, let player = player else { return }
            playerVC?.readyObservation = nil

            let resumeSeconds = playerVC?.resumeSeconds ?? 0
            let itemId = playerVC?.itemId ?? ""
            let shouldSeek = playerVC?.shouldSeekForResume ?? true
            let resumeTicks = Int64(resumeSeconds * 10_000_000)
            print("[Resume] Starting from: \(resumeTicks) ticks for \(itemId) (seek=\(shouldSeek))")
            if shouldSeek && resumeSeconds > 5.0 {
                // Jellyfin ticks are 10-million-ths of a second; use that
                // timescale directly so the seek target is exact rather than
                // quantized to 600Hz.
                let resumeTime = CMTime(value: resumeTicks, timescale: 10_000_000)
                print("[Player] Seeking to resume position: \(resumeTicks) ticks (\(resumeSeconds)s)")
                // The completion handler used to also call notifyPlaybackStarted
                // and the periodic time observer would fire immediately after
                // seek finished — producing two `[Resume] Saved` lines in quick
                // succession. Keep the completion handler narrow: just resume
                // playback. The periodic observer (installed below) will pick
                // up the position on its first scheduled fire.
                player.seek(
                    to: resumeTime,
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                ) { finished in
                    player.play()
                    print("[Player] Resumed and playing from \(resumeSeconds)s (seek finished=\(finished))")
                }
            } else {
                player.play()
                print("[Player] Playing from start")
            }
            Task { @MainActor in await vmRef.notifyPlaybackStarted() }
        }
        playerVC.readyObservation = readyObservation

        let interval = CMTime(seconds: 10, preferredTimescale: 600)
        // The AVPlayer is seeked to the resume point client-side after
        // readyForDisplay, so its currentTime is already the true content
        // position — no offset adjustment needed. Capture vm weakly so the
        // observer closure cannot keep the view model alive past view
        // teardown if the observer is somehow not removed.
        playerVC.timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak playerVC, weak player, weak vm] time in
            guard let player = player,
                  let vc = playerVC,
                  let vm,
                  player.timeControlStatus == .playing else { return }
            let seconds = time.seconds
            guard seconds.isFinite, seconds > 0 else { return }
            let ticks = Int64(seconds * 10_000_000)
            vm.positionTicks = ticks
            let defaults = UserDefaults.standard
            let key = "resume_\(vc.itemId)"
            let duration = player.currentItem?.duration.seconds
            if let duration, duration.isFinite, duration > 0, seconds > duration - 60 {
                defaults.removeObject(forKey: key)
                print("[Resume] Cleared ticks for \(vc.itemId) (near end of media)")
            } else {
                defaults.set(Double(ticks), forKey: key)
                print("[Resume] Saved \(ticks) ticks for \(vc.itemId) (server + local)")
            }
        }

        // iOS 26 beta: after seek completes, AVPlayerViewController's controls
        // auto-hide timer fails to re-arm and the scrub bar stays visible. Watch
        // timeControlStatus transition from waiting → playing (the signature of
        // a seek completing) and force a controls reset to re-arm the timer.
        playerVC.seekStatusObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak playerVC] p, _ in
            DispatchQueue.main.async {
                guard let vc = playerVC else { return }
                switch p.timeControlStatus {
                case .waitingToPlayAtSpecifiedRate:
                    vc.wasSeekingOrWaiting = true
                case .playing:
                    if vc.wasSeekingOrWaiting {
                        vc.wasSeekingOrWaiting = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak vc] in
                            vc?.showsPlaybackControls = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak vc] in
                                vc?.showsPlaybackControls = true
                            }
                        }
                    }
                default:
                    break
                }
            }
        }

        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow })?
            .rootViewController
        else {
            print("[Player] ERROR: could not find root view controller for UIKit presentation")
            return
        }

        var top = root
        while let next = top.presentedViewController {
            top = next
        }

        top.present(playerVC, animated: true) {
            print("[Player] AVPlayerViewController UIKit-presented, awaiting readyForDisplay for autoplay")
        }
    }
    #endif
}

#if os(iOS)
private final class DismissAwareAVPlayerViewController: AVPlayerViewController {
    var onDismissed: (() -> Void)?
    var onStop: (() async -> Void)?
    var readyObservation: NSKeyValueObservation?
    var seekStatusObservation: NSKeyValueObservation?
    var statusObservation: NSKeyValueObservation?
    var tcObservation: NSKeyValueObservation?
    var wasSeekingOrWaiting: Bool = false
    var resumeSeconds: Double = 0
    var shouldSeekForResume: Bool = true
    var itemId: String = ""
    var timeObserver: Any?

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // Only genuine dismissal — not SwiftUI lifecycle churn — should tear
        // down the player session.
        if isBeingDismissed || isMovingFromParent {
            if let token = timeObserver {
                player?.removeTimeObserver(token)
                timeObserver = nil
            }
            statusObservation = nil
            tcObservation = nil
            let stop = onStop
            onStop = nil
            Task { await stop?() }
            onDismissed?()
            onDismissed = nil
        }
    }
}
#endif

// MARK: - System AVPlayerViewController (tvOS, macOS)
// Using AVPlayerViewController on tvOS/macOS ensures:
// - Correct HDR / Dolby Vision tone-mapping via VideoToolbox
// - Native transport bar with working dismiss / done button
// - Picture-in-Picture and AirPlay support

#if os(macOS)
    import AppKit

    // macOS has no AVPlayerViewController — use AVPlayerView from AVKit (AppKit).
    struct SystemPlayerView: NSViewRepresentable {
        let player: AVPlayer
        let onDismiss: () -> Void
        var onControlsVisibilityChange: ((Bool) -> Void)? = nil

        func makeNSView(context _: Context) -> AVPlayerView {
            let view = AVPlayerView()
            view.player = player
            view.controlsStyle = .inline
            view.showsFullScreenToggleButton = true
            view.allowsPictureInPicturePlayback = true
            return view
        }

        func updateNSView(_ nsView: AVPlayerView, context _: Context) {
            if nsView.player !== player {
                nsView.player = player
            }
        }
    }
#elseif os(tvOS)
    import UIKit

    struct SystemPlayerView: UIViewControllerRepresentable {
        let player: AVPlayer
        let onDismiss: () -> Void
        var onControlsVisibilityChange: ((Bool) -> Void)? = nil

        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let playerVC = AVPlayerViewController()
            playerVC.player = player
            playerVC.showsPlaybackControls = true
            playerVC.videoGravity = .resizeAspect
            playerVC.allowsPictureInPicturePlayback = true
            playerVC.delegate = context.coordinator
            return playerVC
        }

        func updateUIViewController(_ playerVC: AVPlayerViewController, context _: Context) {
            if playerVC.player !== player {
                playerVC.player = player
            }
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(onDismiss: onDismiss)
        }

        final class Coordinator: NSObject, AVPlayerViewControllerDelegate {
            let onDismiss: () -> Void
            init(onDismiss: @escaping () -> Void) {
                self.onDismiss = onDismiss
            }

            func playerViewControllerWillBeginDismissalTransition(_ playerViewController: AVPlayerViewController) {
                onDismiss()
            }
        }
    }
#endif
