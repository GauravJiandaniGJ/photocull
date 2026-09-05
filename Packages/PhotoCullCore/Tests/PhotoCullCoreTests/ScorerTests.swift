import XCTest
@testable import PhotoCullCore

final class ScorerTests: XCTestCase {
    let scorer = Scorer()

    private func scored(_ metrics: [AssetMetrics], kind: GroupKind = .similar) -> ScoredGroup {
        let group = ProposedGroup(kind: kind, memberIDs: metrics.map(\.id))
        return scorer.score(group: group, metrics: Dictionary(uniqueKeysWithValues: metrics.map { ($0.id, $0) }))
    }

    func testClosedEyesLosesToOpenEyesWithEqualQuality() {
        let open = asset("open", faces: [face(eyesOpen: true)])
        let closed = asset("closed", at: 1, faces: [face(eyesOpen: false)])
        let g = scored([open, closed])
        XCTAssertEqual(g.keeperID, "open")
        XCTAssertFalse(g.isTie)
        XCTAssertEqual(g.reasons["closed"], "1 face with eyes closed")
        XCTAssertTrue(g.reasons["open"]!.contains("all eyes open"))
    }

    func testFavoriteWinsWithLowerScore() {
        let sharp = asset("sharp", faces: [face(quality: 0.95, smiling: true)])
        let blurryFavorite = asset("fav", at: 1, favorite: true, faces: [face(quality: 0.2, eyesOpen: false)])
        let g = scored([sharp, blurryFavorite])
        XCTAssertEqual(g.keeperID, "fav")
        XCTAssertEqual(g.reasons["sharp"], "Keeper is a favorite")
        XCTAssertTrue(g.reasons["fav"]!.contains("favorite"))
    }

    func testTieDetectionAtExactlyTheMargin() {
        // 1.0 and 0.75 are exact in binary, so the gap is exactly 0.25.
        let top = MemberScore(assetID: "a", score: 1.0, aesthetics: 1, faceQuality: nil, eyesOpenFraction: nil, smileFraction: nil, resolution: 1, faceCount: 0, closedEyesFaceCount: 0, isFavorite: false)
        let second = MemberScore(assetID: "b", score: 0.75, aesthetics: 1, faceQuality: nil, eyesOpenFraction: nil, smileFraction: nil, resolution: 1, faceCount: 0, closedEyesFaceCount: 0, isFavorite: false)
        XCTAssertEqual(Scorer.tieSet(scores: [top, second], top: 1.0, margin: 0.25).count, 1, "a gap equal to the margin is not a tie")
        XCTAssertEqual(Scorer.tieSet(scores: [top, second], top: 1.0, margin: 0.2500001).count, 2)
    }

    func testIdenticalMembersAreATieResolvedByEarlierDate() {
        let g = scored([asset("later", at: 5), asset("earlier", at: 1)])
        XCTAssertTrue(g.isTie)
        XCTAssertEqual(g.keeperID, "earlier")
        XCTAssertEqual(g.localTieBreak, .earlierDate)
        XCTAssertEqual(g.reasons["later"], "Near-identical; keeper was taken first")
    }

    func testTieIsResolvedByHigherAestheticsFirst() {
        // Both have faces of equal quality; aesthetics differ by a hair so scores are within the margin.
        let a = asset("a", aesthetics: 0.50, faces: [face()])
        let b = asset("b", at: 1, aesthetics: 0.52, faces: [face()])
        let g = scored([a, b])
        XCTAssertTrue(g.isTie)
        XCTAssertEqual(g.keeperID, "b")
        XCTAssertEqual(g.localTieBreak, .higherAesthetics)
    }

    func testNoFaceGroupUsesAestheticsOnlyFormula() {
        let m = asset("a", pixels: 100, aesthetics: 0.5)
        let s = scorer.score(m, maxPixelCount: 100)
        let expectedAesthetics: Float = (0.5 + 1) / 2
        XCTAssertNil(s.faceQuality)
        XCTAssertEqual(s.score, 0.9 * expectedAesthetics + 0.1 * 1, accuracy: 1e-6)
        let smaller = scorer.score(asset("b", pixels: 50, aesthetics: 0.5), maxPixelCount: 100)
        XCTAssertEqual(smaller.score, 0.9 * expectedAesthetics, accuracy: 1e-6)
    }

    func testFaceFormulaWeights() {
        let m = asset("a", pixels: 100, aesthetics: 0, faces: [face(quality: 0.8, eyesOpen: true, smiling: true)])
        let s = scorer.score(m, maxPixelCount: 100)
        // faceQ = 0.6*0.8 + 0.4*0.8 = 0.8; aesthetics = 0.5; eyes = 1; smile = 1; res = 1
        let expected: Float = (0.40 * 0.8) + (0.25 * 0.5) + 0.20 + 0.10 + 0.05
        XCTAssertEqual(s.score, expected, accuracy: 1e-6)
    }

    func testTinyFacesAreIgnored() {
        let m = asset("a", faces: [face(eyesOpen: false, size: 0.05)]) // area 0.0025 < 0.01
        let s = scorer.score(m, maxPixelCount: m.pixelCount)
        XCTAssertEqual(s.faceCount, 0)
        XCTAssertNil(s.eyesOpenFraction)
    }

    func testLowerFaceQualityReasonShowsBothValues() {
        let sharp = asset("sharp", faces: [face(quality: 0.9)])
        let soft = asset("soft", at: 1, faces: [face(quality: 0.3)])
        let g = scored([sharp, soft])
        XCTAssertEqual(g.keeperID, "sharp")
        XCTAssertEqual(g.reasons["soft"], "Lower face quality (0.30 vs 0.90)")
    }

    func testEveryMemberHasANonEmptyReason() {
        let members = [
            asset("a", faces: [face()]),
            asset("b", at: 1, faces: [face(eyesOpen: false)]),
            asset("c", at: 2),
            asset("d", at: 3, favorite: true),
        ]
        let g = scored(members)
        XCTAssertEqual(g.reasons.count, members.count)
        for id in members.map(\.id) {
            XCTAssertFalse((g.reasons[id] ?? "").isEmpty, "no reason for \(id)")
        }
    }

    func testReplacingKeeperRebuildsReasons() {
        let a = asset("a", faces: [face(quality: 0.9)])
        let b = asset("b", at: 1, faces: [face(quality: 0.3)])
        let g = scored([a, b])
        let overridden = scorer.replacingKeeper(in: g, with: "b", keeperReason: "Claude: better expression")
        XCTAssertEqual(overridden.keeperID, "b")
        XCTAssertEqual(overridden.reasons["b"], "Claude: better expression")
        XCTAssertFalse(overridden.reasons["a"]!.isEmpty)
        XCTAssertNil(overridden.localTieBreak)
        XCTAssertEqual(overridden.scores, g.scores)
    }
}
