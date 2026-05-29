// Jellyswarrm — LGPL-2.1-or-later
#if os(tvOS)
import UIKit
import SwiftUI
import JellyswarrmCore
import JellyswarrmUI

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

        // Wire the JellyswarrmCore → tvOS UIKit player bridge so
        // `PlayerViewModel.launchTVOSPlayer()` can present the VLC view
        // controller through TVNavigationCoordinator without JellyswarrmCore
        // importing UIKit / TVVLCKit.
        #if canImport(TVVLCKit)
        TVPlayerHookInstaller.install()
        #endif

        installInitialRootViewController()
        window?.makeKeyAndVisible()

        // Defer onboarding check until after the window is live so it can drive
        // SwiftUI sheet presentation inside the hosted view hierarchy.
        DispatchQueue.main.async { [appState] in
            appState.checkTVOSUserOnboarding()
        }
        return true
    }

    /// Choose the root VC based on stored profiles:
    ///   no profiles → onboarding wizard
    ///   one profile (or one autoSignIn) → straight to tab bar
    ///   multiple profiles → picker
    @MainActor
    private func installInitialRootViewController() {
        let pm = ProfileManager.shared

        if pm.profiles.isEmpty {
            window?.rootViewController = JellyswarrmTabBarController(appState: appState)
            return
        }

        if pm.shouldAutoSignIn, let profile = pm.autoSignInProfile {
            pm.setActive(profile)
            window?.rootViewController = JellyswarrmTabBarController(appState: appState)
            return
        }

        installProfilePicker()
    }

    @MainActor
    private func installProfilePicker() {
        let picker = TVProfilePickerView(
            onSelect: { [weak self] profile in
                guard let self else { return }
                ProfileManager.shared.setActive(profile)
                self.window?.rootViewController = JellyswarrmTabBarController(appState: self.appState)
            },
            onAddNew: { [weak self] in
                guard let self else { return }
                self.window?.rootViewController = JellyswarrmTabBarController(appState: self.appState)
                DispatchQueue.main.async {
                    self.appState.needsTVOSUserOnboarding = true
                }
            }
        )
        window?.rootViewController = UIHostingController(rootView: picker)
    }
}
#endif
