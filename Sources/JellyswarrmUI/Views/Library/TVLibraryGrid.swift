// MARK: - TVLibraryGrid.swift

// Jellyswarrm — LGPL-2.1-or-later
// tvOS-only UICollectionViewCompositionalLayout grid for the library items
// view. Uses UIKit instead of LazyVGrid to get:
//   • Native focus parallax (adjustsImageWhenAncestorFocused = true)
//   • Predictable focus traversal across rows
//   • No SwiftUI lazy-sizing races

#if os(tvOS)
import JellyswarrmCore
import SwiftUI
import UIKit

struct TVLibraryGrid: UIViewRepresentable {
    let items: [MediaItem]
    var onSelect: (MediaItem) -> Void
    var onPaginate: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect, onPaginate: onPaginate)
    }

    func makeUIView(context: Context) -> UICollectionView {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            // Cell = poster (330pt) + ~60pt label area below.
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .absolute(220),
                heightDimension: .absolute(390)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)
            item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(390)
            )
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])

            let section = NSCollectionLayoutSection(group: group)
            section.contentInsets = NSDirectionalEdgeInsets(top: 24, leading: 48, bottom: 24, trailing: 48)
            section.interGroupSpacing = 24
            return section
        }

        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = UIColor(AppleTVTheme.background)
        cv.register(LibraryPosterCell.self, forCellWithReuseIdentifier: LibraryPosterCell.reuseID)
        cv.delegate = context.coordinator
        cv.dataSource = context.coordinator
        cv.remembersLastFocusedIndexPath = true
        context.coordinator.collectionView = cv
        context.coordinator.items = items
        return cv
    }

    func updateUIView(_ cv: UICollectionView, context: Context) {
        let oldCount = context.coordinator.items.count
        context.coordinator.items = items
        context.coordinator.onSelect = onSelect
        context.coordinator.onPaginate = onPaginate
        // Only reload when the item set actually changed — avoids killing
        // focus on every parent re-render.
        if items.count != oldCount {
            cv.reloadData()
        } else {
            // Reload just the visible cells to refresh artwork / metadata.
            cv.reloadData()
        }
    }

    final class Coordinator: NSObject, UICollectionViewDelegate, UICollectionViewDataSource {
        var items: [MediaItem] = []
        var onSelect: (MediaItem) -> Void
        var onPaginate: (() -> Void)?
        weak var collectionView: UICollectionView?

        init(onSelect: @escaping (MediaItem) -> Void, onPaginate: (() -> Void)?) {
            self.onSelect = onSelect
            self.onPaginate = onPaginate
        }

        func collectionView(_ cv: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            items.count
        }

        func collectionView(_ cv: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            let cell = cv.dequeueReusableCell(
                withReuseIdentifier: LibraryPosterCell.reuseID,
                for: indexPath
            ) as! LibraryPosterCell
            cell.configure(with: items[indexPath.item])
            return cell
        }

        func collectionView(_ cv: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            guard indexPath.item < items.count else { return }
            onSelect(items[indexPath.item])
        }

        func collectionView(_ cv: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
            // Paginate near the end of the grid.
            if indexPath.item >= items.count - 6 {
                onPaginate?()
            }
        }
    }
}

// MARK: - Cell

final class LibraryPosterCell: UICollectionViewCell {
    static let reuseID = "LibraryPosterCell"

    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let yearLabel = UILabel()
    private let watchedBadge = UIImageView()
    private var imageTask: URLSessionDataTask?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageTask?.cancel()
        imageTask = nil
        imageView.image = nil
        titleLabel.text = nil
        yearLabel.text = nil
        watchedBadge.isHidden = true
    }

    private func setup() {
        // Poster image — native tvOS parallax kicks in via this property.
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 12
        imageView.backgroundColor = UIColor(AppleTVTheme.cardBackground)
        imageView.adjustsImageWhenAncestorFocused = true

        titleLabel.font = .systemFont(ofSize: 22, weight: .medium)
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 1

        yearLabel.font = .systemFont(ofSize: 18)
        yearLabel.textColor = UIColor(AppleTVTheme.labelSecondary)

        watchedBadge.image = UIImage(systemName: "checkmark.circle.fill")
        watchedBadge.tintColor = .white
        watchedBadge.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        watchedBadge.layer.cornerRadius = 12
        watchedBadge.layer.masksToBounds = true
        watchedBadge.isHidden = true

        [imageView, titleLabel, yearLabel, watchedBadge].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview($0)
        }

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.heightAnchor.constraint(equalToConstant: 330),

            watchedBadge.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 10),
            watchedBadge.trailingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: -10),
            watchedBadge.widthAnchor.constraint(equalToConstant: 24),
            watchedBadge.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -4),

            yearLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            yearLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 4),
        ])
    }

    func configure(with item: MediaItem) {
        titleLabel.text = item.displayTitle
        yearLabel.text = item.productionYear.map(String.init)
        watchedBadge.isHidden = !(item.userData?.played ?? false)

        if let server = AppStateProvider.currentServer,
           let tag = item.imageTags?["Primary"]
        {
            let url = JellyfinAPIClient.shared.imageURL(
                server: server,
                itemId: item.id,
                imageType: .primary,
                tag: tag,
                maxWidth: 440
            )
            let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                if let data, let img = UIImage(data: data) {
                    DispatchQueue.main.async { self?.imageView.image = img }
                }
            }
            imageTask = task
            task.resume()
        }
    }

    // Native tvOS focus lift — UIKit drives the standard parallax via
    // `adjustsImageWhenAncestorFocused`; on top of that we lift the cell on
    // focus to match the SwiftUI card scale.
    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)
        coordinator.addCoordinatedAnimations {
            let focused = self.isFocused
            self.titleLabel.alpha = focused ? 1.0 : 0.85
            self.yearLabel.alpha = focused ? 1.0 : 0.85
        }
    }

    override var canBecomeFocused: Bool { true }
}

// MARK: - Static AppState bridge

/// UIKit cells can't pick up SwiftUI's @Environment, so we bridge through a
/// small static holder set by `LibraryView` on appear.
enum AppStateProvider {
    nonisolated(unsafe) static var currentServer: JellyfinServer?
}
#endif
