import Foundation
import Observation
import PhotoCullCore
import SwiftData

/// Runs the Claude tie-breaker over a session's unresolved ties after the user confirms.
/// A verdict can only move the keeper inside a tie; a failed or unconfident call changes
/// nothing (safety rule 7).
@MainActor
@Observable
final class TieBreakRunner {
    enum State: Equatable {
        case idle
        case running(done: Int, total: Int)
        case finished(changed: Int, confirmed: Int, failed: Int)
        case failed(String)
    }

    struct Job {
        let group: PhotoGroup
        let candidateIDs: [String]
    }

    private(set) var state: State = .idle

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// Tied groups not yet judged by Claude and not overridden by the user, with the
    /// candidates that would be sent: the tie set, minus favorites, capped by the threshold.
    func jobs(in session: ScanSession, thresholds: Thresholds) -> [Job] {
        let scorer = Scorer(thresholds: thresholds)
        let protected = Set(session.decisions.filter(\.isProtected).map(\.assetID))
        return session.groups
            .filter { $0.isTie && $0.claudeReason == nil && !$0.isUserKeeper }
            .sorted { $0.earliestDate > $1.earliestDate }
            .compactMap { group in
                let candidates = scorer.tieCandidates(in: group.scores)
                    .map(\.assetID)
                    .filter { !protected.contains($0) }
                    .prefix(thresholds.claudeMaxImagesPerGroup)
                return candidates.count >= 2 ? Job(group: group, candidateIDs: Array(candidates)) : nil
            }
    }

    func run(_ jobs: [Job], apiKey: String, model: ClaudeModel, thresholds: Thresholds, decisions: [String: Decision], context: ModelContext) async {
        guard !isRunning, !jobs.isEmpty else { return }
        let client = ClaudeTieBreaker(apiKey: apiKey, model: model.rawValue, imageLongEdge: thresholds.claudeImageLongEdge)
        let scorer = Scorer(thresholds: thresholds)
        var changed = 0, confirmed = 0, failed = 0
        state = .running(done: 0, total: jobs.count)

        for (index, job) in jobs.enumerated() {
            do {
                let verdict = try await client.resolve(candidateIDs: job.candidateIDs)
                guard verdict.isConfident else {
                    job.group.claudeError = "Low confidence (\(Int((verdict.confidence * 100).rounded()))%): \(verdict.reason)"
                    failed += 1
                    continue
                }
                let winner = job.candidateIDs[verdict.winner - 1]
                if winner == job.group.keeperID {
                    job.group.claudeReason = verdict.reason
                    if let keeper = decisions[winner], !keeper.isUserDecision {
                        keeper.reason = "Claude agrees: \(verdict.reason)"
                    }
                    confirmed += 1
                } else {
                    apply(winner: winner, reason: verdict.reason, to: job.group, scorer: scorer, decisions: decisions)
                    changed += 1
                }
                job.group.claudeError = nil
            } catch {
                job.group.claudeError = error.localizedDescription
                failed += 1
            }
            try? context.save()
            state = .running(done: index + 1, total: jobs.count)
        }
        state = .finished(changed: changed, confirmed: confirmed, failed: failed)
    }

    private func apply(winner: String, reason: String, to group: PhotoGroup, scorer: Scorer, decisions: [String: Decision]) {
        let previous = group.keeperID
        group.keeperID = winner
        group.keeperSource = DecisionSource.claude.rawValue
        group.claudeReason = reason
        let reasons = scorer.reasons(for: group.scores, keeperID: winner)
        for id in group.memberIDs {
            guard let d = decisions[id], !d.isUserDecision else { continue }
            if id == winner {
                d.action = CullAction.keep.rawValue
                d.source = DecisionSource.claude.rawValue
                d.reason = "Claude: \(reason)"
            } else if id == previous {
                // Was an auto keeper; never a favorite (favorites are not tie candidates).
                d.action = d.isProtected ? CullAction.keep.rawValue : CullAction.delete.rawValue
                d.source = DecisionSource.claude.rawValue
                d.reason = d.isProtected ? "Favorite (protected)" : (reasons[id] ?? "Claude preferred another frame")
            } else if let r = reasons[id] {
                d.reason = r
            }
        }
    }
}
