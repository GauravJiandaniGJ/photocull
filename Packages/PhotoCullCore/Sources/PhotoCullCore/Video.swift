import Foundation

// MARK: - Metrics

/// What the app extracts for one video (milestone 7). Frame feature prints stay in memory.
public struct VideoMetrics: Codable, Equatable, Sendable {
    public var id: String
    public var creationDate: Date
    public var duration: TimeInterval
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// 0 when unknown (e.g. the file is only in iCloud).
    public var fileSizeBytes: Int64
    public var isFavorite: Bool
    public var inWhatsAppAlbum: Bool
    public var fileUTI: String
    /// Camera make/model in the container metadata; nil when metadata could not be read.
    public var hasCameraMetadata: Bool?
    /// Frame size matches an iPhone screen and there is no camera metadata.
    public var looksLikeScreenRecording: Bool
    /// True when the file was local and frames could be sampled.
    public var framesSampled: Bool

    public init(
        id: String,
        creationDate: Date,
        duration: TimeInterval,
        pixelWidth: Int,
        pixelHeight: Int,
        fileSizeBytes: Int64 = 0,
        isFavorite: Bool = false,
        inWhatsAppAlbum: Bool = false,
        fileUTI: String = "com.apple.quicktime-movie",
        hasCameraMetadata: Bool? = nil,
        looksLikeScreenRecording: Bool = false,
        framesSampled: Bool = true
    ) {
        self.id = id
        self.creationDate = creationDate
        self.duration = duration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fileSizeBytes = fileSizeBytes
        self.isFavorite = isFavorite
        self.inWhatsAppAlbum = inWhatsAppAlbum
        self.fileUTI = fileUTI
        self.hasCameraMetadata = hasCameraMetadata
        self.looksLikeScreenRecording = looksLikeScreenRecording
        self.framesSampled = framesSampled
    }

    public var pixelCount: Int { pixelWidth * pixelHeight }
}

// MARK: - Classifier

/// Rules in order; first match wins.
public struct VideoClassifier: Sendable {
    public init() {}

    public func classify(_ v: VideoMetrics) -> Classification {
        if v.isFavorite {
            return Classification(category: .personalVideo, reason: "Favorite", defaultAction: .keep, isProtected: true)
        }
        if v.looksLikeScreenRecording && !v.inWhatsAppAlbum {
            return Classification(category: .screenRecording, reason: "Screen recording", defaultAction: .delete)
        }
        if v.inWhatsAppAlbum || v.hasCameraMetadata == false {
            return Classification(category: .receivedVideo, reason: "Received video (no camera data)", defaultAction: .keep)
        }
        return Classification(category: .personalVideo, reason: "Video", defaultAction: .keep)
    }
}

// MARK: - Grouper

/// Exact duplicates first (same duration, size and dimensions, any time apart), then
/// same-take similarity inside time buckets using sampled-frame distances.
public struct VideoGrouper: Sendable {
    public let thresholds: Thresholds

    public init(thresholds: Thresholds = .default) {
        self.thresholds = thresholds
    }

    public func groups(for videos: [VideoMetrics], distance: (String, String) -> Float?) -> [ProposedGroup] {
        let sorted = videos.sorted { a, b in
            a.creationDate != b.creationDate ? a.creationDate < b.creationDate : a.id < b.id
        }
        var result: [ProposedGroup] = []
        var claimed = Set<String>()

        // 1. Exact duplicates: identical container facts. Size 0 (unknown) never matches.
        var byKey: [String: [VideoMetrics]] = [:]
        for v in sorted where v.fileSizeBytes > 0 {
            let key = "\(Int((v.duration * 10).rounded()))|\(v.pixelWidth)x\(v.pixelHeight)|\(v.fileSizeBytes)"
            byKey[key, default: []].append(v)
        }
        for members in byKey.values where members.count >= 2 {
            result.append(ProposedGroup(kind: .duplicate, memberIDs: members.map(\.id)))
            claimed.formUnion(members.map(\.id))
        }

        // 2. Similar takes: time buckets + frame distance, gated on comparable duration.
        var photoStyle = thresholds
        photoStyle.similarityDistanceMax = thresholds.videoSimilarityDistanceMax
        let durations = Dictionary(sorted.map { ($0.id, $0.duration) }, uniquingKeysWith: { a, _ in a })
        let tolerance = Double(thresholds.videoDurationTolerance)
        let candidates = sorted.filter { !claimed.contains($0.id) }.map { GroupingCandidate(id: $0.id, creationDate: $0.creationDate) }
        let similar = Grouper(thresholds: photoStyle).groups(for: candidates) { a, b in
            guard let da = durations[a], let db = durations[b] else { return nil }
            let allowed = max(1.0, tolerance * max(da, db))
            guard abs(da - db) <= allowed else { return nil }
            return distance(a, b)
        }
        result.append(contentsOf: similar)

        let dates = Dictionary(sorted.map { ($0.id, $0.creationDate) }, uniquingKeysWith: { a, _ in a })
        return result.sorted { a, b in
            let da = dates[a.memberIDs[0]] ?? .distantPast, db = dates[b.memberIDs[0]] ?? .distantPast
            return da != db ? da < db : a.memberIDs[0] < b.memberIDs[0]
        }
    }
}

// MARK: - Scorer

/// Keeper = highest resolution, then largest file (bitrate), then longest; favorites always win.
public struct VideoScorer: Sendable {
    public let thresholds: Thresholds

    public init(thresholds: Thresholds = .default) {
        self.thresholds = thresholds
    }

    public func score(group: ProposedGroup, metrics: [String: VideoMetrics]) -> ScoredGroup {
        let members = group.memberIDs.compactMap { metrics[$0] }
        precondition(members.count == group.memberIDs.count, "Every group member needs metrics")
        let maxPixels = max(1, members.map(\.pixelCount).max() ?? 1)
        let maxSize = max(1, members.map(\.fileSizeBytes).max() ?? 1)
        let maxDuration = max(0.001, members.map(\.duration).max() ?? 0.001)

        let scores: [MemberScore] = members.map { v in
            var score = 0.6 * Float(v.pixelCount) / Float(maxPixels)
                + 0.3 * Float(Double(v.fileSizeBytes) / Double(maxSize))
                + 0.1 * Float(v.duration / maxDuration)
            if v.isFavorite { score += 1 }
            var s = MemberScore(
                assetID: v.id, score: score, aesthetics: 0, faceQuality: nil, eyesOpenFraction: nil, smileFraction: nil,
                resolution: v.pixelCount == maxPixels ? 1 : 0, faceCount: 0, closedEyesFaceCount: 0, isFavorite: v.isFavorite
            )
            s.duration = v.duration
            s.fileSizeBytes = v.fileSizeBytes
            s.pixelWidth = v.pixelWidth
            s.pixelHeight = v.pixelHeight
            return s
        }

        let top = scores.map(\.score).max() ?? 0
        let ties = scores.filter { top - $0.score < thresholds.tieBreakMargin }
        let isTie = ties.count >= 2
        let dates = Dictionary(members.map { ($0.id, $0.creationDate) }, uniquingKeysWith: { a, _ in a })
        let keeper = ties.sorted { a, b in
            if (a.fileSizeBytes ?? 0) != (b.fileSizeBytes ?? 0) { return (a.fileSizeBytes ?? 0) > (b.fileSizeBytes ?? 0) }
            let da = dates[a.assetID] ?? .distantPast, db = dates[b.assetID] ?? .distantPast
            return da != db ? da < db : a.assetID < b.assetID
        }[0]

        return ScoredGroup(
            kind: group.kind,
            memberIDs: group.memberIDs,
            scores: scores,
            keeperID: keeper.assetID,
            isTie: isTie,
            localTieBreak: isTie ? .earlierDate : nil,
            reasons: reasons(scores: scores, keeperID: keeper.assetID, kind: group.kind)
        )
    }

    public func reasons(scores: [MemberScore], keeperID: String, kind: GroupKind) -> [String: String] {
        guard let k = scores.first(where: { $0.assetID == keeperID }) else { return [:] }
        var out: [String: String] = [:]
        var keeperParts: [String] = []
        if k.isFavorite { keeperParts.append("favorite") }
        if k.resolution == 1 { keeperParts.append("highest resolution") }
        if (k.fileSizeBytes ?? 0) == (scores.compactMap(\.fileSizeBytes).max() ?? 0) { keeperParts.append("largest file") }
        if keeperParts.isEmpty { keeperParts.append("best available") }
        out[keeperID] = "Best of \(scores.count): " + keeperParts.joined(separator: ", ")
        for s in scores where s.assetID != keeperID {
            if k.isFavorite && !s.isFavorite {
                out[s.assetID] = "Keeper is a favorite"
            } else if kind == .duplicate {
                out[s.assetID] = "Exact duplicate of keeper"
            } else if let sw = s.pixelWidth, let sh = s.pixelHeight, let kw = k.pixelWidth, let kh = k.pixelHeight, sw * sh < kw * kh {
                out[s.assetID] = "Lower resolution (\(sw)×\(sh) vs \(kw)×\(kh))"
            } else if let ss = s.fileSizeBytes, let ks = k.fileSizeBytes, ss < ks {
                out[s.assetID] = "Smaller file (\(Self.mb(ss)) vs \(Self.mb(ks)))"
            } else if let sd = s.duration, let kd = k.duration, sd < kd {
                out[s.assetID] = "Shorter (\(Self.clock(sd)) vs \(Self.clock(kd)))"
            } else {
                out[s.assetID] = "Near-identical take; keeper was taken first"
            }
        }
        return out
    }

    static func mb(_ bytes: Int64) -> String {
        String(format: "%.0f MB", Double(bytes) / 1_048_576)
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - Planner

/// classify → group → score → decide for videos. Same determinism guarantees as `Planner`.
public struct VideoPlanner: Sendable {
    public let thresholds: Thresholds

    public init(thresholds: Thresholds = .default) {
        self.thresholds = thresholds
    }

    public func plan(metrics: [VideoMetrics], distance: (String, String) -> Float?) -> ScanPlan {
        let ordered = metrics.sorted { a, b in
            a.creationDate != b.creationDate ? a.creationDate < b.creationDate : a.id < b.id
        }
        let byID = Dictionary(ordered.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let classifier = VideoClassifier()
        var classifications: [String: Classification] = [:]
        for v in ordered { classifications[v.id] = classifier.classify(v) }

        let groupable = ordered.filter { classifications[$0.id]?.isGroupable == true }
        let scorer = VideoScorer(thresholds: thresholds)
        let groups = VideoGrouper(thresholds: thresholds)
            .groups(for: groupable, distance: distance)
            .map { scorer.score(group: $0, metrics: byID) }
        let decisions = Planner.decisions(orderedIDs: ordered.map(\.id), classifications: classifications, groups: groups)
        return ScanPlan(classifications: classifications, groups: groups, decisions: decisions)
    }
}
