import CoreGraphics
import Foundation

/// One detected face. `bbox` is normalised to the image (0…1 on both axes).
public struct FaceMetrics: Codable, Equatable, Sendable {
    public var bbox: CGRect
    public var captureQuality: Float
    public var leftEyeOpen: Bool
    public var rightEyeOpen: Bool
    public var smiling: Bool

    public init(bbox: CGRect, captureQuality: Float, leftEyeOpen: Bool, rightEyeOpen: Bool, smiling: Bool) {
        self.bbox = bbox
        self.captureQuality = captureQuality
        self.leftEyeOpen = leftEyeOpen
        self.rightEyeOpen = rightEyeOpen
        self.smiling = smiling
    }

    /// Fraction of the frame the face covers.
    public var areaRatio: Float { Float(bbox.size.width * bbox.size.height) }
    public var bothEyesOpen: Bool { leftEyeOpen && rightEyeOpen }
}

/// Everything the app target extracts for one asset (spec §4). Persisted as JSON in the
/// analysis cache. Feature prints are deliberately NOT here — they live in memory for one scan.
public struct AssetMetrics: Codable, Equatable, Sendable {
    public var id: String
    public var creationDate: Date
    public var pixelCount: Int
    public var isScreenshot: Bool
    public var isFavorite: Bool
    public var inWhatsAppAlbum: Bool
    public var fileUTI: String
    /// nil = not probed (HEIC is assumed camera-originated).
    public var hasCameraExif: Bool?
    public var burstIdentifier: String?
    /// −1…1 from Vision's aesthetics request; nil if the request failed.
    public var aestheticsScore: Float?
    /// Vision's "utility image" flag: screenshots, receipts, documents, whiteboards.
    public var isUtility: Bool?
    public var faces: [FaceMetrics]
    /// Recognised character count; nil when OCR was skipped by the gating rule.
    public var textCharCount: Int?

    public init(
        id: String,
        creationDate: Date,
        pixelCount: Int,
        isScreenshot: Bool = false,
        isFavorite: Bool = false,
        inWhatsAppAlbum: Bool = false,
        fileUTI: String = "public.heic",
        hasCameraExif: Bool? = nil,
        burstIdentifier: String? = nil,
        aestheticsScore: Float? = nil,
        isUtility: Bool? = nil,
        faces: [FaceMetrics] = [],
        textCharCount: Int? = nil
    ) {
        self.id = id
        self.creationDate = creationDate
        self.pixelCount = pixelCount
        self.isScreenshot = isScreenshot
        self.isFavorite = isFavorite
        self.inWhatsAppAlbum = inWhatsAppAlbum
        self.fileUTI = fileUTI
        self.hasCameraExif = hasCameraExif
        self.burstIdentifier = burstIdentifier
        self.aestheticsScore = aestheticsScore
        self.isUtility = isUtility
        self.faces = faces
        self.textCharCount = textCharCount
    }

    /// JPEG/PNG are the formats messaging apps and browsers save; HEIC is camera-originated.
    public var isJPEGOrPNG: Bool {
        switch fileUTI.lowercased() {
        case "public.jpeg", "public.jpg", "public.png": return true
        default: return false
        }
    }
}
