import Foundation
import Observation
import Photos

enum PhotosAccess: Equatable {
    case notDetermined
    case restricted
    case denied
    case limited
    case full
}

/// Everything PhotoKit (spec §4.1). Fetches are `nonisolated static` so callers can run them
/// off the main actor; the observable part is just the authorization state.
@MainActor
@Observable
final class PhotoLibraryService {
    private(set) var access: PhotosAccess

    init() {
        access = Self.currentAccess()
    }

    static func currentAccess() -> PhotosAccess {
        map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func refreshAccess() {
        access = Self.currentAccess()
    }

    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        access = Self.map(status)
    }

    private static func map(_ status: PHAuthorizationStatus) -> PhotosAccess {
        switch status {
        case .authorized: return .full
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    // MARK: Fetching

    /// Images only, creation date in [start, end), user library, hidden excluded,
    /// every burst frame included so bursts can be grouped.
    nonisolated static func fetchOptions(start: Date, end: Date, mediaType: PHAssetMediaType = .image) -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
            mediaType.rawValue, start as NSDate, end as NSDate
        )
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        options.includeAllBurstAssets = true
        options.includeHiddenAssets = false
        options.includeAssetSourceTypes = [.typeUserLibrary]
        return options
    }

    nonisolated static func fetchAssets(start: Date, end: Date, mediaType: PHAssetMediaType = .image) -> PHFetchResult<PHAsset> {
        PHAsset.fetchAssets(with: fetchOptions(start: start, end: end, mediaType: mediaType))
    }

    nonisolated static func assetCount(start: Date, end: Date, mediaType: PHAssetMediaType = .image) -> Int {
        fetchAssets(start: start, end: end, mediaType: mediaType).count
    }

    /// Sendable snapshots of every asset in the range, in creation-date order.
    nonisolated static func assetInfos(start: Date, end: Date, mediaType: PHAssetMediaType = .image) -> [AssetInfo] {
        let result = fetchAssets(start: start, end: end, mediaType: mediaType)
        var infos: [AssetInfo] = []
        infos.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in infos.append(AssetInfo(asset)) }
        return infos
    }

    nonisolated static func asset(withID id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// localIdentifiers of every asset in the user album with this title (WhatsApp's
    /// "Save to Camera Roll" album). Empty when no such album exists; the EXIF rule still
    /// catches received JPEGs, so a missing album is fine.
    nonisolated static func albumAssetIDs(titled title: String) -> Set<String> {
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        var ids = Set<String>()
        albums.enumerateObjects { collection, _, _ in
            guard collection.localizedTitle == title else { return }
            PHAsset.fetchAssets(in: collection, options: nil).enumerateObjects { asset, _, _ in
                ids.insert(asset.localIdentifier)
            }
        }
        return ids
    }
}
