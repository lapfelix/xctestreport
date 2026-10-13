import Foundation
import UIKit
import XCTest

enum FixtureMode {
    static var isMixed: Bool { ProcessInfo.processInfo.environment["FIXTURE_SCENARIO"] == "mixed" }
}

extension XCTActivity {
    func keep(_ data: Data, named name: String, type: String) {
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: type)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func keepText(_ text: String, named name: String) {
        keep(Data(text.utf8), named: name, type: "public.plain-text")
    }
}

enum FixtureImages {
    // Pixel-only drawing avoids OS font/rendering changes in snapshot comparisons.
    static func card(changed: Bool = false, size: CGSize = CGSize(width: 160, height: 96)) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            cg.fill(CGRect(origin: .zero, size: size))
            cg.setFillColor(UIColor(red: 0.08, green: 0.58, blue: 0.25, alpha: 1).cgColor)
            cg.fill(CGRect(x: 8, y: 8, width: 144, height: 24))
            cg.setFillColor(UIColor.darkGray.cgColor)
            cg.fill(CGRect(x: 8, y: 44, width: 96, height: 8))
            cg.fill(CGRect(x: 8, y: 60, width: 64, height: 8))
            cg.setFillColor((changed ? UIColor.systemPink : UIColor.lightGray).cgColor)
            cg.fill(CGRect(x: changed ? 112 : 120, y: 44, width: 24, height: 24))
        }
        return image.pngData()!
    }

    static func difference() -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 160, height: 96), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 160, height: 96))
            UIColor.magenta.setFill()
            context.fill(CGRect(x: 112, y: 44, width: 32, height: 24))
        }
        return image.pngData()!
    }
}

enum FixtureFailure: Error, CustomStringConvertible {
    case offline

    var description: String {
        "Fixture service unavailable\nGET /routes?city=Montréal&mode=<rail>\nExpected status 200, received 503."
    }
}

// A separate source file gives failure/source navigation more than one location to exercise.
func recordFixtureFailure(file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertEqual(503, 200, "Fixture response has an unexpected status <503> & no body.", file: file, line: line)
}
