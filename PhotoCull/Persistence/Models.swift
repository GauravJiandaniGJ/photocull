import Foundation
import PhotoCullCore
import SwiftData

// Spec §7. Scalars only: feature prints never touch the store.

/// Analysis cache. Survives sessions so a re-scan only processes new or changed assets.
@Model
final class AssetRecord {
    @Attribute(.unique) var localIdentifier: String
    /// Recompute when `PHAsset.modificationDate` differs.
    var modificationDate: Date?
    /// `AssetMetrics` as JSON.
    var metricsJSON: Data
    var category: String
    var categoryReason: String
    var analyzedAt: Date

    init(localIdentifier: String, modificationDate: Date?, metricsJSON: Data, category: String, categoryReason: String, analyzedAt: Date = .now) {
        self.localIdentifier = localIdentifier
        self.modificationDate = modificationDate
        self.metricsJSON = metricsJSON
        self.category = category
        self.categoryReason = categoryReason
        self.analyzedAt = analyzedAt
    }
}

enum ScanStatus {
    static let running = "running"
    static let cancelled = "cancelled"
    static let completed = "completed"
    static let applied = "applied"
}

@Model
final class ScanSession {
    @Attribute(.unique) var id: UUID
    var startDate: Date
    var endDate: Date
    var createdAt: Date
    var status: String
    /// `Thresholds` snapshot as JSON.
    var thresholdsJSON: Data
    @Relationship(deleteRule: .cascade, inverse: \PhotoGroup.session) var groups: [PhotoGroup]
    @Relationship(deleteRule: .cascade, inverse: \Decision.session) var decisions: [Decision]
    // Journey (spec §6 flow: Scan → Groups → Clutter → Apply), persisted so the user can
    // leave and come back days later.
    var groupsVisitedAt: Date?
    var groupsReviewedAt: Date?
    var clutterVisitedAt: Date?
    var clutterReviewedAt: Date?

    init(id: UUID = UUID(), startDate: Date, endDate: Date, createdAt: Date = .now, status: String = ScanStatus.running, thresholdsJSON: Data) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.createdAt = createdAt
        self.status = status
        self.thresholdsJSON = thresholdsJSON
        self.groups = []
        self.decisions = []
    }
}

@Model
final class PhotoGroup {
    @Attribute(.unique) var id: UUID
    /// `GroupKind` raw value: burst | similar.
    var kind: String
    var memberIDs: [String]
    var keeperID: String
    /// `[MemberScore]` as JSON.
    var scoresJSON: Data
    var isTie: Bool
    var claudeReason: String?
    var claudeError: String?
    /// `DecisionSource` raw value for the keeper choice: auto | user | claude. A user-chosen
    /// keeper is carried over to the same group on later scans.
    var keeperSource: String = DecisionSource.auto.rawValue
    /// Creation date of the earliest member, for newest-first ordering.
    var earliestDate: Date = Date.distantPast
    var session: ScanSession?

    init(id: UUID = UUID(), kind: String, memberIDs: [String], keeperID: String, scoresJSON: Data, isTie: Bool, keeperSource: String = DecisionSource.auto.rawValue, earliestDate: Date = .distantPast, claudeReason: String? = nil, claudeError: String? = nil) {
        self.id = id
        self.kind = kind
        self.memberIDs = memberIDs
        self.keeperID = keeperID
        self.scoresJSON = scoresJSON
        self.isTie = isTie
        self.keeperSource = keeperSource
        self.earliestDate = earliestDate
        self.claudeReason = claudeReason
        self.claudeError = claudeError
    }

    var scores: [MemberScore] { (try? JSONDecoder().decode([MemberScore].self, from: scoresJSON)) ?? [] }
    var isUserKeeper: Bool { keeperSource == DecisionSource.user.rawValue }
}

@Model
final class Decision {
    @Attribute(.unique) var id: UUID
    var assetID: String
    /// `CullAction` raw value: keep | delete.
    var action: String
    /// `DecisionSource` raw value: auto | user | claude. User decisions are never re-scored.
    var source: String
    var reason: String
    var groupID: UUID?
    /// `AssetCategory` raw value.
    var category: String
    /// Favorite: never a delete candidate, whatever the user toggles (safety rule 2).
    var isProtected: Bool = false
    /// Asset creation date, for newest-first ordering in review screens.
    var creationDate: Date = Date.distantPast
    var session: ScanSession?

    init(id: UUID = UUID(), assetID: String, action: String, source: String, reason: String, groupID: UUID? = nil, category: String, isProtected: Bool = false, creationDate: Date = .distantPast) {
        self.id = id
        self.assetID = assetID
        self.action = action
        self.source = source
        self.reason = reason
        self.groupID = groupID
        self.category = category
        self.isProtected = isProtected
        self.creationDate = creationDate
    }

    var isDelete: Bool { action == CullAction.delete.rawValue }
    var isUserDecision: Bool { source == DecisionSource.user.rawValue }
}

@Model
final class AuditEntry {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var appliedAt: Date
    var deletedIDs: [String]
    var keptIDs: [String]
    var summaryJSON: Data

    init(id: UUID = UUID(), sessionID: UUID, appliedAt: Date = .now, deletedIDs: [String], keptIDs: [String], summaryJSON: Data) {
        self.id = id
        self.sessionID = sessionID
        self.appliedAt = appliedAt
        self.deletedIDs = deletedIDs
        self.keptIDs = keptIDs
        self.summaryJSON = summaryJSON
    }
}

/// One line of the in-app activity log (Settings → Activity log).
@Model
final class LogEntry {
    @Attribute(.unique) var id: UUID
    var at: Date
    /// info | warning | error
    var level: String
    /// app | scan | review | claude | apply | settings
    var category: String
    var message: String

    init(id: UUID = UUID(), at: Date = .now, level: String, category: String, message: String) {
        self.id = id
        self.at = at
        self.level = level
        self.category = category
        self.message = message
    }
}

extension ModelContainer {
    static let photoCullSchema = Schema([
        AssetRecord.self, ScanSession.self, PhotoGroup.self, Decision.self, AuditEntry.self, LogEntry.self,
    ])

    static func photoCull(inMemory: Bool = false) throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: photoCullSchema, configurations: [config])
    }
}
