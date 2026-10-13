import XCTest

final class SnapshotTests: XCTestCase {
    func testChangedCard() {
        XCTContext.runActivity(named: "Compare route card without a supplied diff") { activity in
            activity.keep(FixtureImages.card(), named: "RouteCard.expected.png", type: "public.png")
            activity.keep(FixtureImages.card(changed: FixtureMode.isMixed), named: "RouteCard.actual.png", type: "public.png")
            XCTAssertFalse(FixtureMode.isMixed, "Snapshot mismatch: pin moved and changed color.")
        }
    }

    func testResizedCard() {
        XCTContext.runActivity(named: "Compare images of different sizes") { activity in
            activity.keep(FixtureImages.card(), named: "WideCard.expected.png", type: "public.png")
            activity.keep(FixtureImages.card(size: FixtureMode.isMixed ? CGSize(width: 192, height: 112) : CGSize(width: 160, height: 96)),
                          named: "WideCard.actual.png", type: "public.png")
            XCTAssertFalse(FixtureMode.isMixed, "Snapshot size mismatch: expected 160x96, got 192x112.")
        }
    }

    func testProvidedDifferenceAndAliases() {
        XCTContext.runActivity(named: "Compare reference/failure aliases with supplied difference") { activity in
            activity.keep(FixtureImages.card(), named: "AliasedCard.reference.png", type: "public.png")
            activity.keep(FixtureImages.card(changed: FixtureMode.isMixed), named: "AliasedCard.failure.png", type: "public.png")
            if FixtureMode.isMixed {
                activity.keep(FixtureImages.difference(), named: "AliasedCard.difference.png", type: "public.png")
            }
            XCTAssertFalse(FixtureMode.isMixed, "Snapshot mismatch with a supplied difference image.")
        }
    }

    func testMatchingCardWithoutAttachments() {
        // Snapshot libraries generally emit no images when an assertion matches.
        XCTContext.runActivity(named: "Verify matching card without retaining images") { _ in
            XCTAssertEqual(FixtureImages.card(), FixtureImages.card())
        }
    }
}
