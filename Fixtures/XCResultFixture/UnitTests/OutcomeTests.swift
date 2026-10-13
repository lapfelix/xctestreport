import Foundation
import XCTest

final class OutcomeTests: XCTestCase {
    private static var retryAttempts = 0

    func testPassingAssertion() {
        XCTContext.runActivity(named: "Verify a plain assertion without attachments") { _ in
            XCTAssertEqual(2 + 2, 4)
        }
    }

    func testSkippedWithReason() throws {
        try XCTContext.runActivity(named: "Check subscription eligibility") { _ in
            try XCTSkipIf(FixtureMode.isMixed, "Fixture: offline account has no subscription; skip billing checks.")
            XCTContext.runActivity(named: "Verify billing access") { _ in
                XCTAssertTrue(true)
            }
        }
    }

    func testExpectedFailure() {
        XCTContext.runActivity(named: "Verify fare rounding") { _ in
            if FixtureMode.isMixed {
                XCTExpectFailure("Fixture: known fare rounding bug") {
                    XCTAssertEqual(1.99, 2.00, "Known discrepancy of one cent.")
                }
            } else {
                XCTAssertEqual(2.00, 2.00)
            }
        }
    }

    func testMultipleFailuresInNestedStep() {
        continueAfterFailure = true
        XCTContext.runActivity(named: "Verify response") { _ in
            XCTContext.runActivity(named: "Validate status & route name <rail>") { activity in
                if FixtureMode.isMixed {
                    activity.keepText("HTTP 503\nNo routes returned.\nThis attachment belongs to the failing step.", named: "failure-context.txt")
                    recordFixtureFailure()
                    XCTAssertEqual("Orange", "Green", "Wrong route: expected Green, got Orange.\nSecond issue in the same activity.")
                } else {
                    activity.keepText("HTTP 200\nRoute: Green", named: "response-context.txt")
                    XCTAssertEqual("Green", "Green")
                }
            }
        }
    }

    func testThrownError() throws {
        try XCTContext.runActivity(named: "Request route service") { _ in
            try XCTContext.runActivity(named: "Decode service response") { activity in
                activity.keepText(FixtureMode.isMixed ? "Service is deliberately unavailable." : "Service returned HTTP 200.",
                                  named: "service.log")
                if FixtureMode.isMixed { throw FixtureFailure.offline }
            }
        }
    }

    func testFailsOnceThenPasses() {
        Self.retryAttempts += 1
        XCTContext.runActivity(named: "Connect to route service") { _ in
            XCTContext.runActivity(named: "Connection attempt \(Self.retryAttempts)") { activity in
                activity.keepText("Attempt \(Self.retryAttempts)", named: "attempt.txt")
                XCTAssertTrue(!FixtureMode.isMixed || Self.retryAttempts > 1,
                              "Fixture: first connection attempt fails; retry succeeds.")
            }
        }
    }
}
