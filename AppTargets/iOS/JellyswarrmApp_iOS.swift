import AVFoundation
import JellyswarrmCore
import JellyswarrmUI
import SwiftUI

@main
struct JellyswarmApp: App {
    @State private var appState = AppState()

    init() {
        // Configure audio session for video playback BEFORE AVPlayer is ever
        // created. Without this, iOS kills mediaserverd (-12860) when AVPlayer
        // tries to activate the audio route on first play.
        // .playback category: allows background audio, disables mute-switch silence,
        // enables AirPlay/AirPods routing, and grants the entitlement AVPlayer needs.
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            // Non-fatal — log and continue. Playback may still work in foreground.
            print("[AudioSession] Failed to configure: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
        }
    }
}
