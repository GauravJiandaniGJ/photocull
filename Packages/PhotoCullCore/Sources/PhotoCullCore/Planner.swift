import Foundation

/// One proposed decision per scanned asset. The app persists these as SwiftData `Decision`s.
public struct ProposedDecision: Codable, Equatable, Sendable {
    public let assetID: String
    public let action: CullAction
    public let source: DecisionSource
    public let reason: String
    /// Index into `ScanPlan.groups`, when the asset belongs to a group.
    public let groupIndex: Int?
    public let category: AssetCategory
}

public struct ScanPlan: Equatable, Sendable {
    public let classifications: [String: Classification]
    public let groups: [ScoredGroup]
    /// Deterministic order: creation date, then id.
    public let decisions: [ProposedDecision]

    public var deleteCandidateIDs: [String] { decisions.filter { $0.action == .delete }.map(\.assetID) }
}

/// The whole pure pipeline for one scan: classify → group → score → decide (spec §3 data flow).
/// Same metrics in, same plan out, regardless of input order (safety rule 6).
public struct Planner: Sendable {
    public let thresholds: Thresholds
    public let classifier: Classifier
    public let grouper: Grouper
    public let scorer: Scorer

    public init(thresholds: Thresholds = .default) {
        self.thresholds = thresholds
        self.classifier = Classifier(thresholds: thresholds)
        self.grouper = Grouper(thresholds: thresholds)
        self.scorer = Scorer(thresholds: thresholds)
    }

    public func plan(metrics: [AssetMetrics], distance: (String, String) -> Float?) -> ScanPlan {
        let ordered = metrics.sorted { a, b in
            a.creationDate != b.creationDate ? a.creationDate < b.creationDate : a.id < b.id
        }
        let byID = Dictionary(uniqueKeysWithValues: ordered.map { ($0.id, $0) })

        var classifications: [String: Classification] = [:]
        for m in ordered { classifications[m.id] = classifier.classify(m) }

        let candidates = ordered
            .filter { classifications[$0.id]?.isGroupable == true }
            .map(GroupingCandidate.init)
        let groups = grouper
            .groups(for: candidates, distance: distance)
            .map { scorer.score(group: $0, metrics: byID) }

        var groupIndexByAsset: [String: Int] = [:]
        for (i, g) in groups.enumerated() {
            for id in g.memberIDs { groupIndexByAsset[id] = i }
        }

        let decisions: [ProposedDecision] = ordered.map { m in
            let c = classifications[m.id]!
            if let gi = groupIndexByAsset[m.id] {
                let g = groups[gi]
                let reason = g.reasons[m.id] ?? "Group member"
                if m.id == g.keeperID {
                    return ProposedDecision(assetID: m.id, action: .keep, source: .auto, reason: reason, groupIndex: gi, category: c.category)
                }
                if c.isProtected {
                    return ProposedDecision(assetID: m.id, action: .keep, source: .auto, reason: "Favorite (protected)", groupIndex: gi, category: c.category)
                }
                return ProposedDecision(assetID: m.id, action: .delete, source: .auto, reason: reason, groupIndex: gi, category: c.category)
            }
            let action: CullAction = c.isProtected ? .keep : c.defaultAction
            return ProposedDecision(assetID: m.id, action: action, source: .auto, reason: c.reason, groupIndex: nil, category: c.category)
        }

        return ScanPlan(classifications: classifications, groups: groups, decisions: decisions)
    }
}
