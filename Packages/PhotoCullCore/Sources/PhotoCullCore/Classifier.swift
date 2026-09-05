import Foundation

public struct Classification: Codable, Equatable, Sendable {
    public let category: AssetCategory
    /// Human-readable, non-empty. Shown in the UI and written to the audit log.
    public let reason: String
    public let defaultAction: CullAction
    /// Favorites: never a delete candidate, regardless of group overrides (safety rule 2).
    public let isProtected: Bool

    public init(category: AssetCategory, reason: String, defaultAction: CullAction, isProtected: Bool = false) {
        self.category = category
        self.reason = reason
        self.defaultAction = defaultAction
        self.isProtected = isProtected
    }

    public var isGroupable: Bool { category.isGroupable }
}

/// Spec §5.2. Rules run in order; the first match wins.
public struct Classifier: Sendable {
    public let thresholds: Thresholds

    public init(thresholds: Thresholds = .default) {
        self.thresholds = thresholds
    }

    public func classify(_ m: AssetMetrics) -> Classification {
        // 1. Favorites are personal and protected. They can still be a group keeper.
        if m.isFavorite {
            return Classification(category: .personal, reason: "Favorite", defaultAction: .keep, isProtected: true)
        }
        // 2. Screenshots.
        if m.isScreenshot {
            return Classification(category: .screenshot, reason: "Screenshot", defaultAction: .delete)
        }
        // 3. Received: in the WhatsApp album, or a JPEG/PNG with no camera EXIF.
        //    HEIC (hasCameraExif == nil) is never "received" by the EXIF rule.
        let strippedExif = m.isJPEGOrPNG && m.hasCameraExif == false
        if m.inWhatsAppAlbum || strippedExif {
            let textHeavy = (m.textCharCount ?? 0) >= thresholds.textHeavyCharCount
            if m.isUtility == true || textHeavy {
                return Classification(
                    category: .receivedUtility,
                    reason: "Received image with text/document content",
                    defaultAction: .delete
                )
            }
            return Classification(
                category: .receivedPhoto,
                reason: "Received photo (no camera data)",
                defaultAction: .keep
            )
        }
        // 4. Camera-originated utility shots: documents, receipts, whiteboards.
        if m.isUtility == true {
            return Classification(
                category: .utility,
                reason: "Photo of document/receipt/whiteboard",
                defaultAction: .delete
            )
        }
        // 5. Everything else.
        return Classification(category: .personal, reason: "Personal photo", defaultAction: .keep)
    }
}
