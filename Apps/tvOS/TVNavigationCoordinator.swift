// Jellyswarrm — LGPL-2.1-or-later
#if os(tvOS)
import UIKit
import SwiftUI

/// Shared navigation coordinator for tvOS — SwiftUI views call this to push
/// detail views or present full-screen modal view controllers (e.g. the VLC
/// player) instead of using NavigationLink/NavigationStack or
/// `.fullScreenCover`, which produce ghost titles and double-dismiss bugs on
/// tvOS.
@MainActor
final class TVNavigationCoordinator: ObservableObject {
    static let shared = TVNavigationCoordinator()

    private init() {}

    /// Push a SwiftUI view onto the currently-selected tab's UINavigationController.
    func push<V: View>(_ view: V) {
        guard let nav = currentNavigationController() else { return }
        let host = UIHostingController(rootView: view)
        nav.pushViewController(host, animated: true)
        nav.setNavigationBarHidden(true, animated: false)
    }

    /// Pop the top view controller from the currently-selected tab.
    func pop() {
        currentNavigationController()?.popViewController(animated: true)
    }

    /// Full-screen modal present of a UIViewController. Used by
    /// `PlayerViewModel` to launch `VLCPlayerViewController` outside of any
    /// SwiftUI presentation layer — guarantees a single modal stack so the
    /// Siri Remote's Menu button dismisses cleanly in one press.
    func present(_ viewController: UIViewController) {
        guard let top = topPresentedViewController() else { return }
        viewController.modalPresentationStyle = .fullScreen
        top.present(viewController, animated: true)
    }

    /// Dismiss the top-most presented controller (the inverse of `present`).
    func dismiss() {
        topPresentedViewController()?.dismiss(animated: true)
    }

    private func currentNavigationController() -> UINavigationController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController as? UITabBarController,
              let nav = root.selectedViewController as? UINavigationController else { return nil }
        return nav
    }

    private func topPresentedViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              var top = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }
}
#endif
