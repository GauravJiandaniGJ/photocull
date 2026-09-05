import Foundation

/// Every tunable in one Codable struct (spec §5.1). Editable in Settings; a snapshot is
/// stored on each ScanSession so past decisions can be explained with the values that made them.
public struct Thresholds: Codable, Equatable, Sendable {
    /// New time bucket when the gap to the previous photo exceeds this.
    public var groupTimeGapSeconds: TimeInterval
    /// Feature-print distance at or below which two photos are "the same shot".
    /// The spec's 0.6 over-groups badly on iOS 26 Vision; 0.05 was calibrated on a real
    /// library with Debug → Calibrate and keeps only near-identical frames.
    public var similarityDistanceMax: Float
    /// Top-two score gap below which the group is a tie.
    public var tieBreakMargin: Float
    /// Ignore faces smaller than this fraction of the frame for eyes/smile.
    public var minFaceAreaRatio: Float
    /// A received image with this many recognised characters is a forward / chat screenshot.
    public var textHeavyCharCount: Int
    /// Album title created by WhatsApp's "Save to Camera Roll".
    public var whatsAppAlbumName: String
    /// Long edge of the image handed to Vision.
    public var visionLongEdge: Int
    /// Long edge of the JPEGs sent to the Claude tie-breaker.
    public var claudeImageLongEdge: Int
    /// Cap on images per tie-breaker call.
    public var claudeMaxImagesPerGroup: Int

    public init(
        groupTimeGapSeconds: TimeInterval = 120,
        similarityDistanceMax: Float = 0.05,
        tieBreakMargin: Float = 0.05,
        minFaceAreaRatio: Float = 0.01,
        textHeavyCharCount: Int = 80,
        whatsAppAlbumName: String = "WhatsApp",
        visionLongEdge: Int = 1024,
        claudeImageLongEdge: Int = 768,
        claudeMaxImagesPerGroup: Int = 6
    ) {
        self.groupTimeGapSeconds = groupTimeGapSeconds
        self.similarityDistanceMax = similarityDistanceMax
        self.tieBreakMargin = tieBreakMargin
        self.minFaceAreaRatio = minFaceAreaRatio
        self.textHeavyCharCount = textHeavyCharCount
        self.whatsAppAlbumName = whatsAppAlbumName
        self.visionLongEdge = visionLongEdge
        self.claudeImageLongEdge = claudeImageLongEdge
        self.claudeMaxImagesPerGroup = claudeMaxImagesPerGroup
    }

    public static let `default` = Thresholds()

    // Tolerant decoding: a snapshot saved before a key existed falls back to the default,
    // so adding a threshold later never invalidates stored sessions.
    private enum CodingKeys: String, CodingKey {
        case groupTimeGapSeconds, similarityDistanceMax, tieBreakMargin, minFaceAreaRatio
        case textHeavyCharCount, whatsAppAlbumName, visionLongEdge, claudeImageLongEdge, claudeMaxImagesPerGroup
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Thresholds.default
        groupTimeGapSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .groupTimeGapSeconds) ?? d.groupTimeGapSeconds
        similarityDistanceMax = try c.decodeIfPresent(Float.self, forKey: .similarityDistanceMax) ?? d.similarityDistanceMax
        tieBreakMargin = try c.decodeIfPresent(Float.self, forKey: .tieBreakMargin) ?? d.tieBreakMargin
        minFaceAreaRatio = try c.decodeIfPresent(Float.self, forKey: .minFaceAreaRatio) ?? d.minFaceAreaRatio
        textHeavyCharCount = try c.decodeIfPresent(Int.self, forKey: .textHeavyCharCount) ?? d.textHeavyCharCount
        whatsAppAlbumName = try c.decodeIfPresent(String.self, forKey: .whatsAppAlbumName) ?? d.whatsAppAlbumName
        visionLongEdge = try c.decodeIfPresent(Int.self, forKey: .visionLongEdge) ?? d.visionLongEdge
        claudeImageLongEdge = try c.decodeIfPresent(Int.self, forKey: .claudeImageLongEdge) ?? d.claudeImageLongEdge
        claudeMaxImagesPerGroup = try c.decodeIfPresent(Int.self, forKey: .claudeMaxImagesPerGroup) ?? d.claudeMaxImagesPerGroup
    }
}
