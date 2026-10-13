import Foundation
import XCTest

@testable import xctestreport

final class ArtifactIdentityTests: XCTestCase {
    func testDistinctIdentifiersHaveDistinctBoundedURLSafePages() {
        let identifiers = ["Suite_A/test()", "Suite/A_test()", "Suite/testCafé()", "Suite/testCafè()",
                           "Suite/test #?%()", String(repeating: "Long", count: 200)]
        let names = identifiers.map { identifier in
            XCTestReport.testPageName(for: XCTestReport.TestNode(
                name: identifier, nodeType: "Test Case", nodeIdentifier: identifier,
                result: "Passed", duration: nil, details: nil, children: nil, startTime: nil))
        }
        XCTAssertEqual(Set(names).count, identifiers.count)
        for name in names {
            XCTAssertLessThan(name.utf8.count, 128)
            XCTAssertTrue(name.hasSuffix(".html"))
            XCTAssertTrue(name.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-").contains($0)
            })
        }
    }

    func testGalleryAnchorsDistinguishPunctuationAndFullTestIdentity() {
        let report = XCTestReport()
        let first = report.snapshotGalleryComparisonElementID(
            suite: "Suite", testName: "test()", comparisonName: "Card_light", identifier: "A/Suite/test()")
        let second = report.snapshotGalleryComparisonElementID(
            suite: "Suite", testName: "test()", comparisonName: "Card-light", identifier: "A/Suite/test()")
        let third = report.snapshotGalleryComparisonElementID(
            suite: "Suite", testName: "test()", comparisonName: "Card_light", identifier: "B/Suite/test()")
        XCTAssertEqual(Set([first, second, third]).count, 3)
        XCTAssertEqual(first, report.snapshotGalleryComparisonElementID(
            suite: "Suite", testName: "test()", comparisonName: "Card_light", identifier: "A/Suite/test()"))
    }

    func testAttachmentURLsEncodeReservedCharactersWithoutLosingUnicode() {
        let report = XCTestReport()
        let path = report.attachmentRelativePathForTestPage(fileName: "café #?%[].png")
        let url = URL(string: path, relativeTo: URL(string: "https://example.test/tests/detail.html")!)!
        XCTAssertEqual(url.path.removingPercentEncoding ?? url.path, "/attachments/café #?%[].png")
        XCTAssertNil(url.query)
        XCTAssertNil(url.fragment)
    }
}
