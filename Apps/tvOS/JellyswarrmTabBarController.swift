// Jellyswarrm — LGPL-2.1-or-later
#if os(tvOS)
import UIKit
import SwiftUI
import JellyswarrmCore
import JellyswarrmUI

final class JellyswarrmTabBarController: UITabBarController {

    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupAppearance()
        setupTabs()
    }

    private func setupAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
    }

    private func setupTabs() {
        // Each tab: UINavigationController with nav bar PERMANENTLY hidden.
        // SwiftUI view hosted inside — no NavigationStack, no ghost titles
        // possible.
        let watchNow = makeTab(
            root: HomeView().environment(appState),
            title: "Watch Now",
            image: UIImage(systemName: "play.circle.fill")
        )

        let library = makeTab(
            root: LibraryView().environment(appState),
            title: "Library",
            image: UIImage(systemName: "books.vertical.fill")
        )

        let discover = makeTab(
            root: DiscoverView().environment(appState),
            title: "Discover",
            image: UIImage(systemName: "sparkles.tv.fill")
        )

        let search = makeTab(
            root: SearchView().environment(appState),
            title: "Search",
            image: UIImage(systemName: "magnifyingglass")
        )

        let settings = makeTab(
            root: SettingsView().environment(appState),
            title: "Settings",
            image: UIImage(systemName: "gearshape.fill")
        )

        viewControllers = [watchNow, library, discover, search, settings]
    }

    private func makeTab<V: View>(root: V, title: String, image: UIImage?) -> UINavigationController {
        let host = UIHostingController(rootView: root)
        host.title = title

        let nav = UINavigationController(rootViewController: host)
        // PERMANENTLY hide the navigation bar — eliminates ALL ghost title
        // possibilities surfacing from NavigationStack on tvOS.
        nav.setNavigationBarHidden(true, animated: false)
        nav.navigationBar.isHidden = true

        nav.tabBarItem = UITabBarItem(title: title, image: image, selectedImage: image)
        return nav
    }
}
#endif
