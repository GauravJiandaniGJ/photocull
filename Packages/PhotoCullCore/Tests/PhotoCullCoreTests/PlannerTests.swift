import XCTest
@testable import PhotoCullCore

final class PlannerTests: XCTestCase {
    let planner = Planner()

    private var library: [AssetMetrics] {
        [
            asset("burst1", burst: "B", faces: [face(quality: 0.9)]),
            asset("burst2", at: 1, burst: "B", faces: [face(quality: 0.5, eyesOpen: false)]),
            asset("sim1", at: 300, aesthetics: 0.4),
            asset("sim2", at: 302, aesthetics: 0.1),
            asset("lone", at: 900),
            asset("shot", at: 1000, screenshot: true),
            asset("wa", at: 1100, whatsApp: true, uti: "public.jpeg", exif: false, text: 200),
            asset("fav", at: 1200, screenshot: true, favorite: true),
            asset("receipt", at: 1300, utility: true),
        ]
    }

    private let table = distances([("sim1", "sim2", 0.2)])

    func testSameMetricsInSameDecisionsOut() {
        let a = planner.plan(metrics: library, distance: table)
        let b = planner.plan(metrics: library, distance: table)
        XCTAssertEqual(a, b)
    }

    func testInputOrderDoesNotChangeThePlan() {
        let a = planner.plan(metrics: library, distance: table)
        let b = planner.plan(metrics: library.reversed(), distance: table)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.decisions.map(\.assetID), library.map(\.id))
    }

    func testDecisionsFollowClassifierAndScorer() {
        let plan = planner.plan(metrics: library, distance: table)
        func decision(_ id: String) -> ProposedDecision { plan.decisions.first { $0.assetID == id }! }

        XCTAssertEqual(plan.groups.count, 2)
        XCTAssertEqual(decision("burst1").action, .keep)
        XCTAssertEqual(decision("burst2").action, .delete)
        XCTAssertEqual(decision("burst2").reason, "1 face with eyes closed")
        XCTAssertEqual(decision("sim1").action, .keep)
        XCTAssertEqual(decision("sim2").action, .delete)
        XCTAssertEqual(decision("lone").action, .keep)
        XCTAssertNil(decision("lone").groupIndex)
        XCTAssertEqual(decision("shot").action, .delete)
        XCTAssertEqual(decision("wa").action, .delete)
        XCTAssertEqual(decision("wa").category, .receivedUtility)
        XCTAssertEqual(decision("receipt").action, .delete)
        XCTAssertEqual(decision("fav").action, .keep)
        XCTAssertEqual(decision("fav").category, .personal)
        for d in plan.decisions {
            XCTAssertEqual(d.source, .auto)
            XCTAssertFalse(d.reason.isEmpty, "no reason for \(d.assetID)")
        }
    }

    func testFavoriteIsNeverADeleteCandidateEvenAsGroupLoser() {
        // Two favorites in one group: one must lose on score but still be kept.
        let m = [
            asset("favA", favorite: true, faces: [face(quality: 0.9)]),
            asset("favB", at: 1, favorite: true, faces: [face(quality: 0.2, eyesOpen: false)]),
        ]
        let plan = planner.plan(metrics: m, distance: allPairs(0))
        XCTAssertEqual(plan.groups.count, 1)
        XCTAssertEqual(plan.groups[0].keeperID, "favA")
        let loser = plan.decisions.first { $0.assetID == "favB" }!
        XCTAssertEqual(loser.action, .keep)
        XCTAssertEqual(loser.reason, "Favorite (protected)")
        XCTAssertTrue(plan.deleteCandidateIDs.isEmpty)
    }

    func testEveryGroupHasExactlyOneKeeperWhoIsAMember() {
        let plan = planner.plan(metrics: library, distance: table)
        for (i, g) in plan.groups.enumerated() {
            XCTAssertTrue(g.memberIDs.contains(g.keeperID))
            XCTAssertGreaterThanOrEqual(g.memberIDs.count, 2)
            let keepers = plan.decisions.filter { $0.groupIndex == i && $0.assetID == g.keeperID }
            XCTAssertEqual(keepers.count, 1)
            XCTAssertEqual(keepers[0].action, .keep)
        }
    }

    func testClutterNeverEntersGroups() {
        // A screenshot and a receipt taken within the same second as a similar pair stay out.
        let m = [
            asset("p1", aesthetics: 0.5), asset("p2", at: 1, aesthetics: 0.5),
            asset("s", at: 1, screenshot: true), asset("r", at: 1, utility: true),
        ]
        let plan = planner.plan(metrics: m, distance: allPairs(0))
        XCTAssertEqual(plan.groups.count, 1)
        XCTAssertEqual(plan.groups[0].memberIDs, ["p1", "p2"])
    }
}
