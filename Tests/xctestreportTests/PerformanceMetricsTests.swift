import Foundation
import XCTest

@testable import xctestreport

final class PerformanceMetricsTests: XCTestCase {
    typealias Report = XCTestReport

    // MARK: - Decoding

    func testDecodesXCResultToolMetricsAndDropsTestsWithoutMetrics() throws {
        let json = """
            [{"testIdentifier":"Suite/testFast()","testIdentifierURL":"test://x/Suite/testFast","testRuns":[{
              "device":{"deviceId":"A","deviceName":"iPhone 17 Pro"},
              "testPlanConfiguration":{"configurationId":"1","configurationName":"Perf"},
              "metrics":[{"baselineAverage":0,"baselineName":"","displayName":"Clock Monotonic Time",
                "identifier":"com.apple.dt.XCTMetric_Clock.time.monotonic","maxPercentRegression":10,
                "maxPercentRelativeStandardDeviation":10,"maxRegression":0,"maxStandardDeviation":10,
                "measurements":[1.0,1.1,0.9],"polarity":"prefers smaller","unitOfMeasurement":"s"}]}]},
             {"testIdentifier":"Suite/testEmpty()","testRuns":[{"metrics":[]}]}]
            """
        let metrics = try Report.decodePerformanceMetrics(Data(json.utf8))
        XCTAssertEqual(Array(metrics.keys), ["Suite/testFast()"])
        let run = try XCTUnwrap(metrics["Suite/testFast()"]?.testRuns.first)
        XCTAssertEqual(run.label, "iPhone 17 Pro · Perf")
        let metric = try XCTUnwrap(run.metrics.first)
        XCTAssertEqual(metric.measurements, [1.0, 1.1, 0.9])
        XCTAssertEqual(metric.prefersSmaller, true)
        XCTAssertNil(metric.baseline, "A zero average with no name means no baseline")
    }

    // MARK: - Statistics

    func testStatisticsUseSampleStandardDeviation() throws {
        let statistics = try XCTUnwrap(Report.PerformanceStatistics([2, 4, 4, 4, 5, 5, 7, 9]))
        XCTAssertEqual(statistics.mean, 5)
        XCTAssertEqual(statistics.median, 4.5)
        XCTAssertEqual(statistics.min, 2)
        XCTAssertEqual(statistics.max, 9)
        XCTAssertEqual(statistics.standardDeviation, (32.0 / 7).squareRoot(), accuracy: 1e-9)
        XCTAssertEqual(statistics.relativeStandardDeviation!, (32.0 / 7).squareRoot() / 5 * 100, accuracy: 1e-9)
    }

    func testRelativeDeviationIsUndefinedForValuesAroundZero() throws {
        let statistics = try XCTUnwrap(Report.PerformanceStatistics([16.4, -131, -163, 0, -180]))
        XCTAssertNil(statistics.relativeStandardDeviation)
    }

    func testFlagsALoneDivergentIterationButNotSteadyValues() throws {
        let divergent = try XCTUnwrap(Report.PerformanceStatistics([2.98, 3.01, 2.98, 2.93, 1.87]))
        XCTAssertEqual(divergent.outlierIndices, [4])
        let steady = try XCTUnwrap(Report.PerformanceStatistics([14.769, 14.768, 14.770, 14.770, 14.766]))
        XCTAssertEqual(steady.outlierIndices, [])
        let flat = try XCTUnwrap(Report.PerformanceStatistics([1.22, 1.22, 1.22]))
        XCTAssertEqual(flat.outlierIndices, [])
    }

    // MARK: - Formatting

    func testFormatsXCTestUnitsAtOneSharedScale() {
        let seconds = Report.PerformanceValueFormatter(unit: "s", values: [0.0042, 0.0051])
        XCTAssertEqual(seconds.format(0.0042), "4.20 ms")
        let memory = Report.PerformanceValueFormatter(unit: "kB", values: [345214.24, 248548.64])
        XCTAssertEqual(memory.format(345214.24), "345 MB")
        XCTAssertEqual(memory.format(248548.64), "249 MB")
        let instructions = Report.PerformanceValueFormatter(unit: "kI", values: [17285956.047])
        XCTAssertEqual(instructions.format(17285956.047), "17.3 G instr")
        let cycles = Report.PerformanceValueFormatter(unit: "kC", values: [7798284.79])
        XCTAssertEqual(cycles.format(7798284.79), "7.80 G cycles")
        let custom = Report.PerformanceValueFormatter(unit: "fps", values: [59.9])
        XCTAssertEqual(custom.format(59.94), "59.9 fps")
        XCTAssertEqual(memory.raw(345214.24), "345214 kB")
        let rate = Report.PerformanceValueFormatter(unit: "routes/s", values: [9133456])
        XCTAssertEqual(rate.format(9133456), "9.13 M routes/s")
        let legacy = Report.PerformanceValueFormatter(unit: "seconds", values: [0.0002])
        XCTAssertEqual(legacy.format(0.000197), "197 µs")
        XCTAssertEqual(Report.formatPercentChange(913_345_548), "×9.13M")
        XCTAssertEqual(Report.formatPercentChange(12.34), "+12%")
        XCTAssertEqual(Report.formatPercentChange(-4.21), "−4.2%")
        XCTAssertEqual(Report.formatPercentChange(0.01), "±0%")
        XCTAssertEqual(Report.formatPercent(0.01), "<0.1%")
    }

    // MARK: - Baselines and history

    func testFlagsRegressionsAgainstTheBaselineByPolarity() {
        let slower = analysis(metric(values: [1.2, 1.2, 1.2], baseline: 1.0))
        XCTAssertEqual(slower.baselineChange!, 20, accuracy: 1e-9)
        XCTAssertEqual(slower.baselineDirection, .worse)
        XCTAssertTrue(slower.exceedsRegressionLimit)

        let withinLimit = analysis(metric(values: [1.05, 1.05, 1.05], baseline: 1.0))
        XCTAssertEqual(withinLimit.baselineDirection, .worse)
        XCTAssertFalse(withinLimit.exceedsRegressionLimit)

        let faster = analysis(metric(values: [0.5, 0.5, 0.5], baseline: 1.0))
        XCTAssertEqual(faster.baselineDirection, .better)
        XCTAssertFalse(faster.exceedsRegressionLimit)

        let fewerFrames = analysis(metric(values: [40, 40, 40], baseline: 60, polarity: "prefers larger"))
        XCTAssertEqual(fewerFrames.baselineDirection, .worse)
        XCTAssertTrue(fewerFrames.exceedsRegressionLimit)

        // XCTest: "measurement #4 is 125% worse than average (max allowed: 40%)".
        let spike = analysis(metric(values: [0.0207, 0.0203, 0.0207, 0.0797], baseline: 0.035))
        XCTAssertEqual(spike.iterationsOverLimit, [3])
        XCTAssertFalse(spike.exceedsRegressionLimit)
        XCTAssertEqual(analysis(metric(values: [0.0207, 0.0203, 0.0207, 0.0797])).iterationsOverLimit, [],
                       "XCTest checks iterations only against a baseline")

        let absoluteLimit = analysis(metric(values: [1.2, 1.2, 1.2], baseline: 1.0, maxRegression: 0.5))
        XCTAssertFalse(absoluteLimit.exceedsRegressionLimit, "Both XCTest limits must be exceeded")
    }

    func testComparesWithTheMatchingRunOfEarlierReports() {
        let current = test(runs: [run(device: "iPhone", metrics: [metric(values: [1.3, 1.3, 1.3])])])
        let older = Report.PerformanceHistoryEntry(date: nil, tests: [
            "Suite/test()": test(runs: [run(device: "iPhone", metrics: [metric(values: [1.0, 1.0, 1.0])])]),
        ])
        let newer = Report.PerformanceHistoryEntry(date: Date(timeIntervalSince1970: 10), tests: [
            "Suite/test()": test(runs: [
                run(device: "iPad", metrics: [metric(values: [9, 9, 9])]),
                run(device: "iPhone", metrics: [metric(values: [1.2, 1.2, 1.2])]),
            ]),
        ])
        let result = Report.analyzePerformance(current, history: [newer, older])
        let item = result.runs[0].metrics[0]
        XCTAssertEqual(item.history, [1.0, 1.2], "Oldest first, from the run on the same device")
        XCTAssertEqual(item.previousChange!, 1.3 / 1.2 * 100 - 100, accuracy: 1e-9)
        XCTAssertEqual(item.previousDirection, .worse)
        XCTAssertEqual(result.previousRunDate, Date(timeIntervalSince1970: 10))
    }

    // MARK: - Findings and rendering

    func testGroupsOutliersByIterationAndLeadsWithRegressions() {
        let result = Report.analyzePerformance(test(runs: [run(device: "iPhone", metrics: [
            metric(name: "CPU Time", values: [3.0, 3.01, 2.98, 2.99, 1.9]),
            metric(name: "CPU Cycles", values: [7.8, 7.85, 7.78, 7.75, 3.6]),
            metric(name: "Clock", values: [1.5, 1.5, 1.5, 1.5, 1.5], baseline: 1.0),
        ])]), history: [])
        let findings = Report.performanceFindings(for: result)
        XCTAssertEqual(findings.first?.severity, .regression)
        XCTAssertTrue(findings[0].text.contains("Clock regressed from baseline"), findings[0].text)
        let outliers = findings.filter { $0.severity == .outlier }
        XCTAssertEqual(outliers.count, 1)
        XCTAssertTrue(outliers[0].text.hasPrefix("Iteration 5 stands out in 2 metrics"), outliers[0].text)
    }

    func testRendersSectionOverviewAndMarkdown() {
        let report = makeTestReport()
        let result = Report.analyzePerformance(test(runs: [run(device: "iPhone", metrics: [
            metric(name: "Clock <Monotonic>", values: [1.2, 1.2, 1.2], baseline: 1.0),
            metric(name: "Memory", values: [100, 101, 160], unit: "kB"),
        ])]), history: [])

        let html = report.renderPerformanceSection(result)
        XCTAssertTrue(html.contains("id=\"performance\""))
        XCTAssertTrue(html.contains("Clock &lt;Monotonic&gt;"), "Metric names are escaped")
        XCTAssertTrue(html.contains("perf-row-regressed"))
        XCTAssertTrue(html.contains("<th scope=\"col\">Baseline</th>"))
        XCTAssertFalse(html.contains("Previous runs"), "No history, no column")
        XCTAssertTrue(html.contains("class=\"perf-outlier\""))
        XCTAssertEqual(html.components(separatedBy: "<circle").count - 1, 6)

        let node = Report.TestNode(
            name: "test()", nodeType: "Test Case", nodeIdentifier: "Suite/test()", result: "Passed",
            duration: nil, details: nil, children: nil, startTime: nil)
        let overview = report.renderPerformanceOverview([
            .init(test: node, pagePath: "tests/page.html", analysis: result)
        ])
        XCTAssertTrue(overview.contains("href=\"tests/page.html#performance\""))
        XCTAssertTrue(overview.contains("1 regressed"))
        XCTAssertTrue(overview.contains("<th scope=\"col\">Memory</th>"))

        let markdown = report.renderPerformanceMarkdown(result).joined(separator: "\n")
        XCTAssertTrue(markdown.contains("## Performance"))
        XCTAssertTrue(markdown.contains("**Regression:**"))
        XCTAssertTrue(markdown.contains("| Clock <Monotonic> (lower is better) | 1.20 s |"), markdown)
        XCTAssertTrue(markdown.contains("**160 kB**"), "Outlier iterations are bold")
    }

    func testHTMLOnlyRegenerationReadsTheCachedMetrics() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("perf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let cached = [test(runs: [run(device: "iPhone", metrics: [metric(values: [1, 2, 3])])])]
        try JSONEncoder().encode(cached).write(to: root.appendingPathComponent(Report.performanceMetricsFileName))

        var report = makeTestReport()
        report.xcresultPath = root.appendingPathComponent("missing.xcresult").path
        report.outputDir = root.path
        report.htmlOnly = true
        let metrics = try report.loadPerformanceMetrics()
        XCTAssertEqual(metrics["Suite/test()"]?.testRuns.first?.metrics.first?.measurements, [1, 2, 3])
    }

    // MARK: - Helpers

    private func metric(
        name: String = "Clock Monotonic Time", values: [Double], baseline: Double = 0, unit: String = "s",
        polarity: String = "prefers smaller", maxRegression: Double = 0
    ) -> Report.PerformanceMetric {
        Report.PerformanceMetric(
            displayName: name, identifier: "metric.\(name)", unitOfMeasurement: unit, polarity: polarity,
            measurements: values, baselineName: baseline == 0 ? "" : "Local Baseline", baselineAverage: baseline,
            maxPercentRegression: 10, maxPercentRelativeStandardDeviation: 10, maxRegression: maxRegression,
            maxStandardDeviation: 10)
    }

    private func run(device: String, metrics: [Report.PerformanceMetric]) -> Report.PerformanceRun {
        Report.PerformanceRun(
            device: .init(deviceId: device, deviceName: device),
            testPlanConfiguration: .init(configurationId: "1", configurationName: "Perf"), metrics: metrics)
    }

    private func test(runs: [Report.PerformanceRun]) -> Report.PerformanceTestMetrics {
        Report.PerformanceTestMetrics(testIdentifier: "Suite/test()", testIdentifierURL: nil, testRuns: runs)
    }

    private func analysis(_ metric: Report.PerformanceMetric) -> Report.PerformanceMetricAnalysis {
        Report.analyzePerformance(test(runs: [run(device: "iPhone", metrics: [metric])]), history: [])
            .runs[0].metrics[0]
    }
}
