import Foundation
import XCTest

final class TimelineControlsStyleTests: XCTestCase {
    func testTimelineControlButtonsShareSingleHeightDefinition() throws {
        let css = try loadProjectFile("Sources/xctestreport/Resources/Web/report.css")
        let timelineTemplate = try loadProjectFile("Sources/xctestreport/Resources/Web/templates/timeline-section.html")

        // Ensure every control participates in the shared `.timeline-button` sizing contract.
        XCTAssertTrue(
            timelineTemplate.contains("class=\"timeline-button\" data-nav=\"prev\""),
            "Prev button should use the shared timeline button class."
        )
        XCTAssertTrue(
            timelineTemplate.contains("class=\"timeline-button timeline-button-play\""),
            "Play button should use the shared timeline button class."
        )
        XCTAssertTrue(
            timelineTemplate.contains("class=\"timeline-button\" data-nav=\"next\""),
            "Next button should use the shared timeline button class."
        )
        XCTAssertTrue(
            timelineTemplate.contains("class=\"timeline-button timeline-button-download\""),
            "Download control should use the shared timeline button class."
        )

        let baseButtonRules = ruleBodies(for: ".timeline-button", in: css)
        XCTAssertTrue(
            baseButtonRules.contains(where: { $0.contains("height: 30px;") }),
            "Base timeline button rule should define a shared height."
        )

        let mobileButtonRules = ruleBodies(for: ".test-detail-page .timeline-button", in: css)
        XCTAssertTrue(
            mobileButtonRules.contains(where: { $0.contains("height: 34px;") }),
            "Mobile timeline button rule should define a shared height override."
        )

        let heightPropertyPattern = #"(?m)\bheight\s*:"# 
        for body in ruleBodies(for: ".timeline-button-play", in: css) {
            XCTAssertFalse(
                body.range(of: heightPropertyPattern, options: .regularExpression) != nil,
                "Play-specific rule must not override height."
            )
        }
        for body in ruleBodies(for: ".timeline-button-download", in: css) {
            XCTAssertFalse(
                body.range(of: heightPropertyPattern, options: .regularExpression) != nil,
                "Download-specific rule must not override height."
            )
        }
    }

    private func loadProjectFile(_ relativePath: String) throws -> String {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let projectRoot = testFileURL
            .deletingLastPathComponent()  // xctestreportTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // project root
        let fileURL = projectRoot.appendingPathComponent(relativePath)
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    private func ruleBodies(for selector: String, in css: String) -> [String] {
        let escapedSelector = NSRegularExpression.escapedPattern(for: selector)
        let pattern = "(?s)" + escapedSelector + "\\s*\\{(.*?)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(location: 0, length: css.utf16.count)
        let nsCSS = css as NSString
        return regex.matches(in: css, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return nsCSS.substring(with: match.range(at: 1))
        }
    }
}
