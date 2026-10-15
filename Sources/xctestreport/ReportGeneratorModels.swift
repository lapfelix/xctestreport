import Dispatch
import Foundation

extension XCTestReport {
    // MARK: - Structures
    struct Summary: Decodable {
        let title: String
        let startTime: Double
        let finishTime: Double
        let environmentDescription: String
        let topInsights: [InsightSummary]
        let result: String
        let totalTestCount: Int
        let passedTests: Int
        let failedTests: Int
        let skippedTests: Int
        let expectedFailures: Int
        let statistics: [Statistic]
        let devicesAndConfigurations: [DeviceAndConfigurationSummary]
        let testFailures: [TestFailure]
    }

    struct InsightSummary: Decodable {
        let impact: String
        let category: String
        let text: String
    }

    struct Statistic: Decodable {
        let title: String
        let subtitle: String
    }

    struct DeviceAndConfigurationSummary: Decodable {
        let device: Device
        let testPlanConfiguration: Configuration
        let passedTests: Int
        let failedTests: Int
        let skippedTests: Int
        let expectedFailures: Int
    }

    struct Device: Decodable {
        let deviceId: String?
        let deviceName: String
        let architecture: String
        let modelName: String
        let platform: String?
        let osVersion: String
        let osBuildNumber: String?
    }

    struct Configuration: Decodable {
        let configurationId: String
        let configurationName: String
    }

    struct TestFailure: Decodable {
        let testName: String
        let targetName: String
        let failureText: String
        let testIdentifier: Int
    }

    struct FullTestResults: Decodable {
        let devices: [Device]
        let testNodes: [TestNode]
        let testPlanConfigurations: [TestPlanConfiguration]
    }

    struct TestNode: Codable {
        let name: String
        let nodeType: String
        let nodeIdentifier: String?
        let result: String?
        let duration: String?
        let details: String?
        let children: [TestNode]?
        let startTime: Double?
    }

    struct TestPlanConfiguration: Decodable {
        let configurationId: String
        let configurationName: String
    }

    struct TestDetails: Decodable {
        let devices: [Device]
        let duration: String
        let hasMediaAttachments: Bool
        let hasPerformanceMetrics: Bool
        let startTime: Double?
        let testDescription: String
        let testIdentifier: String
        let testIdentifierURL: String?
        let testName: String
        let testPlanConfigurations: [TestPlanConfiguration]
        let testResult: String
        let testRuns: [TestRunDetail]?
        var previousRuns: [TestRunDetail]?

        private enum CodingKeys: String, CodingKey {
            case devices, duration, hasMediaAttachments, hasPerformanceMetrics, startTime
            case testDescription, testIdentifier, testIdentifierURL, testName
            case testPlanConfigurations, testResult, testRuns
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            devices = try container.decode([Device].self, forKey: .devices)
            duration = try container.decode(String.self, forKey: .duration)
            hasMediaAttachments = try container.decode(Bool.self, forKey: .hasMediaAttachments)
            hasPerformanceMetrics = try container.decode(Bool.self, forKey: .hasPerformanceMetrics)
            startTime = try container.decodeIfPresent(Double.self, forKey: .startTime)
            testDescription = try container.decode(String.self, forKey: .testDescription)
            testIdentifier = try container.decode(String.self, forKey: .testIdentifier)
            testIdentifierURL = try container.decodeIfPresent(String.self, forKey: .testIdentifierURL)
            testName = try container.decode(String.self, forKey: .testName)
            testPlanConfigurations = try container.decode(
                [TestPlanConfiguration].self, forKey: .testPlanConfigurations)
            testResult = try container.decode(String.self, forKey: .testResult)
            testRuns = try container.decodeIfPresent([TestRunNode].self, forKey: .testRuns)
                .map(TestRunDetail.flatten)
            previousRuns = nil
        }
    }

    struct TestRunDetail: Decodable {
        let children: [TestRunChild]?
        let duration: String
        let name: String
        let nodeIdentifier: String?
        let nodeType: String
        let result: String?
        /// Device and configuration the run belongs to, when the result nests runs under them.
        var destination: String? = nil

        private static let destinationNodeTypes: Set<String> = ["Device", "Test Plan Configuration"]

        /// Bundles with several destinations nest runs as Device > Test Plan Configuration >
        /// [Repetition], without a duration on the device; single-destination bundles list
        /// repetitions directly. Either way, each leaf is one attempt.
        static func flatten(_ nodes: [TestRunNode]) -> [TestRunDetail] {
            var runs = [TestRunDetail]()
            func visit(_ node: TestRunNode, path: [String]) {
                let children = node.children ?? []
                let nestsRuns =
                    destinationNodeTypes.contains(node.nodeType)
                    && children.contains {
                        destinationNodeTypes.contains($0.nodeType) || $0.nodeType == "Repetition"
                    }
                if nestsRuns {
                    for child in children {
                        visit(child, path: path + [node.name])
                    }
                    return
                }
                var run = TestRunDetail(node: node)
                if !path.isEmpty {
                    let destination = path.joined(separator: " · ")
                    run = TestRunDetail(
                        children: run.children, duration: run.duration,
                        name: "\(destination) · \(run.name)", nodeIdentifier: run.nodeIdentifier,
                        nodeType: run.nodeType, result: run.result, destination: destination)
                }
                runs.append(run)
            }
            for node in nodes {
                visit(node, path: [])
            }
            return runs
        }
    }

    /// Raw `testRuns` node from `xcresulttool get test-results test-details`.
    struct TestRunNode: Decodable {
        let children: [TestRunNode]?
        let duration: String?
        let durationInSeconds: Double?
        let name: String
        let nodeIdentifier: String?
        let nodeType: String
        let result: String?
        let url: String?
        let sourceLocation: TestRunSourceLocation?
    }

    struct TestRunChild {
        let children: [TestRunChildDetail]?
        let name: String
        let nodeType: String
        let result: String?
        let sourceLocation: TestRunSourceLocation?
        var durationInSeconds: Double? = nil

        init(_ node: TestRunNode) {
            children = node.children?.map(TestRunChildDetail.init)
            name = node.name
            nodeType = node.nodeType
            result = node.result
            sourceLocation = node.sourceLocation
            durationInSeconds = node.durationInSeconds
        }
    }

    struct TestRunSourceLocation: Decodable {
        let filePath: String
        let lineNumber: Int
    }

    struct TestRunChildDetail {
        let children: [TestRunChildDetail]?
        let name: String
        let nodeType: String
        let result: String?
        let url: String?
        let sourceLocation: TestRunSourceLocation?

        init(_ node: TestRunNode) {
            children = node.children?.map(TestRunChildDetail.init)
            name = node.name
            nodeType = node.nodeType
            result = node.result
            url = node.url
            sourceLocation = node.sourceLocation
        }
    }

    struct TestHistory {
        let date: Date
        let results: [String: TestResult]  // nodeIdentifier -> result
    }

    struct TestResult {
        let name: String
        let status: String
        let duration: String?
    }

    struct BuildResults: Decodable {
        let startTime: Double
        let endTime: Double
        let errorCount: Int
        let warningCount: Int

        var buildTime: Double {
            return endTime - startTime
        }
    }

    struct TestExportItem: Codable {
        let name: String
        let result: String
        let duration: String?
        let nodeIdentifier: String?
        let details: String?
    }

    struct SuiteExportItem: Codable {
        let name: String
        let totalTests: Int
        let passedTests: Int
        let failedTests: Int
        let skippedTests: Int
        let duration: TimeInterval
        let tests: [TestExportItem]
    }

    struct GroupedTestsExport: Codable {
        let summary: ExportSummary
        let suites: [SuiteExportItem]
    }

    struct ExportSummary: Codable {
        let title: String
        let totalTestCount: Int
        let passedTests: Int
        let failedTests: Int
        let skippedTests: Int
        let timestamp: Date
    }

    struct TestCounts: Equatable {
        let passedTests: Int
        let failedTests: Int
        let skippedTests: Int

        var totalTests: Int {
            return passedTests + failedTests
        }

        var rawTotalTests: Int {
            return totalTests + skippedTests
        }

        var percentagePassed: Double {
            return totalTests > 0 ? Double(passedTests) / Double(totalTests) * 100.0 : 100.0
        }
    }

    struct AttachmentManifestEntry: Codable {
        var attachments: [AttachmentManifestItem]
        let testIdentifier: String
    }

    struct AttachmentManifestItem: Codable {
        var exportedFileName: String
        let isAssociatedWithFailure: Bool?
        var suggestedHumanReadableName: String?
        let timestamp: Double?
        let payloadRefId: String?
    }

    struct TestActivities: Codable {
        let testIdentifier: String
        let testRuns: [TestActivityRun]
    }

    struct TestActivityRun: Codable {
        let activities: [TestActivity]
    }

    struct TestActivity: Codable {
        let title: String
        let startTime: Double?
        let isAssociatedWithFailure: Bool?
        let attachments: [TestActivityAttachment]?
        let childActivities: [TestActivity]?
        let failureBranchStyle: Bool?
    }

    struct TestActivityAttachment: Codable {
        let name: String
        let timestamp: Double?
        let payloadId: String?
    }

    struct VideoSource {
        let label: String
        let fileName: String
        let mimeType: String
        let startTime: Double?
        let failureAssociated: Bool
        let runIndex: Int?
    }

    struct ScreenshotSource: Codable {
        let label: String
        let src: String
        let time: Double
        let failureAssociated: Bool
        var runIndex: Int? = nil
    }

    struct TimelineAttachment {
        let name: String
        let timestamp: Double?
        let relativePath: String?
        let failureAssociated: Bool
    }

    struct TimelineNode {
        let id: String
        let title: String
        let sourceLocationLabel: String?
        let timestamp: Double?
        let endTimestamp: Double?
        let failureAssociated: Bool
        let failureBranchStyle: Bool
        let attachments: [TimelineAttachment]
        let children: [TimelineNode]
        let repeatCount: Int
    }

    struct SourceLocation {
        let filePath: String
        let line: Int
        let column: Int?
    }

    struct StackTracePreview {
        let attachmentName: String
        let relativePath: String
        let preview: String
        let frameCount: Int
    }

    struct TouchGesturePoint: Codable {
        let time: Double
        let x: Double
        let y: Double
    }

    struct TouchGestureOverlay: Codable {
        let startTime: Double
        let endTime: Double
        let width: Double
        let height: Double
        let points: [TouchGesturePoint]
    }

    struct UIHierarchyElement: Codable {
        let id: String
        let depth: Int
        let role: String
        let name: String?
        let label: String?
        let identifier: String?
        let value: String?
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let properties: [String: String]
    }

    struct UIHierarchySnapshot: Codable {
        let id: String
        let label: String
        let time: Double
        let width: Double
        let height: Double
        let failureAssociated: Bool
        let elements: [UIHierarchyElement]
    }

    enum TimelineEventKind: String, Codable {
        case event
        case tap
        case hierarchy
        case error
    }

    struct TimelineEventEntry: Codable {
        let id: String
        let title: String
        let time: Double
        let endTime: Double
        let kind: TimelineEventKind
    }

    struct TimelineRunState: Codable {
        let index: Int
        let label: String
        let timelineBase: Double
        let firstEventLabel: String
        let initialFailureEventIndex: Int
        let events: [TimelineEventEntry]
        let touchGestures: [TouchGestureOverlay]
        let hierarchySnapshots: [UIHierarchySnapshot]
    }

    static func isPassedTestResult(_ result: String?) -> Bool {
        // XCTest's known issues are accepted outcomes, not unexpected failures.
        return result == "Passed" || result == "Expected Failure"
    }

    static func isSkippedTestResult(_ result: String?) -> Bool {
        return result == "Skipped"
    }

    static func isFailureTestResult(_ result: String?) -> Bool {
        return !isPassedTestResult(result) && !isSkippedTestResult(result)
    }

    static func testCounts(for tests: [TestNode]) -> TestCounts {
        var passedTests = 0
        var failedTests = 0
        var skippedTests = 0

        for test in tests {
            if isPassedTestResult(test.result) {
                passedTests += 1
            } else if isSkippedTestResult(test.result) {
                skippedTests += 1
            } else {
                failedTests += 1
            }
        }

        return TestCounts(
            passedTests: passedTests,
            failedTests: failedTests,
            skippedTests: skippedTests
        )
    }

}

extension XCTestReport.TestRunDetail {
    init(from decoder: Decoder) throws {
        self.init(node: try XCTestReport.TestRunNode(from: decoder))
    }

    init(node: XCTestReport.TestRunNode) {
        let children = node.children?.map(XCTestReport.TestRunChild.init)
        let duration: String
        if let supplied = node.duration {
            duration = supplied
        } else if let seconds = node.durationInSeconds {
            duration = formatCompactDuration(seconds)
        } else {
            // Swift Testing groups repetitions under their argument and omits the group's
            // duration. Preserve the group and its children, deriving timing from repetitions.
            let repetitions = (children ?? []).filter { $0.nodeType == "Repetition" }
                .compactMap { $0.durationInSeconds }
            duration = repetitions.isEmpty ? "--" : formatCompactDuration(repetitions.reduce(0, +))
        }
        self.init(
            children: children, duration: duration, name: node.name,
            nodeIdentifier: node.nodeIdentifier, nodeType: node.nodeType, result: node.result)
    }
}
