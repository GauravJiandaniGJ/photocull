import Foundation
import Observation
import PhotoCullCore
import SwiftData
import UIKit

/// Runs one scan end to end (spec §3 data flow, plus the video pass of milestone 7) and
/// publishes progress for the Scan screen. Nothing here deletes anything.
@MainActor
@Observable
final class ScanController {
    enum Stage: Equatable {
        case idle, fetching, analysing, analysingVideos, grouping, saving, completed, cancelled, failed

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .fetching: return "Fetching…"
            case .analysing: return "Analysing photos"
            case .analysingVideos: return "Analysing videos"
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
        var includeVideos: Bool
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
        var videos = 0
        var videoGroups = 0
        var bytesToFree: Int64 = 0
        var duration: TimeInterval = 0
    }

    /// Everything the Calibrate view needs (photos only), kept for the session.
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
    let videoExtractor = VideoFeatureExtractor()
    private let container: ModelContainer
    private var task: Task<Void, Never>?

    private static let maxInFlight = 3
    private static let maxVideosInFlight = 2
    private static let cacheBatchSize = 25

    init(container: ModelContainer) {
        self.container = container
    }

    var isRunning: Bool {
        switch stage {
        case .fetching, .analysing, .analysingVideos, .grouping, .saving: return true
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
        AppLog.info(.scan, "Scan started: \(options.start.formatted(date: .abbreviated, time: .omitted)) – \(options.end.formatted(date: .abbreviated, time: .omitted)), WhatsApp \(options.includeWhatsApp ? "on" : "off"), screenshots \(options.includeScreenshots ? "on" : "off"), videos \(options.includeVideos ? "on" : "off"), similarity ≤ \(options.thresholds.similarityDistanceMax)")
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
        let thresholds = options.thresholds
        do {
            // 1. Snapshots + WhatsApp album membership off the main actor.
            let whatsAppName = thresholds.whatsAppAlbumName
            let includeVideos = options.includeVideos
            let fetched = await Task.detached(priority: .userInitiated) { () -> (photos: [AssetInfo], videos: [AssetInfo], whatsApp: Set<String>) in
                let photos = PhotoLibraryService.assetInfos(start: options.start, end: options.end, mediaType: .image)
                let videos = includeVideos ? PhotoLibraryService.assetInfos(start: options.start, end: options.end, mediaType: .video) : []
                let ids = PhotoLibraryService.albumAssetIDs(titled: whatsAppName)
                return (photos, videos, ids)
            }.value
            var photos = fetched.photos
            if !options.includeScreenshots { photos.removeAll { $0.isScreenshot } }
            if !options.includeWhatsApp { photos.removeAll { fetched.whatsApp.contains($0.id) } }
            let videos = fetched.videos
            try Task.checkCancellation()

            // 2. Photos.
            let cached = try await persistence.cachedMetrics(for: Set(photos.map(\.id) + videos.map(\.id)))
            let photoPlan = try await analysePhotos(photos, cached: cached, whatsApp: fetched.whatsApp, thresholds: thresholds, persistence: persistence)
            try Task.checkCancellation()

            // 3. Videos.
            var bundles = [photoPlan]
            var videoMetrics: [VideoMetrics] = []
            if includeVideos, !videos.isEmpty {
                let (bundle, metrics) = try await analyseVideos(videos, cached: cached, whatsApp: fetched.whatsApp, thresholds: thresholds, persistence: persistence)
                bundles.append(bundle)
                videoMetrics = metrics
            }
            try Task.checkCancellation()

            // 4. Persist the session for the review screens.
            stage = .saving
            let sessionID = try await persistence.saveSession(
                start: options.start, end: options.end, thresholds: thresholds, bundles: bundles, status: ScanStatus.completed
            )
            summary = Self.summarize(bundles, sessionID: sessionID, scanned: photos.count, videos: videoMetrics.count, since: startedAt)
            stage = .completed
            if let s = summary {
                AppLog.info(.scan, "Scan finished in \(Int(s.duration))s: \(s.scanned) photos + \(s.videos) videos (\(progress.fullAnalyses) analysed, \(progress.printOnly) re-fingerprinted, \(progress.reusedFromCache) reused), \(s.groups) groups, \(s.deleteCandidates) delete candidates, \(ByteCountFormatter.string(fromByteCount: s.bytesToFree, countStyle: .file)) of video")
            }
        } catch is CancellationError {
            stage = .cancelled
            AppLog.warning(.scan, "Scan cancelled after \(progress.done)/\(progress.total) items; cache kept")
        } catch {
            errorMessage = error.localizedDescription
            stage = .failed
            AppLog.error(.scan, "Scan failed: \(error.localizedDescription)")
        }
    }

    // MARK: Photos

    private func analysePhotos(_ infos: [AssetInfo], cached: [String: CachedMetrics], whatsApp: Set<String>, thresholds: Thresholds, persistence: PersistenceActor) async throws -> PlanBundle {
        let classifier = Classifier(thresholds: thresholds)
        var metricsByID: [String: AssetMetrics] = [:]
        var work: [(AssetInfo, ExtractionMode)] = []
        for info in infos {
            if let hit = cached[info.id], case .photo(var metrics) = hit.metrics, hit.modificationDate == info.modificationDate {
                metrics.inWhatsAppAlbum = whatsApp.contains(info.id)
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
        progress.done = 0
        stage = .analysing
        extractor.resetPrints()

        let extractor = self.extractor
        var pending: [AnalysisEntry] = []
        var failures: [String] = []
        try await withThrowingTaskGroup(of: PhotoResult.self) { group in
            var iterator = work.makeIterator()
            func addNext() {
                guard let (info, mode) = iterator.next() else { return }
                group.addTask {
                    do {
                        let metrics = try await extractor.extract(info, mode: mode, inWhatsAppAlbum: whatsApp.contains(info.id), thresholds: thresholds)
                        return PhotoResult(info: info, metrics: metrics, error: nil)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return PhotoResult(info: info, metrics: nil, error: error.localizedDescription)
                    }
                }
            }
            for _ in 0..<Self.maxInFlight { addNext() }
            for try await result in group {
                progress.done += 1
                if let error = result.error {
                    progress.failed += 1
                    if failures.count < 5 { failures.append("\(result.info.id.prefix(8))…: \(error)") }
                } else if let metrics = result.metrics {
                    progress.fullAnalyses += 1
                    metricsByID[metrics.id] = metrics
                    pending.append(AnalysisEntry(metrics: .photo(metrics), classification: classifier.classify(metrics), modificationDate: result.info.modificationDate))
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
        if progress.failed > 0 {
            AppLog.warning(.scan, "\(progress.failed) photos failed analysis, e.g. \(failures.joined(separator: "; "))")
        }
        try Task.checkCancellation()

        stage = .grouping
        let all = Array(metricsByID.values)
        let plan = await Task.detached(priority: .userInitiated) {
            Planner(thresholds: thresholds).plan(metrics: all) { extractor.distance($0, $1) }
        }.value
        let candidates = all.filter { classifier.classify($0).isGroupable }.map(GroupingCandidate.init)
        let distances = await Task.detached(priority: .utility) { () -> [ComparedPair: Float] in
            var table: [ComparedPair: Float] = [:]
            for pair in Grouper(thresholds: thresholds).comparedPairs(for: candidates) {
                if let d = extractor.distance(pair.a, pair.b) { table[pair] = d }
            }
            return table
        }.value
        calibration = Calibration(candidates: candidates, distances: distances, metricsByID: metricsByID, thresholds: thresholds)

        let dates = Dictionary(all.map { ($0.id, $0.creationDate) }, uniquingKeysWith: { a, _ in a })
        return PlanBundle(plan: plan, mediaType: "image", dates: dates, sizes: [:], durations: [:])
    }

    // MARK: Videos

    private func analyseVideos(_ infos: [AssetInfo], cached: [String: CachedMetrics], whatsApp: Set<String>, thresholds: Thresholds, persistence: PersistenceActor) async throws -> (PlanBundle, [VideoMetrics]) {
        let classifier = VideoClassifier()
        var metricsByID: [String: VideoMetrics] = [:]
        var work: [(AssetInfo, ExtractionMode)] = []
        for info in infos {
            if let hit = cached[info.id], case .video(var metrics) = hit.metrics, hit.modificationDate == info.modificationDate {
                metrics.inWhatsAppAlbum = whatsApp.contains(info.id)
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
        progress.done = 0
        stage = .analysingVideos
        videoExtractor.resetPrints()

        let extractor = self.videoExtractor
        var pending: [AnalysisEntry] = []
        var failed = 0
        try await withThrowingTaskGroup(of: VideoResult.self) { group in
            var iterator = work.makeIterator()
            func addNext() {
                guard let (info, mode) = iterator.next() else { return }
                group.addTask {
                    do {
                        let metrics = try await extractor.extract(info, mode: mode, inWhatsAppAlbum: whatsApp.contains(info.id), thresholds: thresholds)
                        return VideoResult(info: info, metrics: metrics, failed: false)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        return VideoResult(info: info, metrics: nil, failed: true)
                    }
                }
            }
            for _ in 0..<Self.maxVideosInFlight { addNext() }
            for try await result in group {
                progress.done += 1
                if result.failed {
                    failed += 1
                    progress.failed += 1
                } else if let metrics = result.metrics {
                    progress.fullAnalyses += 1
                    metricsByID[metrics.id] = metrics
                    pending.append(AnalysisEntry(metrics: .video(metrics), classification: classifier.classify(metrics), modificationDate: result.info.modificationDate))
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
        if failed > 0 { AppLog.warning(.scan, "\(failed) videos failed analysis") }
        try Task.checkCancellation()

        stage = .grouping
        let all = Array(metricsByID.values)
        let plan = await Task.detached(priority: .userInitiated) {
            VideoPlanner(thresholds: thresholds).plan(metrics: all) { extractor.distance($0, $1) }
        }.value
        let bundle = PlanBundle(
            plan: plan,
            mediaType: "video",
            dates: Dictionary(all.map { ($0.id, $0.creationDate) }, uniquingKeysWith: { a, _ in a }),
            sizes: Dictionary(all.map { ($0.id, $0.fileSizeBytes) }, uniquingKeysWith: { a, _ in a }),
            durations: Dictionary(all.map { ($0.id, $0.duration) }, uniquingKeysWith: { a, _ in a })
        )
        return (bundle, all)
    }

    // MARK: Summary

    private static func summarize(_ bundles: [PlanBundle], sessionID: UUID, scanned: Int, videos: Int, since: Date?) -> Summary {
        var s = Summary()
        s.sessionID = sessionID
        for bundle in bundles {
            let plan = bundle.plan
            let isVideo = bundle.mediaType == "video"
            if isVideo {
                s.videoGroups += plan.groups.count
            } else {
                s.groups += plan.groups.count
                s.burstGroups += plan.groups.filter { $0.kind == .burst }.count
                s.photosInGroups += plan.groups.reduce(0) { $0 + $1.memberIDs.count }
                s.keepers += plan.groups.count
            }
            for decision in plan.decisions {
                if decision.groupIndex == nil, decision.category != .personal {
                    s.clutter[decision.category, default: 0] += 1
                }
                if decision.action == .delete {
                    s.deleteCandidates += 1
                    if isVideo { s.bytesToFree += bundle.sizes[decision.assetID] ?? 0 }
                }
            }
            s.favoritesProtected += plan.classifications.values.filter(\.isProtected).count
        }
        s.scanned = scanned
        s.videos = videos
        s.duration = since.map { Date.now.timeIntervalSince($0) } ?? 0
        return s
    }
}

private struct PhotoResult: Sendable {
    let info: AssetInfo
    let metrics: AssetMetrics?
    let error: String?
}

private struct VideoResult: Sendable {
    let info: AssetInfo
    let metrics: VideoMetrics?
    let failed: Bool
}
