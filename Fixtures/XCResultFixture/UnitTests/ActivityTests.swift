import Foundation
import XCTest

final class ActivityTests: XCTestCase {
    func testNestedActivitiesAndAttachments() throws {
        try XCTContext.runActivity(named: "Plan a journey: Montréal → Downtown") { outer in
            outer.keepText("Start journey\nRoute: Green line\nQuoted: <route> & \"station\"", named: "journey.log")
            try XCTContext.runActivity(named: "Load offline response") { activity in
                activity.keep(Data(#"{"city":"Montréal","routes":["Green","Orange"],"online":false}"#.utf8),
                              named: "response.json", type: "public.json")
                let state: [String: Any] = [
                    "selectedRoute": "Green", "pinned": true,
                    "rows": (0..<100).map { ["index": $0, "label": "Station \($0)"] }
                ]
                let binary = try PropertyListSerialization.data(fromPropertyList: state, format: .binary, options: 0)
                activity.keep(binary, named: "route-state.plist", type: "com.apple.binary-property-list")
                let xml = try PropertyListSerialization.data(fromPropertyList: state, format: .xml, options: 0)
                activity.keep(xml, named: "route-state-xml.plist", type: "com.apple.xml-property-list")
                XCTContext.runActivity(named: "Decode → validate → render") { nested in
                    nested.keep(FixtureImages.card(), named: "route-preview.png", type: "public.png")
                    nested.keepText("nested payload one", named: "duplicate-name.txt")
                    XCTAssertEqual(state["selectedRoute"] as? String, "Green")
                }
            }
            XCTContext.runActivity(named: "Finish journey") { activity in
                activity.keepText("nested payload two", named: "duplicate-name.txt")
                activity.keep(Data([0, 1, 2, 127, 128, 254, 255]), named: "opaque.bin", type: "public.data")
                activity.keep(Data(), named: "empty.txt", type: "public.plain-text")
            }
        }
    }

    func testSlowPassingOperation() {
        XCTContext.runActivity(named: "Wait for a deliberately slow local operation") { activity in
            Thread.sleep(forTimeInterval: 0.35)
            activity.keepText("Completed in approximately 350 ms", named: "timing.txt")
        }
    }

    func testPerformanceMeasurement() {
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        XCTContext.runActivity(named: "Measure local route serialization") { _ in
            measure(metrics: [XCTClockMetric()], options: options) {
                _ = (0..<2_000).map(String.init).joined(separator: ",")
            }
        }
    }
}
