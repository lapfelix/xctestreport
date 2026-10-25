import XCTest

// Only the Performance test plan runs these.
final class PerformanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func options(iterations: Int, _ invocation: XCTMeasureOptions.InvocationOptions = []) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        options.invocationOptions = invocation
        return options
    }

    private func launchList() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-FixturePerformanceList"]
        app.launch()
        XCTAssertTrue(app.collectionViews["perf-list"].waitForExistence(timeout: 10))
        return app
    }

    func testLaunchPerformance() {
        let metrics = [XCTApplicationLaunchMetric(), XCTApplicationLaunchMetric(waitUntilResponsive: true)]
        measure(metrics: metrics, options: options(iterations: 2)) {
            XCUIApplication().launch()
        }
    }

    func testScrollDeceleration() {
        let app = launchList()
        let list = app.collectionViews["perf-list"]
        var metrics: [XCTMetric] = [XCTOSSignpostMetric.scrollDecelerationMetric,
                                    XCTOSSignpostMetric.scrollDraggingMetric,
                                    XCTOSSignpostMetric.scrollingAndDecelerationMetric]
        // Simulators record no hitch measurements; devices do.
        if #available(iOS 26.0, *) {
            metrics.append(XCTHitchMetric(application: app))
        }
        measure(metrics: metrics, options: options(iterations: 2, .manuallyStop)) {
            list.swipeUp(velocity: .fast)
            stopMeasuring()
            list.swipeDown(velocity: .fast)
        }
    }

    func testNavigationWithAppMetrics() {
        let app = launchList()
        let metrics: [XCTMetric] = [
            XCTClockMetric(),
            XCTCPUMetric(application: app),
            XCTMemoryMetric(application: app),
            XCTOSSignpostMetric.navigationTransitionMetric,
            XCTOSSignpostMetric(subsystem: "dev.xctestreport.fixture.FixtureApp", category: "Performance",
                                name: "Load departures"),
        ]
        measure(metrics: metrics, options: options(iterations: 2)) {
            app.buttons["Stop 3"].tap()
            XCTAssertTrue(app.collectionViews["perf-detail"].waitForExistence(timeout: 5))
            app.navigationBars.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.buttons["Stop 3"].waitForExistence(timeout: 5))
        }
    }
}
