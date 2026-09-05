import Foundation
import PhotoCullCore

enum ExtractionMode: Sendable {
    /// Every signal in spec §4; the result goes to the cache.
    case full
    /// Only the feature print, for assets whose scalar metrics are already cached. Prints are
    /// never persisted, so grouping a re-scan still needs them in memory.
    case featurePrintOnly
}

struct TimingStat: Sendable, Equatable {
    var count = 0
    var totalMs = 0.0
    var averageMs: Double { count == 0 ? 0 : totalMs / Double(count) }
}

enum ExtractionError: Error, LocalizedError {
    case assetMissing
    case imageUnavailable

    var errorDescription: String? {
        switch self {
        case .assetMissing: return "Asset no longer exists"
        case .imageUnavailable: return "Image could not be loaded"
        }
    }
}

/// Turns one asset into `AssetMetrics` (spec §4) and keeps its feature print in memory so
/// the grouper can ask for distances. Only the implementation may import Vision;
/// PhotoCullCore never does.
protocol FeatureExtracting: AnyObject, Sendable {
    /// Returns nil for `.featurePrintOnly` (the caller already has cached metrics).
    func extract(_ asset: AssetInfo, mode: ExtractionMode, inWhatsAppAlbum: Bool, thresholds: Thresholds) async throws -> AssetMetrics?

    /// Feature-print distance between two analysed assets in this scan; nil when either has no print.
    func distance(_ a: String, _ b: String) -> Float?

    /// Drop all feature prints (start of a scan).
    func resetPrints()

    var timingStats: [String: TimingStat] { get }
}
