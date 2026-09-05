import XCTest
@testable import PhotoCullCore

final class GrouperTests: XCTestCase {
    let grouper = Grouper()

    private func candidates(_ metrics: [AssetMetrics]) -> [GroupingCandidate] {
        metrics.map(GroupingCandidate.init)
    }

    func testGapOf119SecondsStaysInOneBucket() {
        let g = grouper.groups(for: candidates([asset("a"), asset("b", at: 119)]), distance: allPairs(0))
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].memberIDs, ["a", "b"])
        XCTAssertEqual(g[0].kind, .similar)
    }

    func testGapOfExactly120SecondsStaysInOneBucket() {
        let g = grouper.groups(for: candidates([asset("a"), asset("b", at: 120)]), distance: allPairs(0))
        XCTAssertEqual(g.count, 1)
    }

    func testGapOf121SecondsStartsANewBucket() {
        let g = grouper.groups(for: candidates([asset("a"), asset("b", at: 121)]), distance: allPairs(0))
        XCTAssertTrue(g.isEmpty)
    }

    func testUnionFindIsTransitive() {
        let d = distances([("a", "b", 0.3), ("b", "c", 0.3), ("a", "c", 0.9)])
        let g = grouper.groups(for: candidates([asset("a"), asset("b", at: 1), asset("c", at: 2)]), distance: d)
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].memberIDs, ["a", "b", "c"])
    }

    func testDistanceAboveThresholdDoesNotJoin() {
        let g = grouper.groups(for: candidates([asset("a"), asset("b", at: 1)]), distance: allPairs(0.61))
        XCTAssertTrue(g.isEmpty)
    }

    func testDistanceAtThresholdJoins() {
        let g = grouper.groups(for: candidates([asset("a"), asset("b", at: 1)]), distance: allPairs(0.6))
        XCTAssertEqual(g.count, 1)
    }

    func testMissingFeaturePrintNeverJoins() {
        let g = grouper.groups(for: candidates([asset("a"), asset("b", at: 1)]), distance: { _, _ in nil })
        XCTAssertTrue(g.isEmpty)
    }

    func testBurstGroupingWinsOverTimeBucketing() {
        // Ten minutes apart and no feature prints at all: the shared burst id still groups them.
        let m = [asset("a", burst: "B1"), asset("b", at: 600, burst: "B1"), asset("c", at: 601)]
        let g = grouper.groups(for: candidates(m), distance: { _, _ in nil })
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].kind, .burst)
        XCTAssertEqual(g[0].memberIDs, ["a", "b"])
    }

    func testBurstMembersAreNotAlsoInSimilarGroups() {
        let m = [asset("a", burst: "B1"), asset("b", at: 1, burst: "B1"), asset("c", at: 2)]
        let g = grouper.groups(for: candidates(m), distance: allPairs(0))
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].kind, .burst)
    }

    func testLoneBurstFrameFallsBackToSimilarity() {
        let m = [asset("a", burst: "B1"), asset("b", at: 1)]
        let g = grouper.groups(for: candidates(m), distance: allPairs(0))
        XCTAssertEqual(g.count, 1)
        XCTAssertEqual(g[0].kind, .similar)
    }

    func testBucketIsCappedAtSixtyAssets() {
        let m = (0..<61).map { asset(String(format: "%03d", $0), at: TimeInterval($0)) }
        let g = grouper.groups(for: candidates(m), distance: allPairs(0))
        XCTAssertEqual(g.count, 1, "61 identical assets split into a 60-chunk and a singleton")
        XCTAssertEqual(g[0].memberIDs.count, 60)
    }

    func testSingletonsAreNeverGroups() {
        let g = grouper.groups(for: candidates([asset("a")]), distance: allPairs(0))
        XCTAssertTrue(g.isEmpty)
        for group in grouper.groups(for: candidates([asset("a"), asset("b", at: 1), asset("c", at: 2)]), distance: distances([("a", "b", 0.1)])) {
            XCTAssertGreaterThanOrEqual(group.memberIDs.count, 2)
        }
    }

    func testOutputIsIndependentOfInputOrder() {
        let m = [asset("a"), asset("b", at: 5), asset("c", at: 10), asset("d", at: 500), asset("e", at: 505)]
        let d = distances([("a", "b", 0.1), ("b", "c", 0.1), ("d", "e", 0.2)])
        let forward = grouper.groups(for: candidates(m), distance: d)
        let backward = grouper.groups(for: candidates(m.reversed()), distance: d)
        XCTAssertEqual(forward, backward)
        XCTAssertEqual(forward.map(\.memberIDs), [["a", "b", "c"], ["d", "e"]])
    }
}
