import Foundation

/// The minimum the grouper needs per asset. Feature prints stay in the app target; the
/// grouper only ever asks for a distance between two ids.
public struct GroupingCandidate: Equatable, Sendable {
    public let id: String
    public let creationDate: Date
    public let burstIdentifier: String?

    public init(id: String, creationDate: Date, burstIdentifier: String? = nil) {
        self.id = id
        self.creationDate = creationDate
        self.burstIdentifier = burstIdentifier
    }

    public init(_ m: AssetMetrics) {
        self.init(id: m.id, creationDate: m.creationDate, burstIdentifier: m.burstIdentifier)
    }
}

/// An unordered pair of asset ids the grouper compares.
public struct ComparedPair: Equatable, Hashable, Sendable {
    public let a: String
    public let b: String

    public init(a: String, b: String) {
        self.a = a
        self.b = b
    }
}

public struct ProposedGroup: Codable, Equatable, Sendable {
    public let kind: GroupKind
    /// Always ≥ 2 members, in creation-date order.
    public let memberIDs: [String]

    public init(kind: GroupKind, memberIDs: [String]) {
        precondition(memberIDs.count >= 2, "A group never has fewer than two members")
        self.kind = kind
        self.memberIDs = memberIDs
    }
}

/// Spec §5.3: bursts first, then time buckets, then union-find over feature-print distances.
/// Output is deterministic for the same input regardless of input order (safety rule 6).
public struct Grouper: Sendable {
    public let thresholds: Thresholds
    /// Cap on assets per bucket for pairwise work; larger buckets are split by time.
    public let maxBucketSize: Int

    public init(thresholds: Thresholds = .default, maxBucketSize: Int = 60) {
        precondition(maxBucketSize >= 2)
        self.thresholds = thresholds
        self.maxBucketSize = maxBucketSize
    }

    /// - Parameter distance: feature-print distance between two asset ids, or nil when either
    ///   side has no feature print (that pair is then never joined).
    /// - Parameter distance: feature-print distance between two asset ids, or nil when either
    ///   side has no feature print (that pair is then never joined).
    public func groups(
        for candidates: [GroupingCandidate],
        distance: (String, String) -> Float?
    ) -> [ProposedGroup] {
        let sorted = candidates.sorted(by: Self.timeOrder)
        let (bursts, chunks) = partition(sorted)
        var result = bursts

        // 3 + 4. Within each (capped) bucket: pairwise distance → union-find → components of ≥ 2.
        for chunk in chunks {
            result.append(contentsOf: similarGroups(in: chunk, distance: distance))
        }

        return result.sorted(by: Self.groupOrder(lookup: Dictionary(uniqueKeysWithValues: sorted.map { ($0.id, $0.creationDate) })))
    }

    /// Every pair `groups(for:distance:)` would ask a distance for: all pairs inside each
    /// capped time bucket, after burst members are taken out. Used by the Calibrate view to
    /// draw the distance histogram from exactly the comparisons that matter.
    public func comparedPairs(for candidates: [GroupingCandidate]) -> [ComparedPair] {
        let sorted = candidates.sorted(by: Self.timeOrder)
        let (_, chunks) = partition(sorted)
        var pairs: [ComparedPair] = []
        for chunk in chunks where chunk.count >= 2 {
            for i in 0..<(chunk.count - 1) {
                for j in (i + 1)..<chunk.count {
                    pairs.append(ComparedPair(a: chunk[i].id, b: chunk[j].id))
                }
            }
        }
        return pairs
    }

    /// Steps 1, 2 and 4 of §5.3: burst groups, then time buckets of the rest, capped by size.
    private func partition(_ sorted: [GroupingCandidate]) -> (bursts: [ProposedGroup], chunks: [[GroupingCandidate]]) {
        // 1. Bursts: any assets sharing a burstIdentifier form a burst group immediately.
        var burstMembers: [String: [GroupingCandidate]] = [:]
        for c in sorted {
            if let b = c.burstIdentifier, !b.isEmpty {
                burstMembers[b, default: []].append(c)
            }
        }
        var bursts: [ProposedGroup] = []
        var claimed = Set<String>()
        for (_, members) in burstMembers where members.count >= 2 {
            bursts.append(ProposedGroup(kind: .burst, memberIDs: members.map(\.id)))
            claimed.formUnion(members.map(\.id))
        }

        // 2. Remaining assets: time buckets, split when the gap exceeds the threshold.
        let remaining = sorted.filter { !claimed.contains($0.id) }
        var buckets: [[GroupingCandidate]] = []
        var current: [GroupingCandidate] = []
        for c in remaining {
            if let last = current.last,
               c.creationDate.timeIntervalSince(last.creationDate) > thresholds.groupTimeGapSeconds {
                buckets.append(current)
                current = []
            }
            current.append(c)
        }
        if !current.isEmpty { buckets.append(current) }

        // 4. Cap a bucket for pairwise work; split larger buckets by time.
        let chunks = buckets.flatMap { Self.chunked($0, size: maxBucketSize) }
        return (bursts, chunks)
    }

    private func similarGroups(
        in chunk: [GroupingCandidate],
        distance: (String, String) -> Float?
    ) -> [ProposedGroup] {
        guard chunk.count >= 2 else { return [] }
        var uf = UnionFind(count: chunk.count)
        for i in 0..<(chunk.count - 1) {
            for j in (i + 1)..<chunk.count {
                if let d = distance(chunk[i].id, chunk[j].id), d <= thresholds.similarityDistanceMax {
                    uf.union(i, j)
                }
            }
        }
        var components: [Int: [String]] = [:]
        for (index, c) in chunk.enumerated() {
            components[uf.find(index), default: []].append(c.id)
        }
        // Chunk is already in time order, so each component's members are too.
        return components.values
            .filter { $0.count >= 2 }
            .map { ProposedGroup(kind: .similar, memberIDs: $0) }
    }

    static func timeOrder(_ a: GroupingCandidate, _ b: GroupingCandidate) -> Bool {
        if a.creationDate != b.creationDate { return a.creationDate < b.creationDate }
        return a.id < b.id
    }

    private static func groupOrder(lookup: [String: Date]) -> (ProposedGroup, ProposedGroup) -> Bool {
        return { a, b in
            let da = lookup[a.memberIDs[0]] ?? .distantPast
            let db = lookup[b.memberIDs[0]] ?? .distantPast
            if da != db { return da < db }
            return a.memberIDs[0] < b.memberIDs[0]
        }
    }

    private static func chunked<T>(_ items: [T], size: Int) -> [[T]] {
        stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }
}

struct UnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var node = x
        while parent[node] != root {
            let next = parent[node]
            parent[node] = root
            node = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let ra = find(a), rb = find(b)
        guard ra != rb else { return }
        if rank[ra] < rank[rb] {
            parent[ra] = rb
        } else if rank[ra] > rank[rb] {
            parent[rb] = ra
        } else {
            parent[rb] = ra
            rank[ra] += 1
        }
    }
}
