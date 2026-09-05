import Foundation

/// Per-member score with the terms that produced it, so the UI can show a breakdown.
public struct MemberScore: Codable, Equatable, Sendable {
    public let assetID: String
    public let score: Float
    /// 0…1, mapped from Vision's −1…1 (0.5 when the request produced nothing).
    public let aesthetics: Float
    /// nil when no face passed the minimum-area filter.
    public let faceQuality: Float?
    public let eyesOpenFraction: Float?
    public let smileFraction: Float?
    /// 1 when the asset has the highest pixel count in its group, else 0.
    public let resolution: Float
    public let faceCount: Int
    public let closedEyesFaceCount: Int
    public let isFavorite: Bool

    public var hasFaces: Bool { faceCount > 0 }
}

public enum LocalTieBreak: String, Codable, Equatable, Sendable {
    case higherAesthetics
    case earlierDate
}

public struct ScoredGroup: Codable, Equatable, Sendable {
    public let kind: GroupKind
    /// Creation-date order, same order as `scores`.
    public let memberIDs: [String]
    public let scores: [MemberScore]
    public let keeperID: String
    /// True when at least one other member is within `tieBreakMargin` of the top score.
    public let isTie: Bool
    /// How a tie was resolved locally; nil when there was no tie or an external source chose.
    public let localTieBreak: LocalTieBreak?
    /// assetID → non-empty reason (safety rule 5).
    public let reasons: [String: String]

    public var loserIDs: [String] { memberIDs.filter { $0 != keeperID } }
    public func score(for id: String) -> MemberScore? { scores.first { $0.assetID == id } }
}

/// Spec §5.4.
public struct Scorer: Sendable {
    public let thresholds: Thresholds

    public init(thresholds: Thresholds = .default) {
        self.thresholds = thresholds
    }

    // MARK: Weights

    enum Weights {
        static let faceQuality: Float = 0.40
        static let aestheticsWithFaces: Float = 0.25
        static let eyesOpen: Float = 0.20
        static let smile: Float = 0.10
        static let resolutionWithFaces: Float = 0.05
        static let aestheticsNoFaces: Float = 0.90
        static let resolutionNoFaces: Float = 0.10
        static let favoriteBonus: Float = 1.0
    }

    // MARK: Per-member score

    public func score(_ m: AssetMetrics, maxPixelCount: Int) -> MemberScore {
        let aesthetics = ((m.aestheticsScore ?? 0) + 1) / 2
        let faces = m.faces.filter { $0.areaRatio >= thresholds.minFaceAreaRatio }
        let resolution: Float = m.pixelCount == maxPixelCount ? 1 : 0

        var faceQ: Float? = nil
        var eyes: Float? = nil
        var smile: Float? = nil
        var closed = 0
        if !faces.isEmpty {
            let qualities = faces.map(\.captureQuality)
            let mean = qualities.reduce(0, +) / Float(qualities.count)
            faceQ = 0.6 * mean + 0.4 * (qualities.min() ?? 0)
            closed = faces.filter { !$0.bothEyesOpen }.count
            eyes = Float(faces.count - closed) / Float(faces.count)
            smile = Float(faces.filter(\.smiling).count) / Float(faces.count)
        }

        var score: Float
        if let faceQ, let eyes, let smile {
            score = Weights.faceQuality * faceQ
                + Weights.aestheticsWithFaces * aesthetics
                + Weights.eyesOpen * eyes
                + Weights.smile * smile
                + Weights.resolutionWithFaces * resolution
        } else {
            score = Weights.aestheticsNoFaces * aesthetics + Weights.resolutionNoFaces * resolution
        }
        if m.isFavorite { score += Weights.favoriteBonus }

        return MemberScore(
            assetID: m.id,
            score: score,
            aesthetics: aesthetics,
            faceQuality: faceQ,
            eyesOpenFraction: eyes,
            smileFraction: smile,
            resolution: resolution,
            faceCount: faces.count,
            closedEyesFaceCount: closed,
            isFavorite: m.isFavorite
        )
    }

    // MARK: Group

    /// Scores every member, picks the keeper, flags ties and resolves them locally.
    /// The app may later replace the keeper (Claude or user) via `replacingKeeper`.
    public func score(group: ProposedGroup, metrics: [String: AssetMetrics]) -> ScoredGroup {
        let members = group.memberIDs.compactMap { metrics[$0] }
        precondition(members.count == group.memberIDs.count, "Every group member needs metrics")
        let maxPixels = members.map(\.pixelCount).max() ?? 0
        let scores = members.map { score($0, maxPixelCount: maxPixels) }
        let dates = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.creationDate) })

        let top = scores.map(\.score).max() ?? 0
        let tieSet = Self.tieSet(scores: scores, top: top, margin: thresholds.tieBreakMargin)
        let isTie = tieSet.count >= 2

        let keeper: MemberScore
        var method: LocalTieBreak? = nil
        if isTie {
            // Local tie-break: higher aesthetics, else earlier creation date, else id.
            let byAesthetics = tieSet.sorted { $0.aesthetics > $1.aesthetics }
            if byAesthetics[0].aesthetics > byAesthetics[1].aesthetics {
                keeper = byAesthetics[0]
                method = .higherAesthetics
            } else {
                let topAesthetics = byAesthetics[0].aesthetics
                keeper = tieSet
                    .filter { $0.aesthetics == topAesthetics }
                    .sorted { a, b in
                        let da = dates[a.assetID] ?? .distantPast, db = dates[b.assetID] ?? .distantPast
                        return da != db ? da < db : a.assetID < b.assetID
                    }[0]
                method = .earlierDate
            }
        } else {
            keeper = scores.first { $0.score == top }!
        }

        let reasons = reasons(scores: scores, keeperID: keeper.assetID, localTieBreak: method)
        return ScoredGroup(
            kind: group.kind,
            memberIDs: group.memberIDs,
            scores: scores,
            keeperID: keeper.assetID,
            isTie: isTie,
            localTieBreak: method,
            reasons: reasons
        )
    }

    /// Members whose score is within `margin` of the top (strict: a gap of exactly `margin` is not a tie).
    static func tieSet(scores: [MemberScore], top: Float, margin: Float) -> [MemberScore] {
        scores.filter { top - $0.score < margin }
    }

    /// Same group with a different keeper (chosen by Claude or the user). Reasons are rebuilt
    /// relative to the new keeper; `keeperReason` overrides the generated one when given.
    public func replacingKeeper(in g: ScoredGroup, with keeperID: String, keeperReason: String? = nil) -> ScoredGroup {
        precondition(g.memberIDs.contains(keeperID), "Keeper must be a member")
        var reasons = reasons(scores: g.scores, keeperID: keeperID, localTieBreak: nil)
        if let keeperReason, !keeperReason.isEmpty { reasons[keeperID] = keeperReason }
        return ScoredGroup(
            kind: g.kind,
            memberIDs: g.memberIDs,
            scores: g.scores,
            keeperID: keeperID,
            isTie: g.isTie,
            localTieBreak: nil,
            reasons: reasons
        )
    }

    // MARK: Reasons

    /// Reasons for every member relative to `keeperID`, from stored scores. Used by the app
    /// when an external tie-breaker (Claude) picks a keeper on an already-persisted group.
    public func reasons(for scores: [MemberScore], keeperID: String) -> [String: String] {
        reasons(scores: scores, keeperID: keeperID, localTieBreak: nil)
    }

    /// Members within `tieBreakMargin` of the top score, best first. Empty when `scores` is empty.
    public func tieCandidates(in scores: [MemberScore]) -> [MemberScore] {
        guard let top = scores.map(\.score).max() else { return [] }
        return Self.tieSet(scores: scores, top: top, margin: thresholds.tieBreakMargin).sorted { $0.score > $1.score }
    }

    private enum Term: String { case faceQuality, aesthetics, eyesOpen, smile, resolution }

    private func weightedTerms(_ s: MemberScore) -> [Term: Float] {
        if let fq = s.faceQuality, let eyes = s.eyesOpenFraction, let smile = s.smileFraction {
            return [
                .faceQuality: Weights.faceQuality * fq,
                .aesthetics: Weights.aestheticsWithFaces * s.aesthetics,
                .eyesOpen: Weights.eyesOpen * eyes,
                .smile: Weights.smile * smile,
                .resolution: Weights.resolutionWithFaces * s.resolution,
            ]
        }
        return [
            .aesthetics: Weights.aestheticsNoFaces * s.aesthetics,
            .resolution: Weights.resolutionNoFaces * s.resolution,
        ]
    }

    func reasons(scores: [MemberScore], keeperID: String, localTieBreak: LocalTieBreak?) -> [String: String] {
        guard let keeper = scores.first(where: { $0.assetID == keeperID }) else { return [:] }
        var out: [String: String] = [:]
        out[keeperID] = keeperReason(keeper, among: scores)
        for s in scores where s.assetID != keeperID {
            out[s.assetID] = loserReason(s, keeper: keeper, localTieBreak: localTieBreak)
        }
        return out
    }

    private func keeperReason(_ k: MemberScore, among scores: [MemberScore]) -> String {
        let n = scores.count
        var parts: [String] = []
        if k.isFavorite { parts.append("favorite") }
        if k.hasFaces {
            if k.eyesOpenFraction == 1 { parts.append("all eyes open") }
            let bestFaceQ = scores.compactMap(\.faceQuality).max()
            if let fq = k.faceQuality, fq == bestFaceQ { parts.append("sharpest faces") }
            if k.smileFraction == 1 { parts.append("everyone smiling") }
        }
        let bestAesthetics = scores.map(\.aesthetics).max()
        if k.aesthetics == bestAesthetics { parts.append(k.hasFaces ? "best composition" : "highest overall quality") }
        if parts.isEmpty { parts.append("highest overall score") }
        return "Best of \(n): " + parts.joined(separator: ", ")
    }

    private func loserReason(_ l: MemberScore, keeper k: MemberScore, localTieBreak: LocalTieBreak?) -> String {
        if k.isFavorite && !l.isFavorite { return "Keeper is a favorite" }

        let kt = weightedTerms(k), lt = weightedTerms(l)
        // Biggest losing term, comparing only terms both members have.
        let losses = kt.compactMap { term, kv -> (Term, Float)? in
            guard let lv = lt[term] else { return nil }
            return (term, kv - lv)
        }
        if let (term, gap) = losses.max(by: { $0.1 < $1.1 }), gap > 0 {
            switch term {
            case .eyesOpen:
                if l.closedEyesFaceCount > 0 {
                    return "\(l.closedEyesFaceCount) face\(l.closedEyesFaceCount == 1 ? "" : "s") with eyes closed"
                }
                return "Fewer eyes open"
            case .faceQuality:
                return String(format: "Lower face quality (%.2f vs %.2f)", l.faceQuality ?? 0, k.faceQuality ?? 0)
            case .aesthetics:
                return "Lower overall quality"
            case .smile:
                return "Fewer smiles"
            case .resolution:
                return "Lower resolution"
            }
        }
        if k.hasFaces != l.hasFaces {
            return k.hasFaces ? "Keeper has clearer faces" : "Lower overall score"
        }
        switch localTieBreak {
        case .higherAesthetics: return "Near-identical; keeper has slightly better composition"
        case .earlierDate: return "Near-identical; keeper was taken first"
        case nil: return "Near-identical to keeper"
        }
    }
}
