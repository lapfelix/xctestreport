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

    struct TestNode: Decodable {
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
        let testName: String
        let testPlanConfigurations: [TestPlanConfiguration]
        let testResult: String
        let testRuns: [TestRunDetail]?
        var previousRuns: [TestRunDetail]?
    }

    struct TestRunDetail: Decodable {
        let children: [TestRunChild]?
        let duration: String
        let name: String
        let nodeIdentifier: String?
        let nodeType: String
        let result: String?
    }

    struct TestRunChild: Decodable {
        let children: [TestRunChildDetail]?
        let name: String
        let nodeType: String
        let result: String?
    }

    struct TestRunChildDetail: Decodable {
        let name: String
        let nodeType: String
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

    struct AttachmentManifestEntry: Decodable {
        let attachments: [AttachmentManifestItem]
        let testIdentifier: String
    }

    struct AttachmentManifestItem: Decodable {
        let exportedFileName: String
        let isAssociatedWithFailure: Bool?
        let suggestedHumanReadableName: String?
    }

    struct TestActivities: Decodable {
        let testIdentifier: String
        let testRuns: [TestActivityRun]
    }

    struct TestActivityRun: Decodable {
        let activities: [TestActivity]
    }

    struct TestActivity: Decodable {
        let title: String
        let startTime: Double?
        let isAssociatedWithFailure: Bool?
        let attachments: [TestActivityAttachment]?
        let childActivities: [TestActivity]?
    }

    struct TestActivityAttachment: Decodable {
        let name: String
        let timestamp: Double?
    }

    struct VideoSource {
        let label: String
        let fileName: String
        let mimeType: String
        let startTime: Double?
        let failureAssociated: Bool
    }

    struct ScreenshotSource: Codable {
        let label: String
        let src: String
        let time: Double
        let failureAssociated: Bool
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
        let timestamp: Double?
        let endTimestamp: Double?
        let failureAssociated: Bool
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

    struct TimelineEventEntry: Codable {
        let id: String
        let title: String
        let time: Double
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

}
