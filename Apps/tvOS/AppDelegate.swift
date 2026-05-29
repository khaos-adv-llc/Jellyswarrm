// Jellyswarrm — LGPL-2.1-or-later
#if os(tvOS)
import UIKit
import JellyswarrmCore

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    /// Single app-wide AppState shared with every SwiftUI host inside the tab
    /// bar. Held here so the UIKit shell owns its lifetime, matching the
    /// `@State` ownership the previous SwiftUI `App` provided.
    let appState = AppState()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = JellyswarrmTabBarController(appState: appState)
        window?.makeKeyAndVisible()

        // Wire the JellyswarrmCore → tvOS UIKit player bridge so
        // `PlayerViewModel.launchTVOSPlayer()` can present the VLC view
        // controller through TVNavigationCoordinator without JellyswarrmCore
        // importing UIKit / TVVLCKit.
        #if canImport(TVVLCKit)
        TVPlayerHookInstaller.install()
        #endif

        // Defer onboarding check until after the window is live so it can drive
        // SwiftUI sheet presentation inside the hosted view hierarchy.
        DispatchQueue.main.async { [appState] in
            appState.checkTVOSUserOnboarding()
        }
        return true
    }
}
#endif
