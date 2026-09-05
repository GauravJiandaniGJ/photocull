import Foundation
import PhotoCullCore

enum JourneyStep: Int, CaseIterable, Identifiable {
    case scan, groups, clutter, apply

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .scan: return "Scan"
        case .groups: return "Review groups"
        case .clutter: return "Review clutter"
        case .apply: return "Apply"
        }
    }

    var symbol: String {
        switch self {
        case .scan: return "magnifyingglass"
        case .groups: return "square.stack.3d.up"
        case .clutter: return "doc.text.magnifyingglass"
        case .apply: return "trash"
        }
    }

    var tab: AppTab {
        switch self {
        case .scan: return .scan
        case .groups: return .groups
        case .clutter: return .clutter
        case .apply: return .apply
        }
    }
}

enum JourneyState: Equatable {
    case done, current, pending
}

/// Where the user is in Scan → Groups → Clutter → Apply for one session, from persisted marks.
struct Journey {
    let session: ScanSession

    var isApplied: Bool { session.status == ScanStatus.applied }

    var current: JourneyStep {
        if isApplied { return .apply }
        if session.clutterReviewedAt != nil { return .apply }
        if session.groupsReviewedAt != nil { return .clutter }
        return .groups
    }

    func state(of step: JourneyStep) -> JourneyState {
        if isApplied { return .done }
        if step.rawValue < current.rawValue { return .done }
        if step == current { return .current }
        return .pending
    }

    /// Apply is allowed once at least one review tab has been opened for this session (spec §6).
    var canApply: Bool { session.groupsVisitedAt != nil || session.clutterVisitedAt != nil }

    // Counts for the card.
    var groupCount: Int { session.groups.count }
    var editedGroupCount: Int {
        let userIDs = Set(session.decisions.filter(\.isUserDecision).map(\.assetID))
        return session.groups.filter { $0.isUserKeeper || $0.memberIDs.contains(where: userIDs.contains) }.count
    }
    var clutterCount: Int { session.decisions.filter { $0.groupID == nil && $0.category != AssetCategory.personal.rawValue }.count }
    var clutterToDelete: Int { session.decisions.filter { $0.groupID == nil && $0.isDelete }.count }
    var deleteCandidates: Int { session.decisions.filter { $0.isDelete && !$0.isProtected }.count }

    func detail(for step: JourneyStep) -> String {
        switch step {
        case .scan:
            return "\(session.decisions.count.formatted()) photos · \(session.createdAt.formatted(.relative(presentation: .named)))"
        case .groups:
            if groupCount == 0 { return "No groups found" }
            let edited = editedGroupCount
            return "\(groupCount.formatted()) groups" + (edited > 0 ? " · \(edited) changed by you" : "")
        case .clutter:
            if clutterCount == 0 { return "No clutter found" }
            return "\(clutterCount.formatted()) items · \(clutterToDelete.formatted()) to delete"
        case .apply:
            if isApplied { return "Applied \(session.createdAt.formatted(.relative(presentation: .named)))" }
            return "\(deleteCandidates.formatted()) photos to Recently Deleted"
        }
    }
}
