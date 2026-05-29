// Jellyswarrm — LGPL-2.1-or-later
//
// tvOS app entry point lives in `Apps/tvOS/AppDelegate.swift` (pure UIKit),
// which owns `@main`. The previous SwiftUI `App` here is gated out so the
// tvOS target compiles cleanly with the new UIKit shell.

#if !os(tvOS)
import JellyswarrmCore
import JellyswarrmUI
import SwiftUI

@main
struct JellyswarmApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task {
                    // loadFromStorage() is called in AppState.init() synchronously.
                    // checkTVOSUserOnboarding() needs to run after the view tree is
                    // live so it can trigger the sheet presentation.
                    appState.checkTVOSUserOnboarding()
                }
        }
    }
}
#endif
