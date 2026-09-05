import Foundation
import PhotoCullCore
import SwiftData

struct CachedMetrics: Sendable {
    let metrics: AssetMetrics
    let modificationDate: Date?
}

struct AnalysisEntry: Sendable {
    let metrics: AssetMetrics
    let classification: Classification
    let modificationDate: Date?
}

/// The single writer for SwiftData during a scan (spec §9).
@ModelActor
actor PersistenceActor {
    /// All AssetRecords by localIdentifier, loaded once per actor; keeps batch upserts O(batch).
    private var index: [String: AssetRecord]?

    private func loadIndex() throws -> [String: AssetRecord] {
        if let index { return index }
        let records = try modelContext.fetch(FetchDescriptor<AssetRecord>())
        let built = Dictionary(records.map { ($0.localIdentifier, $0) }, uniquingKeysWith: { a, _ in a })
        index = built
        return built
    }

    func cachedMetrics(for ids: Set<String>) throws -> [String: CachedMetrics] {
        let decoder = JSONDecoder()
        var out: [String: CachedMetrics] = [:]
        for (id, record) in try loadIndex() where ids.contains(id) {
            if let metrics = try? decoder.decode(AssetMetrics.self, from: record.metricsJSON) {
                out[id] = CachedMetrics(metrics: metrics, modificationDate: record.modificationDate)
            }
        }
        return out
    }

    func upsert(_ entries: [AnalysisEntry]) throws {
        guard !entries.isEmpty else { return }
        var byID = try loadIndex()
        let encoder = JSONEncoder()
        for entry in entries {
            let json = try encoder.encode(entry.metrics)
            if let record = byID[entry.metrics.id] {
                record.metricsJSON = json
                record.modificationDate = entry.modificationDate
                record.category = entry.classification.category.rawValue
                record.categoryReason = entry.classification.reason
                record.analyzedAt = .now
            } else {
                let record = AssetRecord(
                    localIdentifier: entry.metrics.id,
                    modificationDate: entry.modificationDate,
                    metricsJSON: json,
                    category: entry.classification.category.rawValue,
                    categoryReason: entry.classification.reason
                )
                modelContext.insert(record)
                byID[entry.metrics.id] = record
            }
        }
        index = byID
        try modelContext.save()
    }

    /// Persists a finished plan as ScanSession + PhotoGroup + Decision rows. Returns the session id.
    /// User decisions from the most recent earlier session are carried over (safety rule 6 /
    /// spec §5.4: a group with a user override is never re-scored).
    func saveSession(start: Date, end: Date, thresholds: Thresholds, plan: ScanPlan, dates: [String: Date], status: String) throws -> UUID {
        let encoder = JSONEncoder()
        let carried = try previousUserChoices()
        let scorer = Scorer(thresholds: thresholds)

        let session = ScanSession(startDate: start, endDate: end, status: status, thresholdsJSON: try encoder.encode(thresholds))
        modelContext.insert(session)

        var groupIDs: [Int: UUID] = [:]
        var groupKeepers: [Int: (id: String, source: DecisionSource, reasons: [String: String])] = [:]
        for (index, auto) in plan.groups.enumerated() {
            var group = auto
            var keeperSource = DecisionSource.auto
            if let userKeeper = carried.keepers.first(where: { group.memberIDs.contains($0) }), userKeeper != group.keeperID {
                group = scorer.replacingKeeper(in: group, with: userKeeper, keeperReason: "Chosen by you as keeper")
                keeperSource = .user
            } else if carried.keepers.contains(group.keeperID) {
                keeperSource = .user
            }
            let row = PhotoGroup(
                kind: group.kind.rawValue,
                memberIDs: group.memberIDs,
                keeperID: group.keeperID,
                scoresJSON: try encoder.encode(group.scores),
                isTie: group.isTie,
                keeperSource: keeperSource.rawValue,
                earliestDate: group.memberIDs.compactMap { dates[$0] }.min() ?? .distantPast
            )
            session.groups.append(row)
            groupIDs[index] = row.id
            groupKeepers[index] = (group.keeperID, keeperSource, group.reasons)
        }

        for decision in plan.decisions {
            let protected = plan.classifications[decision.assetID]?.isProtected ?? false
            var action = decision.action
            var source = decision.source
            var reason = decision.reason
            if let gi = decision.groupIndex, let keeper = groupKeepers[gi] {
                if decision.assetID == keeper.id {
                    action = .keep
                    source = keeper.source
                    reason = keeper.reasons[decision.assetID] ?? reason
                } else if let choice = carried.decisions[decision.assetID] {
                    action = choice.action
                    source = .user
                    reason = choice.reason
                } else if keeper.source == .user {
                    reason = keeper.reasons[decision.assetID] ?? reason
                }
            } else if let choice = carried.decisions[decision.assetID] {
                action = choice.action
                source = .user
                reason = choice.reason
            }
            if protected && action == .delete {
                action = .keep
                reason = "Favorite (protected)"
            }
            session.decisions.append(Decision(
                assetID: decision.assetID,
                action: action.rawValue,
                source: source.rawValue,
                reason: reason,
                groupID: decision.groupIndex.flatMap { groupIDs[$0] },
                category: decision.category.rawValue,
                isProtected: protected,
                creationDate: dates[decision.assetID] ?? .distantPast
            ))
        }
        try modelContext.save()
        return session.id
    }

    private struct PreviousChoices {
        var decisions: [String: (action: CullAction, reason: String)] = [:]
        var keepers: Set<String> = []
    }

    /// User decisions and user-chosen keepers from the most recent session, if any.
    private func previousUserChoices() throws -> PreviousChoices {
        // Few sessions ever exist; pick the latest in memory (a SortDescriptor here trips a Sendable warning).
        let sessions = try modelContext.fetch(FetchDescriptor<ScanSession>())
        guard let previous = sessions.max(by: { $0.createdAt < $1.createdAt }) else { return PreviousChoices() }
        var out = PreviousChoices()
        for d in previous.decisions where d.isUserDecision {
            if let action = CullAction(rawValue: d.action) { out.decisions[d.assetID] = (action, d.reason) }
        }
        for g in previous.groups where g.isUserKeeper {
            out.keepers.insert(g.keeperID)
        }
        return out
    }

    func cachedCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<AssetRecord>())
    }
}
