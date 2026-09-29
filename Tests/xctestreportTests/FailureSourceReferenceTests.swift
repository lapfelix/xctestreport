import Foundation
import XCTest

@testable import xctestreport

final class FailureSourceReferenceTests: XCTestCase {

    func testSourceLocationOnlyReferenceRendersFileAndLine() throws {
        let runs = try decodeRuns(
            """
            [{"duration":"1s","name":"Run","nodeType":"Device","result":"Failed","children":[
              {"name":"testA()","nodeType":"Test Case","result":"Failed","children":[
                {"name":"failed - <mismatch>","nodeType":"Failure Message","children":[
                  {"name":"","nodeType":"Source Code Reference",
                   "sourceLocation":{"filePath":"/src/A&B Tests.swift","lineNumber":114}},
                  {"name":"","nodeType":"Source Code Reference"}
                ]}
              ]}
            ]}]
            """)
        XCTAssertEqual(runs.first?.children?.first?.children?.first?.children?.first?
            .sourceLocation?.lineNumber, 114)

        let html = XCTestReport().renderSourceReferenceSection(
            from: runs, testIdentifierURL: nil)
        XCTAssertTrue(html.contains("<li><code>/src/A&amp;B Tests.swift:114</code></li>"), html)
        XCTAssertFalse(html.contains("<li><code></code></li>"), html)
        XCTAssertEqual(html.components(separatedBy: "<li>").count - 1, 1)
    }

    func testReferencesWithNeitherNameNorLocationRenderNothing() throws {
        let runs = try decodeRuns(
            """
            [{"duration":"1s","name":"Run","nodeType":"Device","result":"Failed","children":[
              {"name":"testA()","nodeType":"Test Case","result":"Failed","children":[
                {"name":"","nodeType":"Source Code Reference"}
              ]}
            ]}]
            """)
        XCTAssertEqual(
            XCTestReport().renderSourceReferenceSection(from: runs, testIdentifierURL: nil), "")
    }

    func testNamedReferenceKeepsNameAndShowsExplicitLocation() throws {
        let runs = try decodeRuns(
            """
            [{"duration":"1s","name":"Run","nodeType":"Device","result":"Failed","children":[
              {"name":"testA()","nodeType":"Test Case","result":"Failed","children":[
                {"name":"MyTests.testA()","nodeType":"Source Code Reference",
                 "sourceLocation":{"filePath":"/src/MyTests.swift","lineNumber":7}}
              ]}
            ]}]
            """)
        let html = XCTestReport().renderSourceReferenceSection(from: runs, testIdentifierURL: nil)
        XCTAssertTrue(
            html.contains("<li><code>MyTests.testA()</code><br><code>/src/MyTests.swift:7</code></li>"),
            html)
    }

    private func decodeRuns(_ json: String) throws -> [XCTestReport.TestRunDetail] {
        try JSONDecoder().decode([XCTestReport.TestRunDetail].self, from: Data(json.utf8))
    }
}
