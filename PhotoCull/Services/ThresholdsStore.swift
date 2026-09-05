import Foundation
import Observation
import PhotoCullCore

/// The live Thresholds, persisted as JSON in UserDefaults. Each scan snapshots a copy onto
/// its ScanSession so old decisions stay explainable after the user tunes a value.
@MainActor
@Observable
final class ThresholdsStore {
    private static let key = "thresholds.v1"

    var thresholds: Thresholds {
        didSet {
            save()
            if let change = Self.describeChange(from: oldValue, to: thresholds) {
                AppLog.info(.settings, change)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? JSONDecoder().decode(Thresholds.self, from: data) {
            thresholds = stored
        } else {
            thresholds = .default
        }
    }

    func reset() {
        thresholds = .default
    }

    private let defaults: UserDefaults

    private static func describeChange(from a: Thresholds, to b: Thresholds) -> String? {
        var parts: [String] = []
        if a.similarityDistanceMax != b.similarityDistanceMax { parts.append("similarity \(a.similarityDistanceMax) → \(b.similarityDistanceMax)") }
        if a.groupTimeGapSeconds != b.groupTimeGapSeconds { parts.append("time gap \(Int(a.groupTimeGapSeconds)) → \(Int(b.groupTimeGapSeconds))s") }
        if a.tieBreakMargin != b.tieBreakMargin { parts.append("tie margin \(a.tieBreakMargin) → \(b.tieBreakMargin)") }
        if a.minFaceAreaRatio != b.minFaceAreaRatio { parts.append("min face area \(a.minFaceAreaRatio) → \(b.minFaceAreaRatio)") }
        if a.textHeavyCharCount != b.textHeavyCharCount { parts.append("text-heavy chars \(a.textHeavyCharCount) → \(b.textHeavyCharCount)") }
        if a.whatsAppAlbumName != b.whatsAppAlbumName { parts.append("WhatsApp album “\(a.whatsAppAlbumName)” → “\(b.whatsAppAlbumName)”") }
        if a.visionLongEdge != b.visionLongEdge { parts.append("vision edge \(a.visionLongEdge) → \(b.visionLongEdge)") }
        if a.claudeImageLongEdge != b.claudeImageLongEdge { parts.append("Claude image edge \(a.claudeImageLongEdge) → \(b.claudeImageLongEdge)") }
        if a.claudeMaxImagesPerGroup != b.claudeMaxImagesPerGroup { parts.append("Claude max images \(a.claudeMaxImagesPerGroup) → \(b.claudeMaxImagesPerGroup)") }
        if a.videoSimilarityDistanceMax != b.videoSimilarityDistanceMax { parts.append("video similarity \(a.videoSimilarityDistanceMax) → \(b.videoSimilarityDistanceMax)") }
        if a.videoDurationTolerance != b.videoDurationTolerance { parts.append("video duration tolerance \(a.videoDurationTolerance) → \(b.videoDurationTolerance)") }
        return parts.isEmpty ? nil : "Thresholds changed: " + parts.joined(separator: ", ")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(thresholds) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
