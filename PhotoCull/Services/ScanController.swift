import Foundation
import Observation
import PhotoCullCore
import SwiftData
import UIKit

/// Runs one scan end to end (spec §3 data flow) and publishes progress for the Scan screen.
/// Nothing here deletes anything: the plan is stored as decisions for review.
@MainActor
@Observable
final class ScanController {
    enum Stage: Equatable {
        case idle, fetching, analysing, grouping, saving, completed, cancelled, failed

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .fetching: return "Fetching photos…"
            case .analysing: return "Analysing"
            case .grouping: return "Grouping…"
            case .saving: return "Saving…"
            case .completed: return "Done"
            case .cancelled: return "Cancelled"
            case .failed: return "Failed"
            }
        }
    }

    struct Options: Sendable {
        var start: Date
        var end: Date
        var includeWhatsApp: Bool
        var includeScreenshots: Bool
        var thresholds: Thresholds
    }

    struct Progress: Equatable {
        var total = 0
        var done = 0
        var fullAnalyses = 0
        var printOnly = 0
        var reusedFromCache = 0
        var failed = 0
    }

    struct Summary: Equatable {
        var sessionID: UUID?
        var groups = 0
        var burstGroups = 0
        var photosInGroups = 0
        var keepers = 0
        var clutter: [AssetCategory: Int] = [:]
        var deleteCandidates = 0
        var favoritesProtected = 0
        var scanned = 0
        var duration: TimeInterval = 0
    }

    /// Everything the Calibrate view needs, kept for the session (feature prints live in the extractor).
    struct Calibration {
        var candidates: [GroupingCandidate]
        var distances: [ComparedPair: Float]
        var metricsByID: [String: AssetMetrics]
        var thresholds: Thresholds

        func distance(_ a: String, _ b: String) -> Float? {
            distances[ComparedPair(a: a, b: b)] ?? distances[ComparedPair(a: b, b: a)]
        }
    }

    private(set) var stage: Stage = .idle
    private(set) var progress = Progress()
    private(set) var startedAt: Date?
    private(set) var finishedAt: Date?
    private(set) var summary: Summary?
    private(set) var calibration: Calibration?
    private(set) var errorMessage: String?

    let extractor = VisionFeatureExtractor()
    private let container: ModelContainer
    private var task: Task<Void, Never>?

    private static let maxInFlight = 3
    private static let cacheBatchSize = 25

    init(container: ModelContainer) {
        self.container = container
    }

    var isRunning: Bool {
        switch stage {
        case .fetching, .analysing, .grouping, .saving: return true
        default: return false
        }
    }

    func start(_ options: Options) {
        guard !isRunning else { return }
        stage = .fetching
        progress = Progress()
        summary = nil
        errorMessage = nil
        startedAt = .now
        finishedAt = nil
        UIApplication.shared.isIdleTimerDisabled = true
        task = Task { [weak self] in
            await self?.run(options)
        }
    }

    func cancel() {
        task?.cancel()
    }

    // MARK: Pipeline

    private func run(_ options: Options) async {
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            finishedAt = .now
            task = nil
        }
        let persistence = PersistenceActor(modelContainer: container)
        do {
            // 1. Fetch snapshots + WhatsApp album membership off the main actor.
            let whatsAppName = options.thresholds.whatsAppAlbumName
            let fetched = await Task.detached(priority: .userInitiated) { () -> (infos: [AssetInfo], whatsApp: Set<String>) in
                let infos = PhotoLibraryService.assetInfos(start: options.start, end: options.end)
                let ids = PhotoLibraryService.albumAssetIDs(titled: whatsAppName)
                return (infos, ids)
            }.value
            var infos = fetched.infos
            if !options.includeScreenshots { infos.removeAll { $0.isScreenshot } }
            if !options.includeWhatsApp { infos.removeAll { fetched.whatsApp.contains($0.id) } }
            try Task.checkCancellation()

            // 2. Cache lookup: reuse scalars; groupable cached assets still need a feature print.
            let cached = try await persistence.cachedMetrics(for: Set(infos.map(\.id)))
            let classifier = Classifier(thresholds: options.thresholds)
            var metricsByID: [String: AssetMetrics] = [:]
            var work: [(AssetInfo, ExtractionMode)] = []
            for info in infos {
                if let hit = cached[info.id], hit.modificationDate == info.modificationDate {
                    var metrics = hit.metrics
                    metrics.inWhatsAppAlbum = fetched.whatsApp.contains(info.id)
                    metrics.isFavorite = info.isFavorite
                    metricsByID[info.id] = metrics
                    if classifier.classify(metrics).isGroupable {
                        work.append((info, .featurePrintOnly))
                    } else {
                        progress.reusedFromCache += 1
                    }
                } else {
                    work.append((info, .full))
                }
            }
            progress.total = work.count
            stage = .analysing
            extractor.resetPrints()

            // 3. Analyse with bounded concurrency; cache results in batches as they arrive.
            let extractor = self.extractor
            let thresholds = options.thresholds
            let whatsApp = fetched.whatsApp
            var pending: [AnalysisEntry] = []
            try await withThrowingTaskGroup(of: ExtractionResult.self) { group in
                var iterator = work.makeIterator()
                func addNext() {
                    guard let (info, mode) = iterator.next() else { return }
                    group.addTask {
                        do {
                            let metrics = try await extractor.extract(info, mode: mode, inWhatsAppAlbum: whatsApp.contains(info.id), thresholds: thresholds)
                            return ExtractionResult(info: info, mode: mode, metrics: metrics, error: nil)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            return ExtractionResult(info: info, mode: mode, metrics: nil, error: error.localizedDescription)
                        }
                    }
                }
                for _ in 0..<Self.maxInFlight { addNext() }
                for try await result in group {
                    progress.done += 1
                    if let error = result.error {
                        progress.failed += 1
                        _ = error
                    } else if let metrics = result.metrics {
                        progress.fullAnalyses += 1
                        metricsByID[metrics.id] = metrics
                        pending.append(AnalysisEntry(metrics: metrics, classification: classifier.classify(metrics), modificationDate: result.info.modificationDate))
                        if pending.count >= Self.cacheBatchSize {
                            try await persistence.upsert(pending)
                            pending.removeAll()
                        }
                    } else {
                        progress.printOnly += 1
                    }
                    addNext()
                }
            }
            try await persistence.upsert(pending)
            pending.removeAll()
            try Task.checkCancellation()

            // 4. Classify → group → score → decide, in Core, off the main actor.
            stage = .grouping
            let allMetrics = Array(metricsByID.values)
            let plan = await Task.detached(priority: .userInitiated) {
                Planner(thresholds: thresholds).plan(metrics: allMetrics) { extractor.distance($0, $1) }
            }.value
            let candidates = allMetrics
                .filter { classifier.classify($0).isGroupable }
                .map(GroupingCandidate.init)
            let distances = await Task.detached(priority: .utility) { () -> [ComparedPair: Float] in
                var table: [ComparedPair: Float] = [:]
                for pair in Grouper(thresholds: thresholds).comparedPairs(for: candidates) {
                    if let d = extractor.distance(pair.a, pair.b) { table[pair] = d }
                }
                return table
            }.value
            calibration = Calibration(candidates: candidates, distances: distances, metricsByID: metricsByID, thresholds: thresholds)

            // 5. Persist the session for the review screens.
            stage = .saving
            let sessionID = try await persistence.saveSession(
                start: options.start, end: options.end, thresholds: thresholds, plan: plan, status: ScanStatus.completed
            )
            summary = Self.summarize(plan, sessionID: sessionID, scanned: infos.count, since: startedAt)
            stage = .completed
        } catch is CancellationError {
            stage = .cancelled
        } catch {
            errorMessage = error.localizedDescription
            stage = .failed
        }
    }

    private static func summarize(_ plan: ScanPlan, sessionID: UUID, scanned: Int, since: Date?) -> Summary {
        var s = Summary()
        s.sessionID = sessionID
        s.groups = plan.groups.count
        s.burstGroups = plan.groups.filter { $0.kind == .burst }.count
        s.photosInGroups = plan.groups.reduce(0) { $0 + $1.memberIDs.count }
        s.keepers = plan.groups.count
        for decision in plan.decisions {
            if decision.groupIndex == nil, decision.category != .personal {
                s.clutter[decision.category, default: 0] += 1
            }
            if decision.action == .delete { s.deleteCandidates += 1 }
        }
        s.favoritesProtected = plan.classifications.values.filter(\.isProtected).count
        s.scanned = scanned
        s.duration = since.map { Date.now.timeIntervalSince($0) } ?? 0
        return s
    }
}

private struct ExtractionResult: Sendable {
    let info: AssetInfo
    let mode: ExtractionMode
    let metrics: AssetMetrics?
    let error: String?
}
