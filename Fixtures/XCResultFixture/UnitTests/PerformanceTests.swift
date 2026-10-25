import Foundation
import os
import XCTest

// Only the Performance test plan runs these. Workloads are tiny; the shapes matter, not the numbers.
final class PerformanceTests: XCTestCase {
    private static let signposter = OSSignposter(subsystem: "dev.xctestreport.fixture.tests", category: "Performance")

    private func serializeRoutes(_ count: Int = 2_000) {
        _ = (0..<count).map(String.init).joined(separator: ",")
    }

    private func options(iterations: Int) -> XCTMeasureOptions {
        let options = XCTMeasureOptions()
        options.iterationCount = iterations
        return options
    }

    func testLegacyMeasureBlock() {
        measure { serializeRoutes() }
    }

    func testHostMetricsWithCustomIterationCount() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("perf-storage.bin")
        defer { try? FileManager.default.removeItem(at: file) }
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(), XCTMemoryMetric(), XCTStorageMetric()],
                options: options(iterations: 4)) {
            serializeRoutes()
            try? Data(repeating: 7, count: 256 * 1024).write(to: file)
        }
    }

    func testLegacyManualStartStop() {
        measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
            let input = (0..<5_000).map(String.init)
            startMeasuring()
            _ = input.joined(separator: ",")
            stopMeasuring()
        }
    }

    func testManualStartStopOptions() {
        let options = options(iterations: 3)
        options.invocationOptions = [.manuallyStart, .manuallyStop]
        measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options) {
            let input = (0..<5_000).map(String.init)
            startMeasuring()
            _ = input.joined(separator: ",")
            stopMeasuring()
        }
    }

    func testSignpostAndCustomMetrics() {
        let signpost = XCTOSSignpostMetric(subsystem: "dev.xctestreport.fixture.tests", category: "Performance",
                                           name: "Encode routes")
        measure(metrics: [signpost, RoutesPerSecondMetric()], options: options(iterations: 3)) {
            let state = Self.signposter.beginInterval("Encode routes")
            serializeRoutes(RoutesPerSecondMetric.routes)
            Self.signposter.endInterval("Encode routes", state)
        }
    }

    // Each baseline test is paired with a committed baseline in xcshareddata/xcbaselines.
    func testBaselineRegression() {
        measure(metrics: [XCTClockMetric()], options: options(iterations: 3)) {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    func testBaselineImprovement() {
        measure(metrics: [XCTClockMetric()], options: options(iterations: 3)) {
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    func testLegacyBaselineWithinTolerance() {
        measure { Thread.sleep(forTimeInterval: 0.02) }
    }

    // Xcode checks variance only against a baseline. Every value stays within 20% of the
    // average, so only the relative standard deviation (baseline max: 5%) fails.
    func testHighRelativeStandardDeviation() {
        var iteration = 0
        measure(metrics: [XCTClockMetric()], options: options(iterations: 4)) {
            iteration += 1
            Thread.sleep(forTimeInterval: iteration.isMultiple(of: 2) ? 0.030 : 0.036)
        }
    }

    // The fourth measured value is far above the average: Xcode reports that outlier instead.
    func testOutlierMeasurement() {
        var iteration = 0
        measure(metrics: [XCTClockMetric()], options: options(iterations: 4)) {
            iteration += 1
            Thread.sleep(forTimeInterval: iteration == 5 ? 0.08 : 0.02)
        }
    }

    func testAssertionFailuresInAndAfterMeasure() {
        var iteration = 0
        measure(metrics: [XCTClockMetric()], options: options(iterations: 2)) {
            iteration += 1
            serializeRoutes()
            XCTAssertLessThan(iteration, 3, "Fixture performance failure inside the final measured iteration.")
        }
        XCTFail("Fixture performance failure: the measured routes were not cached.")
    }

    func testActivityWrappedMeasureWithIterationActivities() {
        var iteration = 0
        XCTContext.runActivity(named: "Measure route encoding") { activity in
            measure(metrics: [XCTClockMetric(), XCTMemoryMetric()], options: options(iterations: 3)) {
                iteration += 1
                XCTContext.runActivity(named: "Encode iteration \(iteration)") { step in
                    serializeRoutes()
                    step.keepText("iteration \(iteration)", named: "iteration.txt")
                }
            }
            activity.keepText("\(iteration) invocations", named: "invocations.txt")
        }
    }
}

/// A custom XCTMetric: reports its own identifier, unit and a "prefers larger" polarity.
final class RoutesPerSecondMetric: NSObject, XCTMetric {
    static let routes = 20_000
    private var start = Date()
    private var end = Date()

    func copy(with zone: NSZone? = nil) -> Any { RoutesPerSecondMetric() }

    func willBeginMeasuring() { start = Date() }
    func didStopMeasuring() { end = Date() }

    func reportMeasurements(from startTime: XCTPerformanceMeasurementTimestamp,
                            to endTime: XCTPerformanceMeasurementTimestamp) throws -> [XCTPerformanceMeasurement] {
        let seconds = max(end.timeIntervalSince(start), 0.000_001)
        return [XCTPerformanceMeasurement(identifier: "dev.xctestreport.fixture.routes-per-second",
                                          displayName: "Routes Encoded",
                                          doubleValue: Double(Self.routes) / seconds,
                                          unitSymbol: "routes/s",
                                          polarity: .prefersLarger)]
    }
}
