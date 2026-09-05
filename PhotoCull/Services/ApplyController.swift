import Foundation
import Observation
import PhotoCullCore
import Photos
import SwiftData

/// The ONLY place in the app that calls `PHAssetChangeRequest.deleteAssets` (safety rule 1).
/// `apply` is invoked solely from the Apply screen after the in-app confirmation; iOS then
/// shows its own confirmation because it is one `performChanges` call.
@MainActor
@Observable
final class ApplyController {
    enum State: Equatable {
        case idle
        case checking
        case deleting
        case done
        case cancelled
        case failed(String)
    }

    struct Result: Equatable {
        var deleted = 0
        var skippedMissing = 0
        var skippedModified = 0
        var skippedFavorite = 0
        var auditID: UUID?
    }

    private(set) var state: State = .idle
    private(set) var result: Result?

    var isBusy: Bool { state == .checking || state == .deleting }

    func apply(session: ScanSession, context: ModelContext) async {
        guard !isBusy else { return }
        state = .checking
        result = nil

        // Rule 3: only delete decisions from THIS session; rule 2: never a favorite.
        let candidates = session.decisions.filter { $0.isDelete && !$0.isProtected }
        let candidateIDs = candidates.map(\.assetID)
        let analysedModification: [String: Date?] = (try? context.fetch(FetchDescriptor<AssetRecord>()))
            .map { Dictionary($0.map { ($0.localIdentifier, $0.modificationDate) }, uniquingKeysWith: { a, _ in a }) } ?? [:]

        // Re-fetch right before deletion; skip anything missing, changed since analysis, or favorited since.
        let current = await Task.detached(priority: .userInitiated) { () -> [String: (modified: Date?, favorite: Bool)] in
            var out: [String: (Date?, Bool)] = [:]
            PHAsset.fetchAssets(withLocalIdentifiers: candidateIDs, options: nil).enumerateObjects { asset, _, _ in
                out[asset.localIdentifier] = (asset.modificationDate, asset.isFavorite)
            }
            return out
        }.value

        var partial = Result()
        var eligible: [String] = []
        for id in candidateIDs {
            guard let now = current[id] else { partial.skippedMissing += 1; continue }
            if now.favorite { partial.skippedFavorite += 1; continue }
            if let analysed = analysedModification[id], analysed != now.modified { partial.skippedModified += 1; continue }
            eligible.append(id)
        }

        AppLog.info(.apply, "Apply: \(candidateIDs.count) candidates, \(eligible.count) eligible, skipped \(partial.skippedMissing) missing / \(partial.skippedModified) changed / \(partial.skippedFavorite) favorited")
        guard !eligible.isEmpty else {
            result = partial
            state = .failed("Nothing left to delete: every candidate is missing, changed, or now a favorite.")
            AppLog.warning(.apply, "Apply aborted: nothing eligible")
            return
        }

        state = .deleting
        do {
            let ids = eligible
            try await PHPhotoLibrary.shared().performChanges {
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
                PHAssetChangeRequest.deleteAssets(assets)
            }
        } catch let error as PHPhotosError where error.code == .userCancelled {
            state = .cancelled
            AppLog.warning(.apply, "Apply cancelled in the system dialog; nothing deleted")
            return
        } catch {
            state = .failed(error.localizedDescription)
            AppLog.error(.apply, "Apply failed: \(error.localizedDescription)")
            return
        }

        partial.deleted = eligible.count
        let keptIDs = session.decisions.filter { !$0.isDelete }.map(\.assetID)
        let summary = AuditSummary(
            deleted: eligible.count,
            kept: keptIDs.count,
            skippedMissing: partial.skippedMissing,
            skippedModified: partial.skippedModified,
            skippedFavorite: partial.skippedFavorite,
            deletedByCategory: Dictionary(grouping: candidates.filter { eligible.contains($0.assetID) }, by: \.category).mapValues(\.count),
            userOverrides: session.decisions.filter(\.isUserDecision).count,
            rangeStart: session.startDate,
            rangeEnd: session.endDate
        )
        let audit = AuditEntry(
            sessionID: session.id,
            deletedIDs: eligible,
            keptIDs: keptIDs,
            summaryJSON: (try? JSONEncoder().encode(summary)) ?? Data()
        )
        context.insert(audit)
        session.status = ScanStatus.applied
        try? context.save()
        partial.auditID = audit.id
        result = partial
        state = .done
        AppLog.info(.apply, "Moved \(eligible.count) photos to Recently Deleted; audit \(audit.id.uuidString.prefix(8))")
    }
}

struct AuditSummary: Codable, Equatable {
    var deleted: Int
    var kept: Int
    var skippedMissing: Int
    var skippedModified: Int
    var skippedFavorite: Int
    var deletedByCategory: [String: Int]
    var userOverrides: Int
    var rangeStart: Date
    var rangeEnd: Date
}
