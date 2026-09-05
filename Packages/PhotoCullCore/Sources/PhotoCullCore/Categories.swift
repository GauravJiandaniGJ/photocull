import Foundation

public enum AssetCategory: String, Codable, Sendable, CaseIterable {
    case personal
    case screenshot
    case receivedPhoto
    case receivedUtility
    case utility
    // Videos (milestone 7)
    case personalVideo
    case receivedVideo
    case screenRecording

    /// Personal and received media go through similarity grouping; clutter does not.
    public var isGroupable: Bool {
        switch self {
        case .personal, .receivedPhoto, .personalVideo, .receivedVideo: return true
        default: return false
        }
    }

    public var isVideo: Bool {
        switch self {
        case .personalVideo, .receivedVideo, .screenRecording: return true
        default: return false
        }
    }
}

public enum CullAction: String, Codable, Sendable {
    case keep
    case delete
}

public enum DecisionSource: String, Codable, Sendable {
    case auto
    case user
    case claude
}

public enum GroupKind: String, Codable, Sendable {
    case burst
    case similar
    /// Byte-for-byte look-alikes: same duration, resolution and file size (videos).
    case duplicate
}
