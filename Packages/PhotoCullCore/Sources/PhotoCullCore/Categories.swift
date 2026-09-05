import Foundation

public enum AssetCategory: String, Codable, Sendable, CaseIterable {
    case personal
    case screenshot
    case receivedPhoto
    case receivedUtility
    case utility

    /// Personal and received photos go through similarity grouping; clutter does not.
    public var isGroupable: Bool { self == .personal || self == .receivedPhoto }
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
}
