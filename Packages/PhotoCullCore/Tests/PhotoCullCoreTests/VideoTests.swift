import XCTest
@testable import PhotoCullCore

final class VideoTests: XCTestCase {
    private func video(
        _ id: String, at seconds: TimeInterval = 0, duration: Double = 10, w: Int = 1080, h: Int = 1920, size: Int64 = 50_000_000,
        favorite: Bool = false, whatsApp: Bool = false, camera: Bool? = true, screen: Bool = false
    ) -> VideoMetrics {
        VideoMetrics(id: id, creationDate: t0.addingTimeInterval(seconds), duration: duration, pixelWidth: w, pixelHeight: h,
                     fileSizeBytes: size, isFavorite: favorite, inWhatsAppAlbum: whatsApp, hasCameraMetadata: camera, looksLikeScreenRecording: screen)
    }

    // Classifier

    func testFavoriteVideoIsProtected() {
        let c = VideoClassifier().classify(video("a", favorite: true, screen: true))
        XCTAssertEqual(c.category, .personalVideo)
        XCTAssertTrue(c.isProtected)
    }

    func testScreenRecordingIsDeleteCandidate() {
        let c = VideoClassifier().classify(video("a", camera: false, screen: true))
        XCTAssertEqual(c.category, .screenRecording)
        XCTAssertEqual(c.defaultAction, .delete)
        XCTAssertFalse(c.isGroupable)
    }

    func testWhatsAppVideoIsReceivedEvenIfScreenSized() {
        let c = VideoClassifier().classify(video("a", whatsApp: true, camera: false, screen: true))
        XCTAssertEqual(c.category, .receivedVideo)
        XCTAssertEqual(c.defaultAction, .keep)
        XCTAssertTrue(c.isGroupable)
    }

    func testNoCameraMetadataIsReceived() {
        XCTAssertEqual(VideoClassifier().classify(video("a", camera: false)).category, .receivedVideo)
        XCTAssertEqual(VideoClassifier().classify(video("a", camera: nil)).category, .personalVideo)
    }

    // Grouper

    func testExactDuplicatesGroupAcrossTime() {
        let a = video("a", duration: 12.3, size: 1234)
        let b = video("b", at: 86_400 * 3, duration: 12.3, size: 1234)
        let g = VideoGrouper().groups(for: [a, b], distance: { _, _ in nil })
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].kind, .duplicate)
        XCTAssertEqual(g[0].memberIDs, ["a", "b"])
    }

    func testUnknownSizeNeverCountsAsDuplicate() {
        let g = VideoGrouper().groups(for: [video("a", size: 0), video("b", at: 1, size: 0)], distance: { _, _ in nil })
        XCTAssertTrue(g.isEmpty)
    }

    func testSimilarTakesNeedComparableDuration() {
        let close = VideoGrouper().groups(for: [video("a", duration: 10), video("b", at: 5, duration: 11, size: 60_000_000)], distance: { _, _ in 0.01 })
        XCTAssertEqual(close.count, 1)
        XCTAssertEqual(close[0].kind, .similar)
        let far = VideoGrouper().groups(for: [video("a", duration: 10), video("b", at: 5, duration: 30, size: 60_000_000)], distance: { _, _ in 0.01 })
        XCTAssertTrue(far.isEmpty)
    }

    func testVideoThresholdIsIndependentOfPhotoThreshold() {
        let t = Thresholds(similarityDistanceMax: 0.01, videoSimilarityDistanceMax: 0.5)
        let g = VideoGrouper(thresholds: t).groups(for: [video("a"), video("b", at: 5, size: 60_000_000)], distance: { _, _ in 0.4 })
        XCTAssertEqual(g.count, 1)
    }

    // Scorer

    func testHigherResolutionWins() {
        let a = video("a", w: 1080, h: 1920, size: 40_000_000)
        let b = video("b", at: 1, w: 2160, h: 3840, size: 120_000_000)
        let g = VideoScorer().score(group: ProposedGroup(kind: .similar, memberIDs: ["a", "b"]), metrics: ["a": a, "b": b])
        XCTAssertEqual(g.keeperID, "b")
        XCTAssertEqual(g.reasons["a"], "Lower resolution (1080×1920 vs 2160×3840)")
        XCTAssertTrue(g.reasons["b"]!.contains("highest resolution"))
        XCTAssertEqual(g.scores.first { $0.assetID == "b" }?.pixelWidth, 2160)
    }

    func testDuplicateReasonAndLargerFileTieBreak() {
        let a = video("a", size: 50_000_000)
        let b = video("b", at: 1, size: 50_000_000)
        let g = VideoScorer().score(group: ProposedGroup(kind: .duplicate, memberIDs: ["a", "b"]), metrics: ["a": a, "b": b])
        XCTAssertEqual(g.keeperID, "a", "identical files: earlier wins")
        XCTAssertTrue(g.isTie)
        XCTAssertEqual(g.reasons["b"], "Exact duplicate of keeper")
    }

    func testFavoriteVideoWinsWithLowerResolution() {
        let a = video("a", w: 2160, h: 3840)
        let b = video("b", at: 1, w: 720, h: 1280, favorite: true)
        let g = VideoScorer().score(group: ProposedGroup(kind: .similar, memberIDs: ["a", "b"]), metrics: ["a": a, "b": b])
        XCTAssertEqual(g.keeperID, "b")
        XCTAssertEqual(g.reasons["a"], "Keeper is a favorite")
    }

    // Planner

    func testVideoPlanIsDeterministicAndKeepsScreenRecordingsOutOfGroups() {
        let m = [
            video("take1", duration: 8), video("take2", at: 3, duration: 8.5, size: 70_000_000),
            video("rec", at: 4, duration: 8, camera: false, screen: true),
            video("fwd", at: 500, whatsApp: true, camera: false),
        ]
        let d: (String, String) -> Float? = { _, _ in 0.01 }
        let a = VideoPlanner().plan(metrics: m, distance: d)
        let b = VideoPlanner().plan(metrics: m.reversed(), distance: d)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.groups.count, 1)
        XCTAssertEqual(a.groups[0].memberIDs, ["take1", "take2"])
        XCTAssertEqual(a.decisions.first { $0.assetID == "rec" }?.action, .delete)
        XCTAssertEqual(a.decisions.first { $0.assetID == "fwd" }?.action, .keep)
        XCTAssertEqual(a.decisions.first { $0.assetID == "take1" }?.action, .delete)
        for dec in a.decisions { XCTAssertFalse(dec.reason.isEmpty) }
    }

    func testMemberScoreDecodesWithoutVideoFields() throws {
        let json = #"{"assetID":"x","score":0.5,"aesthetics":0.5,"resolution":1,"faceCount":0,"closedEyesFaceCount":0,"isFavorite":false}"#
        let s = try JSONDecoder().decode(MemberScore.self, from: Data(json.utf8))
        XCTAssertNil(s.duration)
        XCTAssertFalse(s.isVideo)
    }
}
