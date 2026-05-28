#if os(iOS) || os(tvOS)
import AVFoundation
import Foundation

extension PlayerViewModel {

    func setChapterMetadata(chapters: [ChapterInfo], on playerItem: AVPlayerItem) {
        var groups: [AVTimedMetadataGroup] = []

        for (index, chapter) in chapters.enumerated() {
            guard let ticks = chapter.startPositionTicks,
                  let name = chapter.name, !name.isEmpty else { continue }

            let startSec = Double(ticks) / 10_000_000.0
            let nextTicks = index + 1 < chapters.count
                ? (chapters[index + 1].startPositionTicks ?? ticks + 600_000_000)
                : ticks + 600_000_000
            let durationSec = max(Double(nextTicks - ticks) / 10_000_000.0, 0.001)

            let titleItem = AVMutableMetadataItem()
            titleItem.identifier = .commonIdentifierTitle
            titleItem.value = name as NSString
            titleItem.extendedLanguageTag = "und"

            let timeRange = CMTimeRange(
                start: CMTime(seconds: startSec, preferredTimescale: 600),
                duration: CMTime(seconds: durationSec, preferredTimescale: 600)
            )
            groups.append(AVTimedMetadataGroup(items: [titleItem], timeRange: timeRange))
        }

        playerItem.navigationMarkers = groups
    }
}
#endif
