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

    func testGestureTiming() throws {
        let pad = app.descendants(matching: .any)["gesture-pad"].firstMatch
        XCTAssertTrue(pad.waitForExistence(timeout: 5))
        XCTContext.runActivity(named: "Tap, swipe and drag") { _ in
            app.buttons["pin-route"].tap()
            pad.swipeLeft()
            pad.swipeUp()
            let start = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
            let end = pad.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            start.press(forDuration: 0.4, thenDragTo: end, withVelocity: 200, thenHoldForDuration: 0.3)
            app.buttons["pin-route"].tap()
        }
        try XCTContext.runActivity(named: "Attach the app's touch log") { activity in
            // The app records when it actually received each touch: the oracle for the overlay.
            let log = try XCTUnwrap(app.staticTexts["touch-log"].value as? String)
            let attachment = XCTAttachment(data: Data(log.utf8), uniformTypeIdentifier: "public.json")
            attachment.name = "touch-log.json"
            attachment.lifetime = .keepAlways
            activity.add(attachment)
            let touches = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(log.utf8)) as? [[String: Any]])
            XCTAssertEqual(touches.count, 5, "Expected one logged touch per interaction")
            XCTAssertTrue(touches.allSatisfy { $0["up"] != nil }, "A touch never ended")
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
