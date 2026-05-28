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
