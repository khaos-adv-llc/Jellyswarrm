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
                    appState.loadFromStorage()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
