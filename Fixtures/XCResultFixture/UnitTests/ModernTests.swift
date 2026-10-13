import Foundation
import Testing

@Suite("Fare rules – Montréal", .serialized)
struct ModernTests {
    @Test("Prices: adult, child & reduced", arguments: ["adult", "child", "reduced"])
    func fares(category: String) {
        let fares = ["adult": 3.75, "child": 0.0, "reduced": 2.50]
        #expect(fares[category] != nil)
    }

    @Test("A modern assertion with Unicode → and <markup>")
    func modernAssertion() {
        #expect(!FixtureMode.isMixed, "Fixture modern failure: Montréal → Downtown <rail> & bus")
    }
}
