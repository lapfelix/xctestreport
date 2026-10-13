import XCTest

final class JourneyUITests: XCTestCase {
    private var app: XCUIApplication!
    private var isMixed: Bool { ProcessInfo.processInfo.environment["FIXTURE_SCENARIO"] == "mixed" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.staticTexts["journey-title"].waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    private func capture(_ name: String, in activity: XCTActivity) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        activity.add(attachment)
    }

    private func attachPinState(in activity: XCTActivity) throws {
        let state: [String: Any] = [
            "route": "Green line", "city": "Montréal",
            "pinned": app.staticTexts["pin-state"].label == "Pinned",
            "scenario": isMixed ? "mixed" : "baseline"
        ]
        let attachment = XCTAttachment(
            data: try JSONSerialization.data(withJSONObject: state, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "pin-state.json"
        attachment.lifetime = .keepAlways
        activity.add(attachment)
    }

    func testPinRoute() throws {
        try XCTContext.runActivity(named: "Open journey") { activity in
            capture("Journey before pinning", in: activity)
            XCTContext.runActivity(named: "Pin Green line") { _ in
                app.buttons["pin-route"].tap()
            }
            try XCTContext.runActivity(named: "Verify and capture pin state") { nested in
                XCTAssertEqual(app.staticTexts["pin-state"].label, "Pinned")
                capture("Journey after pinning", in: nested)
                try attachPinState(in: nested)
            }
        }
    }

    func testSearchRoutes() {
        XCTContext.runActivity(named: "Search for Orange line") { _ in
            XCTContext.runActivity(named: "Enter search query") { _ in
                let search = app.textFields["route-search"]
                search.tap()
                search.typeText("Orange")
            }
            XCTContext.runActivity(named: "Verify filtered routes") { activity in
                XCTAssertTrue(app.descendants(matching: .any)["route-Orange line"].firstMatch.waitForExistence(timeout: 5))
                XCTAssertFalse(app.descendants(matching: .any)["route-Green line"].firstMatch.exists)
                let attachment = XCTAttachment(string: "Query: Orange\nVisible: Orange line\nHidden: Green line")
                attachment.name = "search-results.txt"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
                // No explicit screenshot: this is video-only under the Mixed plan.
            }
        }
    }

    func testFailureWithScreenshotAndHierarchy() {
        XCTContext.runActivity(named: "Verify pin state after tapping") { activity in
            app.buttons["pin-route"].tap()
            capture("Pin failure context", in: activity)
            let attachment = XCTAttachment(string: app.debugDescription)
            attachment.name = "accessibility-hierarchy.txt"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
            // XCTest also records its own diagnostic snapshot and synthesized input events.
            XCTAssertEqual(app.staticTexts["pin-state"].label, isMixed ? "Not pinned" : "Pinned",
                           "Fixture UI failure: the deliberately wrong pin-state expectation.")
        }
    }
}
