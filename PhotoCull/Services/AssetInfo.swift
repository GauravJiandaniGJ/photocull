import Foundation
import Photos

/// Sendable snapshot of the PHAsset fields the pipeline needs (spec §4.1). PHAsset itself is
/// not Sendable, so the fetch thread builds these and everything downstream uses them.
struct AssetInfo: Sendable, Identifiable, Equatable {
    let id: String
    let creationDate: Date
    let modificationDate: Date?
    let pixelWidth: Int
    let pixelHeight: Int
    let isFavorite: Bool
    let isScreenshot: Bool
    let burstIdentifier: String?
    let hasLocation: Bool
    let isVideo: Bool
    let duration: Double

    var pixelCount: Int { pixelWidth * pixelHeight }

    init(_ asset: PHAsset) {
        id = asset.localIdentifier
        creationDate = asset.creationDate ?? .distantPast
        modificationDate = asset.modificationDate
        pixelWidth = asset.pixelWidth
        pixelHeight = asset.pixelHeight
        isFavorite = asset.isFavorite
        isScreenshot = asset.mediaSubtypes.contains(.photoScreenshot)
        burstIdentifier = asset.burstIdentifier
        hasLocation = asset.location != nil
        isVideo = asset.mediaType == .video
        duration = asset.duration
    }
}
