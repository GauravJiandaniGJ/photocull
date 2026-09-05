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
    func saveSession(start: Date, end: Date, thresholds: Thresholds, plan: ScanPlan, status: String) throws -> UUID {
        let encoder = JSONEncoder()
        let session = ScanSession(startDate: start, endDate: end, status: status, thresholdsJSON: try encoder.encode(thresholds))
        modelContext.insert(session)

        var groupIDs: [Int: UUID] = [:]
        for (index, group) in plan.groups.enumerated() {
            let row = PhotoGroup(
                kind: group.kind.rawValue,
                memberIDs: group.memberIDs,
                keeperID: group.keeperID,
                scoresJSON: try encoder.encode(group.scores),
                isTie: group.isTie
            )
            session.groups.append(row)
            groupIDs[index] = row.id
        }
        for decision in plan.decisions {
            session.decisions.append(Decision(
                assetID: decision.assetID,
                action: decision.action.rawValue,
                source: decision.source.rawValue,
                reason: decision.reason,
                groupID: decision.groupIndex.flatMap { groupIDs[$0] },
                category: decision.category.rawValue
            ))
        }
        try modelContext.save()
        return session.id
    }

    func cachedCount() throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<AssetRecord>())
    }
}
