// Jellyswarrm — LGPL-2.1-or-later
#if os(tvOS)
#if canImport(TVVLCKit)
import UIKit
import TVVLCKit
import JellyswarrmCore

/// Full-screen VLC player on tvOS.
///
/// Presented via `TVNavigationCoordinator.present(_:)` — pure UIKit, no
/// SwiftUI `fullScreenCover` layer. This eliminates the double-dismiss bug
/// where Menu had to be pressed twice to return to MediaDetailView.
final class VLCPlayerViewController: UIViewController {

    private let mediaURL: URL
    private let startPosition: TimeInterval
    private let player = VLCMediaPlayer()

    // Transport overlay
    private lazy var overlayView = PlayerOverlayView()
    private var overlayHideTimer: Timer?

    init(url: URL, startAt position: TimeInterval = 0) {
        self.mediaURL = url
        self.startPosition = position
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        // VLC renders into self.view directly.
        player.drawable = self.view
        player.delegate = self

        setupOverlay()
        setupGestures()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let media = VLCMedia(url: mediaURL)
        if startPosition > 0 {
            media.addOption("--start-time=\(Int(startPosition))")
        }
        player.media = media
        player.play()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        player.stop()
    }

    private func setupOverlay() {
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)
        NSLayoutConstraint.activate([
            overlayView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            overlayView.heightAnchor.constraint(equalToConstant: 160)
        ])
        overlayView.alpha = 0

        overlayView.onPlayPause = { [weak self] in self?.togglePlayPause() }
        overlayView.onClose = { [weak self] in self?.dismiss(animated: true) }
    }

    private func setupGestures() {
        // Siri remote click/swipe shows overlay.
        let tap = UITapGestureRecognizer(target: self, action: #selector(showOverlay))
        tap.allowedPressTypes = [UIPress.PressType.select, .playPause].map { NSNumber(value: $0.rawValue) }
        view.addGestureRecognizer(tap)

        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(showOverlay))
        view.addGestureRecognizer(swipe)
    }

    @objc private func showOverlay() {
        overlayHideTimer?.invalidate()
        UIView.animate(withDuration: 0.2) { self.overlayView.alpha = 1 }
        overlayHideTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            UIView.animate(withDuration: 0.3) { self?.overlayView.alpha = 0 }
        }
    }

    private func togglePlayPause() {
        if player.isPlaying { player.pause() } else { player.play() }
        showOverlay()
    }
}

extension VLCPlayerViewController: VLCMediaPlayerDelegate {
    func mediaPlayerStateChanged(_ aNotification: Notification) {
        // VLC delegate fires off the main queue — hop to main for UI work.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.overlayView.isPlaying = self.player.isPlaying
        }
    }
}

// MARK: - Transport overlay

/// Minimal transport overlay — auto-hides after 3s, shows on remote interaction.
final class PlayerOverlayView: UIView {
    var onPlayPause: (() -> Void)?
    var onClose: (() -> Void)?
    var isPlaying: Bool = true {
        didSet { updatePlayPauseButton() }
    }

    private let playPauseButton = UIButton(type: .system)
    private let closeButton = UIButton(type: .system)
    private let progressView = UIProgressView(progressViewStyle: .default)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setup() {
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        blur.frame = bounds
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(blur)

        playPauseButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 32)), for: .normal)
        playPauseButton.tintColor = .white
        playPauseButton.addTarget(self, action: #selector(playPauseTapped), for: .primaryActionTriggered)

        closeButton.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 28)), for: .normal)
        closeButton.tintColor = .white
        closeButton.addTarget(self, action: #selector(closeTapped), for: .primaryActionTriggered)

        progressView.progressTintColor = .white
        progressView.trackTintColor = UIColor.white.withAlphaComponent(0.3)

        [playPauseButton, closeButton, progressView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            progressView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 60),
            progressView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -60),
            progressView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -40),
            progressView.heightAnchor.constraint(equalToConstant: 4),

            playPauseButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playPauseButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: 20),
        ])
    }

    private func updatePlayPauseButton() {
        let name = isPlaying ? "pause.fill" : "play.fill"
        playPauseButton.setImage(UIImage(systemName: name, withConfiguration: UIImage.SymbolConfiguration(pointSize: 32)), for: .normal)
    }

    @objc private func playPauseTapped() { onPlayPause?() }
    @objc private func closeTapped() { onClose?() }
}

// MARK: - PlayerViewModel hook installation

/// Installs the JellyswarrmCore `PlayerViewModel.tvOSPlaybackLauncher` hook so
/// `MediaDetailView.onChange(showPlayer)` → `vm.launchTVOSPlayer()` ultimately
/// reaches this UIKit view controller without JellyswarrmCore needing to
/// import UIKit / TVVLCKit.
enum TVPlayerHookInstaller {
    @MainActor
    static func install() {
        PlayerViewModel.tvOSPlaybackLauncher = { url, startAt in
            let vc = VLCPlayerViewController(url: url, startAt: startAt)
            TVNavigationCoordinator.shared.present(vc)
        }
    }
}
#endif // canImport(TVVLCKit)
#endif // os(tvOS)
