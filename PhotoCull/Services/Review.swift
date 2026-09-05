import Foundation
import PhotoCullCore
import SwiftData

/// User overrides on the latest session's decisions. Every change is marked `source = user`
/// so it survives re-scans. Favorites never become delete candidates (safety rule 2) and a
/// group never loses its keeper (rule 4).
@MainActor
enum Review {
    static let keeperReason = "Chosen by you as keeper"
    static let keptReason = "Kept by you"
    static let removedReason = "Removed by you"

    static func makeKeeper(_ id: String, in group: PhotoGroup, decisions: [String: Decision], context: ModelContext) {
        guard group.memberIDs.contains(id), id != group.keeperID else { return }
        let previous = group.keeperID
        group.keeperID = id
        group.keeperSource = DecisionSource.user.rawValue
        if let d = decisions[id] { set(d, action: .keep, reason: keeperReason) }
        if let d = decisions[previous] { set(d, action: .delete, reason: removedReason) }
        save(context)
    }

    /// Flip keep/delete for a group member. The keeper cannot be flipped; pick another keeper first.
    static func toggle(_ decision: Decision, in group: PhotoGroup?, context: ModelContext) {
        if let group, group.keeperID == decision.assetID { return }
        if decision.isDelete {
            set(decision, action: .keep, reason: keptReason)
        } else {
            set(decision, action: .delete, reason: removedReason)
        }
        save(context)
    }

    static func keepAll(in group: PhotoGroup, decisions: [String: Decision], context: ModelContext) {
        for id in group.memberIDs {
            guard let d = decisions[id], id != group.keeperID else { continue }
            set(d, action: .keep, reason: keptReason)
        }
        save(context)
    }

    static func deleteAllButKeeper(in group: PhotoGroup, decisions: [String: Decision], context: ModelContext) {
        for id in group.memberIDs {
            guard let d = decisions[id], id != group.keeperID else { continue }
            set(d, action: .delete, reason: removedReason)
        }
        save(context)
    }

    /// Clutter: explicit keep/delete for one asset.
    static func set(_ decision: Decision, to action: CullAction, context: ModelContext) {
        set(decision, action: action, reason: action == .delete ? removedReason : keptReason)
        save(context)
    }

    static func setAll(_ decisions: [Decision], to action: CullAction, context: ModelContext) {
        for d in decisions { set(d, action: action, reason: action == .delete ? removedReason : keptReason) }
        save(context)
    }

    private static func set(_ decision: Decision, action: CullAction, reason: String) {
        let final: CullAction = (decision.isProtected && action == .delete) ? .keep : action
        decision.action = final.rawValue
        decision.source = DecisionSource.user.rawValue
        decision.reason = decision.isProtected && action == .delete ? "Favorite (protected)" : reason
    }

    private static func save(_ context: ModelContext) {
        try? context.save()
    }
}
