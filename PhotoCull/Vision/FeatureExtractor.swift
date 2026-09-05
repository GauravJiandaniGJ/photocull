import Foundation
import PhotoCullCore
import Photos

/// Turns one PHAsset into `AssetMetrics` (spec §4) and keeps its feature print in memory so
/// the grouper can ask for distances. Implemented in milestone 1 with Vision + Core Image;
/// only this file and its implementation may import Vision — PhotoCullCore never does.
///
/// Contract for the implementation:
/// - One 1024px `CGImage` per asset, all requests run on it, released in an `autoreleasepool`.
/// - Feature prints are never persisted; they die with the scan.
/// - EXIF is probed only for JPEG/PNG; HEIC leaves `hasCameraExif == nil`.
/// - OCR runs only when `isUtility == true`, there are no faces, or the asset is received/PNG.
/// - If an iOS 18 Swift Vision request name does not compile, use the `VN`-prefixed legacy request.
protocol FeatureExtracting: AnyObject {
    func extract(_ asset: PHAsset, inWhatsAppAlbum: Bool, thresholds: Thresholds) async throws -> AssetMetrics

    /// Feature-print distance between two analysed assets in this scan; nil when either has no print.
    func distance(_ a: String, _ b: String) -> Float?
}
