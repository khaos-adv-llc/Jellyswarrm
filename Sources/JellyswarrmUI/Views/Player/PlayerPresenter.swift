// MARK: - PlayerPresenter.swift

// Jellyswarrm — GPL v3 with App Store exception

#if os(iOS)
import AVKit
import JellyswarrmCore
import SwiftUI
import UIKit

/// iOS-only presenter that bypasses SwiftUI's modal stack by attaching
/// AVPlayerViewController (or VLCPlayerHostController) directly to the
/// top-most UIViewController in the key window.
///
/// Replaces the previous `.fullScreenCover(...) { VideoPlayerView(...) }` flow,
/// which created two modal layers (SwiftUI cover + AVPlayerViewController on
/// top) and required the user to tap "Done" twice — once to dismiss
/// AVPlayerViewController, again to dismiss the empty SwiftUI cover behind it.
@MainActor
enum PlayerPresenter {
    /// Build the PlayerViewModel, resolve the playback URL + engine, then
    /// present either AVPlayerViewController (AVFoundation engine) or a
    /// UIHostingController wrapping VideoPlayerView (VLC engine) directly from
    /// the top UIViewController. `onDismissed` is invoked on the main actor
    /// after the presented controller is fully gone.
    static func presentPlayer(
        item: MediaItem,
        startFromBeginning: Bool,
        appState: AppState,
        onDismissed: @escaping () -> Void
    ) {
        // Fast-path: if the user's playback engine preference is VLC, skip
        // pre-loading entirely and let the wrapped VideoPlayerView load
        // through its own task. VLC presents a single UIKit modal layer
        // (UIHostingController of VideoPlayerView), so the double-close bug
        // doesn't reach this path.
        let prefRaw = UserDefaults.standard.string(forKey: "playbackEngine") ?? PlaybackEngine.auto.rawValue
        let preference = PlaybackEngine(rawValue: prefRaw) ?? .auto
        if preference == .vlc {
            presentVLCDirect(item: item, startFromBeginning: startFromBeginning, appState: appState, onDismissed: onDismissed)
            return
        }

        Task { @MainActor in
            let vm = PlayerViewModel(appState: appState)
            await vm.loadPlayback(for: item, startFromBeginning: startFromBeginning)

            guard let url = vm.playbackURL else {
                print("[PlayerPresenter] ERROR: no playbackURL after loadPlayback")
                onDismissed()
                return
            }

            let asset = AVURLAsset(url: url, options: [
                AVURLAssetPreferPreciseDurationAndTimingKey: false,
            ])
            await vm.detectHDR(asset: asset)

            if vm.resolvedEngine == .vlc {
                // Auto-resolved to VLC. Tear down the AVFoundation VM and
                // present a fresh VideoPlayerView in a UIHostingController —
                // it will reload and route through its VLC body.
                await vm.stop()
                presentVLCDirect(item: item, startFromBeginning: startFromBeginning, appState: appState, onDismissed: onDismissed)
                return
            }

            await presentAVFoundation(
                item: item,
                vm: vm,
                asset: asset,
                onDismissed: onDismissed
            )
        }
    }

    /// Walks the connectedScenes → keyWindow → rootViewController chain to find
    /// the foreground active top-most presented view controller. Returns nil if
    /// none is available or the top-most is mid-dismissal.
    private static func topViewController() -> UIViewController? {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow })?
            .rootViewController
        else { return nil }
        var top = root
        while let next = top.presentedViewController, !next.isBeingDismissed {
            top = next
        }
        return top.isBeingDismissed ? nil : top
    }

    /// Present VideoPlayerView directly inside a UIHostingController. The view
    /// loads + plays via its own .task. Single UIKit modal layer — no SwiftUI
    /// .fullScreenCover above it, so the double-close bug doesn't apply.
    private static func presentVLCDirect(
        item: MediaItem,
        startFromBeginning: Bool,
        appState: AppState,
        onDismissed: @escaping () -> Void
    ) {
        final class Box { weak var hc: UIHostingController<AnyView>? }
        let box = Box()

        let onClose: () -> Void = {
            box.hc?.dismiss(animated: true) { onDismissed() }
        }

        let root = AnyView(
            VideoPlayerView(item: item, startFromBeginning: startFromBeginning, onClose: onClose)
                .environment(appState)
        )
        let hosting = UIHostingController(rootView: root)
        hosting.modalPresentationStyle = .fullScreen
        box.hc = hosting

        guard let top = topViewController() else {
            print("[PlayerPresenter] ERROR: no top VC for VLC presentation")
            onDismissed()
            return
        }
        top.present(hosting, animated: true)
    }

    private static func presentAVFoundation(
        item: MediaItem,
        vm: PlayerViewModel,
        asset: AVURLAsset,
        onDismissed: @escaping () -> Void
    ) async {
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.preferredForwardBufferDuration = 10
        vm.configurePlayerItem(playerItem)
        let avPlayer = AVPlayer(playerItem: playerItem)
        avPlayer.automaticallyWaitsToMinimizeStalling = false

        let statusObservation = playerItem.observe(\.status, options: [.new]) { item, _ in
            switch item.status {
            case .failed:
                let err = item.error
                print("[Player] AVPlayerItem FAILED: \(err?.localizedDescription ?? "unknown")")
            case .readyToPlay:
                print("[Player] AVPlayerItem readyToPlay ✓")
            case .unknown:
                print("[Player] AVPlayerItem status unknown")
            @unknown default:
                break
            }
        }

        let tcObservation = avPlayer.observe(\.timeControlStatus, options: [.new]) { p, _ in
            switch p.timeControlStatus {
            case .playing: print("[Player] AVPlayer playing ✓")
            case .paused: print("[Player] AVPlayer paused")
            case .waitingToPlayAtSpecifiedRate:
                print("[Player] AVPlayer waiting: \(String(describing: p.reasonForWaitingToPlay))")
            @unknown default: break
            }
        }

        let playerVC = DismissAwareAVPlayerViewController()
        playerVC.player = avPlayer
        playerVC.showsPlaybackControls = true
        playerVC.videoGravity = .resizeAspect
        playerVC.allowsPictureInPicturePlayback = true
        playerVC.updatesNowPlayingInfoCenter = false
        playerVC.modalPresentationStyle = .fullScreen
        playerVC.entersFullScreenWhenPlaybackBegins = true
        playerVC.exitsFullScreenWhenPlaybackEnds = true
        playerVC.onDismissed = { onDismissed() }
        playerVC.onStop = { [weak vm] in
            await MainActor.run {
                avPlayer.pause()
                avPlayer.replaceCurrentItem(with: nil)
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
            await vm?.stop()
        }
        playerVC.itemId = item.id
        playerVC.statusObservation = statusObservation
        playerVC.tcObservation = tcObservation
        playerVC.resumeSeconds = vm.positionTicks.ticksToSeconds
        playerVC.shouldSeekForResume = true

        let readyObservation = playerVC.observe(\.isReadyForDisplay, options: [.new]) { [weak playerVC, weak avPlayer] vc, change in
            print("[Player] AVPlayerViewController readyForDisplay → \(vc.isReadyForDisplay)")
            guard change.newValue == true, let avPlayer else { return }
            playerVC?.readyObservation = nil

            let resumeSeconds = playerVC?.resumeSeconds ?? 0
            let itemId = playerVC?.itemId ?? ""
            let shouldSeek = playerVC?.shouldSeekForResume ?? true
            let resumeTicks = Int64(resumeSeconds * 10_000_000)
            print("[Resume] Starting from: \(resumeTicks) ticks for \(itemId) (seek=\(shouldSeek))")
            if shouldSeek && resumeSeconds > 5.0 {
                let resumeTime = CMTime(value: resumeTicks, timescale: 10_000_000)
                avPlayer.seek(
                    to: resumeTime,
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                ) { finished in
                    avPlayer.play()
                    print("[Player] Resumed and playing from \(resumeSeconds)s (seek finished=\(finished))")
                }
            } else {
                avPlayer.play()
                print("[Player] Playing from start")
            }
            Task { @MainActor in await vm.notifyPlaybackStarted() }
        }
        playerVC.readyObservation = readyObservation

        let interval = CMTime(seconds: 10, preferredTimescale: 600)
        playerVC.timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak playerVC, weak avPlayer, weak vm] time in
            guard let avPlayer,
                  let vc = playerVC,
                  let vm,
                  avPlayer.timeControlStatus == .playing else { return }
            let seconds = time.seconds
            guard seconds.isFinite, seconds > 0 else { return }
            let ticks = Int64(seconds * 10_000_000)
            Task { @MainActor in
                vm.positionTicks = ticks
            }
            let defaults = UserDefaults.standard
            let key = "resume_\(vc.itemId)"
            let duration = avPlayer.currentItem?.duration.seconds
            if let duration, duration.isFinite, duration > 0, seconds > duration - 60 {
                defaults.removeObject(forKey: key)
            } else {
                defaults.set(Double(ticks), forKey: key)
            }
        }

        playerVC.seekStatusObservation = avPlayer.observe(\.timeControlStatus, options: [.new]) { [weak playerVC] p, _ in
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

        if vm.isPlaying == false {
            vm.isPlaying = true
        }
        if let chapters = vm.currentItem?.chapters, !chapters.isEmpty {
            vm.startChapterObserver(on: avPlayer, chapters: chapters)
        }

        guard let top = topViewController() else {
            print("[PlayerPresenter] ERROR: no top VC for AVFoundation presentation")
            onDismissed()
            return
        }
        top.present(playerVC, animated: true) {
            print("[PlayerPresenter] AVPlayerViewController presented (single layer, no fullScreenCover)")
        }
    }
}

/// AVPlayerViewController subclass that fires `onDismissed` exactly once,
/// at `viewDidDisappear` triggered by a real dismissal (not SwiftUI lifecycle
/// churn).
final class DismissAwareAVPlayerViewController: AVPlayerViewController {
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
        if isBeingDismissed || isMovingFromParent {
            if let token = timeObserver {
                player?.removeTimeObserver(token)
                timeObserver = nil
            }
            statusObservation = nil
            tcObservation = nil
            let stopClosure = onStop
            onStop = nil
            Task { await stopClosure?() }
            let dismissClosure = onDismissed
            onDismissed = nil
            dismissClosure?()
        }
    }
}

#endif
