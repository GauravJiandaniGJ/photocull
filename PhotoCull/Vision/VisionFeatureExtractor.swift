import CoreImage
import Foundation
import ImageIO
import PhotoCullCore
import Photos
import UIKit
import Vision

/// Spec §4.2–4.4 on the iOS 18 Swift Vision API plus CIDetector for eyes/smile.
final class VisionFeatureExtractor: FeatureExtracting, @unchecked Sendable {
    private let prints = Locked<[String: FeaturePrintObservation]>([:])
    private let timings = Locked<[String: TimingStat]>([:])
    private let faceDetector: CIDetector?
    private let detectorLock = NSLock()

    /// Faces from CIDetector and Vision are matched when their boxes overlap at least this much.
    private static let faceMatchIoU: CGFloat = 0.3

    init() {
        faceDetector = CIDetector(ofType: CIDetectorTypeFace, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
    }

    func resetPrints() {
        prints.with { $0.removeAll() }
        timings.with { $0.removeAll() }
    }

    func distance(_ a: String, _ b: String) -> Float? {
        let pair: (FeaturePrintObservation, FeaturePrintObservation)? = prints.with { table in
            guard let x = table[a], let y = table[b] else { return nil }
            return (x, y)
        }
        guard let (x, y) = pair, let d = try? x.distance(to: y) else { return nil }
        return Float(d)
    }

    var timingStats: [String: TimingStat] { timings.current }

    var printCount: Int { prints.with { $0.count } }

    // MARK: Extraction

    func extract(_ info: AssetInfo, mode: ExtractionMode, inWhatsAppAlbum: Bool, thresholds: Thresholds) async throws -> AssetMetrics? {
        try Task.checkCancellation()
        guard let asset = PhotoLibraryService.asset(withID: info.id) else { throw ExtractionError.assetMissing }

        let cgImage = try await timed("image") { () throws -> CGImage in
            guard let image = await PhotoImageLoader.analysisImage(for: asset, longEdge: CGFloat(thresholds.visionLongEdge)),
                  let cg = PhotoImageLoader.uprightCGImage(image)
            else { throw ExtractionError.imageUnavailable }
            return cg
        }
        let handler = ImageRequestHandler(cgImage)

        let print = try await timed("featurePrint") {
            try await handler.perform(GenerateImageFeaturePrintRequest())
        }
        prints.with { $0[info.id] = print }
        if mode == .featurePrintOnly { return nil }

        let fileUTI = PHAssetResource.assetResources(for: asset).first?.uniformTypeIdentifier ?? "public.heic"
        let isJPEGOrPNG: Bool
        switch fileUTI.lowercased() {
        case "public.jpeg", "public.jpg", "public.png": isJPEGOrPNG = true
        default: isJPEGOrPNG = false
        }

        let aesthetics = try? await timed("aesthetics") {
            try await handler.perform(CalculateImageAestheticsScoresRequest())
        }

        let faceObservations = (try? await timed("faceQuality") {
            try await handler.perform(DetectFaceCaptureQualityRequest())
        }) ?? []
        var faces = faceObservations.map { face in
            FaceMetrics(
                bbox: face.boundingBox.cgRect,
                captureQuality: face.captureQuality?.score ?? 0,
                leftEyeOpen: true,
                rightEyeOpen: true,
                smiling: false
            )
        }
        if !faces.isEmpty {
            faces = timedSync("eyesSmile") { applyEyesAndSmile(to: faces, cgImage: cgImage) }
        }

        var hasCameraExif: Bool? = nil
        if isJPEGOrPNG {
            hasCameraExif = await timed("exif") { await probeCameraExif(asset) }
        }

        // OCR gating (§4.4): only when it can change a decision.
        let isReceived = inWhatsAppAlbum || (isJPEGOrPNG && hasCameraExif == false)
        let isPNG = fileUTI.lowercased() == "public.png"
        var textCharCount: Int? = nil
        if aesthetics?.isUtility == true || faces.isEmpty || isReceived || isPNG {
            textCharCount = try? await timed("text") { () throws -> Int in
                var request = RecognizeTextRequest()
                request.recognitionLevel = .fast
                let observations = try await handler.perform(request)
                return observations.reduce(0) { $0 + ($1.topCandidates(1).first?.string.count ?? 0) }
            }
        }

        return AssetMetrics(
            id: info.id,
            creationDate: info.creationDate,
            pixelCount: info.pixelCount,
            isScreenshot: info.isScreenshot,
            isFavorite: info.isFavorite,
            inWhatsAppAlbum: inWhatsAppAlbum,
            fileUTI: fileUTI,
            hasCameraExif: hasCameraExif,
            burstIdentifier: info.burstIdentifier,
            aestheticsScore: aesthetics?.overallScore,
            isUtility: aesthetics?.isUtility,
            faces: faces,
            textCharCount: textCharCount
        )
    }

    // MARK: Eyes / smile via CIDetector, matched to Vision faces by IoU

    private func applyEyesAndSmile(to faces: [FaceMetrics], cgImage: CGImage) -> [FaceMetrics] {
        guard let detector = faceDetector else { return faces }
        let ciImage = CIImage(cgImage: cgImage)
        detectorLock.lock()
        let features = detector.features(in: ciImage, options: [CIDetectorSmile: true, CIDetectorEyeBlink: true]).compactMap { $0 as? CIFaceFeature }
        detectorLock.unlock()
        guard !features.isEmpty else { return faces }

        let width = CGFloat(cgImage.width), height = CGFloat(cgImage.height)
        let normalized: [(rect: CGRect, feature: CIFaceFeature)] = features.map { f in
            (CGRect(x: f.bounds.minX / width, y: f.bounds.minY / height, width: f.bounds.width / width, height: f.bounds.height / height), f)
        }
        return faces.map { face in
            guard let best = normalized.max(by: { Self.iou($0.rect, face.bbox) < Self.iou($1.rect, face.bbox) }),
                  Self.iou(best.rect, face.bbox) >= Self.faceMatchIoU
            else { return face }
            var updated = face
            updated.leftEyeOpen = !best.feature.leftEyeClosed
            updated.rightEyeOpen = !best.feature.rightEyeClosed
            updated.smiling = best.feature.hasSmile
            return updated
        }
    }

    static func iou(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let inter = a.intersection(b)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return 0 }
        let interArea = inter.width * inter.height
        let union = a.width * a.height + b.width * b.height - interArea
        return union > 0 ? interArea / union : 0
    }

    // MARK: EXIF probe (JPEG/PNG only, §4.2)

    private func probeCameraExif(_ asset: PHAsset) async -> Bool? {
        guard let data = await PhotoImageLoader.imageData(for: asset),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return nil }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let hasMakeOrModel = tiff?[kCGImagePropertyTIFFMake] != nil || tiff?[kCGImagePropertyTIFFModel] != nil
        let hasLens = exif?[kCGImagePropertyExifLensModel] != nil || exif?[kCGImagePropertyExifFNumber] != nil
        return hasMakeOrModel || hasLens
    }

    // MARK: Timing

    private func timed<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T {
        let start = ContinuousClock.now
        defer { record(name, start.duration(to: .now)) }
        return try await body()
    }

    private func timedSync<T>(_ name: String, _ body: () -> T) -> T {
        let start = ContinuousClock.now
        defer { record(name, start.duration(to: .now)) }
        return body()
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
