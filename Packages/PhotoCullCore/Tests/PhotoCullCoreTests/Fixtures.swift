import CoreGraphics
import Foundation
@testable import PhotoCullCore

let t0 = Date(timeIntervalSince1970: 1_700_000_000)

func asset(
    _ id: String,
    at seconds: TimeInterval = 0,
    pixels: Int = 12_000_000,
    screenshot: Bool = false,
    favorite: Bool = false,
    whatsApp: Bool = false,
    uti: String = "public.heic",
    exif: Bool? = nil,
    burst: String? = nil,
    aesthetics: Float? = 0,
    utility: Bool? = false,
    faces: [FaceMetrics] = [],
    text: Int? = nil
) -> AssetMetrics {
    AssetMetrics(
        id: id,
        creationDate: t0.addingTimeInterval(seconds),
        pixelCount: pixels,
        isScreenshot: screenshot,
        isFavorite: favorite,
        inWhatsAppAlbum: whatsApp,
        fileUTI: uti,
        hasCameraExif: exif,
        burstIdentifier: burst,
        aestheticsScore: aesthetics,
        isUtility: utility,
        faces: faces,
        textCharCount: text
    )
}

func face(quality: Float = 0.8, eyesOpen: Bool = true, smiling: Bool = false, size: CGFloat = 0.2) -> FaceMetrics {
    FaceMetrics(
        bbox: CGRect(x: 0.4, y: 0.4, width: size, height: size),
        captureQuality: quality,
        leftEyeOpen: eyesOpen,
        rightEyeOpen: eyesOpen,
        smiling: smiling
    )
}

/// Distance table for tests: symmetric lookup, nil for unknown pairs.
func distances(_ pairs: [(String, String, Float)]) -> (String, String) -> Float? {
    var table: [String: Float] = [:]
    for (a, b, d) in pairs {
        table["\(a)|\(b)"] = d
        table["\(b)|\(a)"] = d
    }
    return { a, b in table["\(a)|\(b)"] }
}

/// Every pair is at the given distance.
func allPairs(_ d: Float) -> (String, String) -> Float? {
    { _, _ in d }
}
