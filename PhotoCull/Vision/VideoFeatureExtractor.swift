import AVFoundation
import Foundation
import PhotoCullCore
import Photos
import Vision

/// Milestone 7: container facts plus feature prints of a few sampled frames per video.
/// Only videos that are on the phone are analysed (no iCloud download): a video that is not
/// local takes no space here, and downloading it just to judge it would be the wrong trade.
final class VideoFeatureExtractor: @unchecked Sendable {
    private let prints = Locked<[String: [FeaturePrintObservation]]>([:])
    private let timings = Locked<[String: TimingStat]>([:])

    /// iPhone screen sizes in pixels, portrait. A video of exactly this size with no camera
    /// metadata is treated as a screen recording.
    static let screenSizes: Set<String> = [
        "640x1136", "750x1334", "828x1792", "1080x1920", "1080x2340", "1125x2436", "1170x2532",
        "1179x2556", "1206x2622", "1242x2208", "1242x2688", "1260x2736", "1284x2778", "1290x2796", "1320x2868",
    ]

    func resetPrints() {
        prints.with { $0.removeAll() }
        timings.with { $0.removeAll() }
    }

    var timingStats: [String: TimingStat] { timings.current }

    /// Mean distance over aligned sampled frames; nil when either video has no frames.
    func distance(_ a: String, _ b: String) -> Float? {
        let pair: ([FeaturePrintObservation], [FeaturePrintObservation])? = prints.with { table in
            guard let x = table[a], let y = table[b], !x.isEmpty, !y.isEmpty else { return nil }
            return (x, y)
        }
        guard let (x, y) = pair else { return nil }
        let n = min(x.count, y.count)
        var total: Double = 0
        for i in 0..<n {
            guard let d = try? x[i].distance(to: y[i]) else { return nil }
            total += d
        }
        return Float(total / Double(n))
    }

    func extract(_ info: AssetInfo, mode: ExtractionMode, inWhatsAppAlbum: Bool, thresholds: Thresholds) async throws -> VideoMetrics? {
        try Task.checkCancellation()
        guard let asset = PhotoLibraryService.asset(withID: info.id) else { throw ExtractionError.assetMissing }
        let resources = PHAssetResource.assetResources(for: asset)
        let fileUTI = (resources.first { $0.type == .video } ?? resources.first)?.uniformTypeIdentifier ?? "com.apple.quicktime-movie"

        // Timed inline: AVAsset is not Sendable, so it must not cross a closure boundary.
        let loadStart = ContinuousClock.now
        let avAsset = await Self.localAVAsset(for: asset)
        record("videoLoad", loadStart.duration(to: .now))
        var fileSize: Int64 = 0
        var hasCamera: Bool? = nil
        var sampled = false

        if let avAsset {
            if let url = (avAsset as? AVURLAsset)?.url,
               let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                fileSize = Int64(size)
            }
            if let items = try? await avAsset.load(.metadata) {
                let names = items.compactMap { $0.commonKey?.rawValue.lowercased() } + items.compactMap { $0.identifier?.rawValue.lowercased() }
                hasCamera = names.contains { $0.hasSuffix("make") || $0.hasSuffix("model") || $0.contains("quicktime.make") || $0.contains("quicktime.model") }
            }
            let frameStart = ContinuousClock.now
            let observations = await Self.framePrints(for: avAsset, duration: info.duration)
            record("videoFrames", frameStart.duration(to: .now))
            sampled = !observations.isEmpty
            if sampled { prints.with { $0[info.id] = observations } }
        }
        if mode == .featurePrintOnly { return nil }

        let w = info.pixelWidth, h = info.pixelHeight
        let screenLike = hasCamera != true && Self.screenSizes.contains("\(min(w, h))x\(max(w, h))")
        return VideoMetrics(
            id: info.id,
            creationDate: info.creationDate,
            duration: info.duration,
            pixelWidth: w,
            pixelHeight: h,
            fileSizeBytes: fileSize,
            isFavorite: info.isFavorite,
            inWhatsAppAlbum: inWhatsAppAlbum,
            fileUTI: fileUTI,
            hasCameraMetadata: hasCamera,
            looksLikeScreenRecording: screenLike,
            framesSampled: sampled
        )
    }

    // MARK: Helpers

    private static func localAVAsset(for asset: PHAsset) async -> AVAsset? {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.version = .current
        let once = Locked(false)
        return await withCheckedContinuation { (continuation: CheckedContinuation<AVAsset?, Never>) in
            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, _ in
                if once.with({ done -> Bool in defer { done = true }; return !done }) {
                    continuation.resume(returning: avAsset)
                }
            }
        }
    }

    /// Feature prints at 10 %, 50 % and 90 % of the duration (just the middle for very short clips).
    private static func framePrints(for avAsset: AVAsset, duration: Double) async -> [FeaturePrintObservation] {
        let generator = AVAssetImageGenerator(asset: avAsset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)
        let fractions: [Double] = duration < 2 ? [0.5] : [0.1, 0.5, 0.9]
        var out: [FeaturePrintObservation] = []
        for fraction in fractions {
            let time = CMTime(seconds: max(0, duration * fraction), preferredTimescale: 600)
            guard let frame = try? await generator.image(at: time) else { continue }
            let handler = ImageRequestHandler(frame.image)
            if let print = try? await handler.perform(GenerateImageFeaturePrintRequest()) {
                out.append(print)
            }
        }
        return out
    }

    private func record(_ name: String, _ duration: Duration) {
        let ms = Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
        timings.with { stats in
            var stat = stats[name] ?? TimingStat()
            stat.count += 1
            stat.totalMs += ms
            stats[name] = stat
        }
    }
}
