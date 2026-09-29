import Foundation

extension XCTestReport {
    struct FailureNavigationLink: Equatable {
        let pageName: String
        let testName: String
    }

    struct FailureNavigation: Equatable {
        let previous: FailureNavigationLink?
        let next: FailureNavigationLink?
        let position: Int
        let total: Int
    }

    /// Previous/next failed test for each failed test page, in the index's default order:
    /// suites by name, tests in run order within a suite.
    static func failureNavigation(for tests: [TestNode]) -> [String: FailureNavigation] {
        let failed = tests.enumerated()
            .filter { isFailureTestResult($0.element.result) }
            .sorted { lhs, rhs in
                let lhsSuite = suiteName(for: lhs.element)
                let rhsSuite = suiteName(for: rhs.element)
                return lhsSuite == rhsSuite ? lhs.offset < rhs.offset : lhsSuite < rhsSuite
            }
            .map { FailureNavigationLink(pageName: testPageName(for: $0.element), testName: $0.element.name) }

        var navigation = [String: FailureNavigation](minimumCapacity: failed.count)
        for (index, link) in failed.enumerated() {
            navigation[link.pageName] = FailureNavigation(
                previous: index > 0 ? failed[index - 1] : nil,
                next: index + 1 < failed.count ? failed[index + 1] : nil,
                position: index + 1,
                total: failed.count)
        }
        return navigation
    }

    static func testPageName(for test: TestNode) -> String {
        "test_\(test.nodeIdentifier ?? test.name).html".replacingOccurrences(of: "/", with: "_")
    }

    private static func suiteName(for test: TestNode) -> String {
        test.nodeIdentifier?.split(separator: "/").first.map(String.init) ?? "Unknown Suite"
    }

    func renderFailureNavigation(_ navigation: FailureNavigation?) -> String {
        guard let navigation, navigation.total > 1 else { return "" }

        func link(_ target: FailureNavigationLink?, rel: String, label: String, glyph: String)
            -> String
        {
            guard let target else {
                return "<span class=\"test-failure-nav-link is-disabled\" aria-hidden=\"true\">\(glyph)</span>"
            }
            let title = htmlEscape("\(label): \(target.testName)")
            return "<a class=\"test-failure-nav-link\" rel=\"\(rel)\" "
                + "href=\"\(htmlEscape(target.pageName))\" title=\"\(title)\" "
                + "aria-label=\"\(title)\">\(glyph)</a>"
        }

        return "<nav class=\"test-failure-nav\" aria-label=\"Failed tests\">"
            + link(navigation.previous, rel: "prev", label: "Previous failure", glyph: "&lsaquo;")
            + "<span class=\"test-failure-nav-count\">Failure \(navigation.position) of \(navigation.total)</span>"
            + link(navigation.next, rel: "next", label: "Next failure", glyph: "&rsaquo;")
            + "</nav>"
    }
}
