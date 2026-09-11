import CoreGraphics
import Dispatch
import Foundation
import ImageIO

private let snapshotAttachmentNameRegex = try! NSRegularExpression(
    pattern: #"^(.+)\.(expected|actual|diff|reference|failure|difference)\.png$"#,
    options: [.caseInsensitive]
)

// Synthesized diff file names are derived from the (unique) expected attachment file name, but two
// tests can still reference the same attachment, so serialize the writes.
private let snapshotDiffWriteQueue = DispatchQueue(label: "snapshotDiffWrite")

private let snapshotMaxBoundingBoxes = 50
private let snapshotMaxComponentsToMerge = 2000
private let snapshotBoundingBoxMergeGap = 4
private let snapshotMaxPixels = 80_000_000

extension XCTestReport {

    // MARK: - Model

    enum SnapshotRole: String {
        case expected
        case actual
        case diff
    }

    /// `src` is relative to a test page (`tests/*.html`); `rootSrc` is relative to the report root.
    struct SnapshotImageRef: Codable {
        let src: String
        let rootSrc: String
        let width: Int
        let height: Int
    }

    struct SnapshotDeviceInfo: Encodable {
        /// The hardware model ("Apple Watch Series 11"). `deviceName` is the simulator instance,
        /// which on a watchOS run names the paired host iPhone instead.
        let name: String?
        let deviceName: String?
        let osVersion: String?
        let osBuildNumber: String?
        let platform: String?
        let identifier: String?

        enum CodingKeys: String, CodingKey {
            case name, deviceName, osVersion, osBuildNumber, platform, identifier
        }

        // Explicit nulls: consumers should see the object shape even when nothing resolved.
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(deviceName, forKey: .deviceName)
            try container.encode(osVersion, forKey: .osVersion)
            try container.encode(osBuildNumber, forKey: .osBuildNumber)
            try container.encode(platform, forKey: .platform)
            try container.encode(identifier, forKey: .identifier)
        }

        var displayLabel: String? {
            var parts = [String]()
            if let name { parts.append(name) }
            var runtime = [platform, osVersion].compactMap { $0 }.joined(separator: " ")
            if let osBuildNumber {
                runtime += runtime.isEmpty ? "(\(osBuildNumber))" : " (\(osBuildNumber))"
            }
            if !runtime.isEmpty { parts.append(runtime) }
            return parts.isEmpty ? nil : parts.joined(separator: " - ")
        }
    }

    struct SnapshotBoundingBox: Codable, Equatable {
        let x: Int
        let y: Int
        let w: Int
        let h: Int

        var area: Int { w * h }
    }

    struct SnapshotComparison: Codable {
        let name: String
        let expected: SnapshotImageRef
        let actual: SnapshotImageRef
        let diff: SnapshotImageRef?
        let sizeMismatch: Bool
        let widthDelta: Int
        let heightDelta: Int
        let changedPixels: Int
        let totalPixels: Int
        let changedFraction: Double
        let maxChannelDelta: Int
        let boundingBoxes: [SnapshotBoundingBox]
        let failureAssociated: Bool
        let diffSynthesized: Bool

        enum CodingKeys: String, CodingKey {
            case name, expected, actual, diff, sizeMismatch, widthDelta, heightDelta
            case changedPixels, totalPixels, changedFraction, maxChannelDelta, boundingBoxes
            case failureAssociated, diffSynthesized
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(expected, forKey: .expected)
            try container.encode(actual, forKey: .actual)
            // Explicit null rather than a missing key: the viewer distinguishes "no diff available".
            try container.encode(diff, forKey: .diff)
            try container.encode(sizeMismatch, forKey: .sizeMismatch)
            try container.encode(widthDelta, forKey: .widthDelta)
            try container.encode(heightDelta, forKey: .heightDelta)
            try container.encode(changedPixels, forKey: .changedPixels)
            try container.encode(totalPixels, forKey: .totalPixels)
            try container.encode(changedFraction, forKey: .changedFraction)
            try container.encode(maxChannelDelta, forKey: .maxChannelDelta)
            try container.encode(boundingBoxes, forKey: .boundingBoxes)
            try container.encode(failureAssociated, forKey: .failureAssociated)
            try container.encode(diffSynthesized, forKey: .diffSynthesized)
        }
    }

    struct SnapshotBitmap {
        let width: Int
        let height: Int
        /// RGBA8, row-major, `width * height * 4` bytes.
        let pixels: [UInt8]
    }

    struct SnapshotDiffResult {
        let width: Int
        let height: Int
        let changed: [Bool]
        let changedPixels: Int
        let maxChannelDelta: Int
        let boundingBoxes: [SnapshotBoundingBox]
    }

    var snapshotDiffEnabled: Bool { !noSnapshotDiff }

    // MARK: - Detection

    static func parseSnapshotAttachmentName(_ rawName: String) -> (name: String, role: SnapshotRole)? {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = snapshotAttachmentNameRegex.firstMatch(in: trimmed, options: [], range: range),
            let nameRange = Range(match.range(at: 1), in: trimmed),
            let roleRange = Range(match.range(at: 2), in: trimmed)
        else {
            return nil
        }

        let role: SnapshotRole
        switch String(trimmed[roleRange]).lowercased() {
        case "expected", "reference": role = .expected
        case "actual", "failure": role = .actual
        default: role = .diff
        }
        return (String(trimmed[nameRange]), role)
    }

    /// Builds one comparison per attachment group that has both an expected and an actual image.
    func buildSnapshotComparisons(attachments: [AttachmentManifestItem]) -> [SnapshotComparison] {
        guard snapshotDiffEnabled, !attachments.isEmpty else { return [] }

        struct Group {
            var displayName: String
            var items: [SnapshotRole: AttachmentManifestItem] = [:]
            var failureAssociated = false
        }

        var groups = [String: Group]()
        var order = [String]()
        for attachment in attachments {
            guard let rawName = attachment.suggestedHumanReadableName,
                let parsed = Self.parseSnapshotAttachmentName(rawName)
            else { continue }

            let key = parsed.name.lowercased()
            if groups[key] == nil {
                groups[key] = Group(displayName: parsed.name)
                order.append(key)
            }
            if groups[key]?.items[parsed.role] == nil {
                groups[key]?.items[parsed.role] = attachment
            }
            if attachment.isAssociatedWithFailure == true {
                groups[key]?.failureAssociated = true
            }
        }

        var comparisons = [SnapshotComparison]()
        for key in order {
            guard let group = groups[key],
                let expectedItem = group.items[.expected],
                let actualItem = group.items[.actual]
            else { continue }

            if let comparison = makeSnapshotComparison(
                name: group.displayName,
                expectedItem: expectedItem,
                actualItem: actualItem,
                diffItem: group.items[.diff],
                failureAssociated: group.failureAssociated)
            {
                comparisons.append(comparison)
            }
        }
        return comparisons
    }

    private func makeSnapshotComparison(
        name: String,
        expectedItem: AttachmentManifestItem,
        actualItem: AttachmentManifestItem,
        diffItem: AttachmentManifestItem?,
        failureAssociated: Bool
    ) -> SnapshotComparison? {
        let directory = attachmentsDirectoryPath
        let expectedPath = (directory as NSString).appendingPathComponent(expectedItem.exportedFileName)
        let actualPath = (directory as NSString).appendingPathComponent(actualItem.exportedFileName)
        guard let expectedBitmap = loadSnapshotBitmap(atPath: expectedPath),
            let actualBitmap = loadSnapshotBitmap(atPath: actualPath)
        else { return nil }

        let result = compareSnapshotBitmaps(
            expected: expectedBitmap, actual: actualBitmap, tolerance: snapshotTolerance)

        var diffRef: SnapshotImageRef?
        var diffSynthesized = false
        if let diffItem,
            let diffBitmap = loadSnapshotBitmap(
                atPath: (directory as NSString).appendingPathComponent(diffItem.exportedFileName))
        {
            diffRef = snapshotImageRef(
                fileName: diffItem.exportedFileName,
                width: diffBitmap.width,
                height: diffBitmap.height)
        } else if let synthesizedFileName = synthesizeSnapshotDiffImage(
            expected: expectedBitmap,
            actual: actualBitmap,
            result: result,
            expectedFileName: expectedItem.exportedFileName)
        {
            diffRef = snapshotImageRef(
                fileName: synthesizedFileName, width: result.width, height: result.height)
            diffSynthesized = true
        }

        let totalPixels = result.width * result.height
        let fraction = totalPixels > 0 ? Double(result.changedPixels) / Double(totalPixels) : 0
        let sizeMismatch =
            expectedBitmap.width != actualBitmap.width || expectedBitmap.height != actualBitmap.height
        return SnapshotComparison(
            name: name,
            expected: snapshotImageRef(
                fileName: expectedItem.exportedFileName,
                width: expectedBitmap.width,
                height: expectedBitmap.height),
            actual: snapshotImageRef(
                fileName: actualItem.exportedFileName,
                width: actualBitmap.width,
                height: actualBitmap.height),
            diff: diffRef,
            sizeMismatch: sizeMismatch,
            widthDelta: actualBitmap.width - expectedBitmap.width,
            heightDelta: actualBitmap.height - expectedBitmap.height,
            changedPixels: result.changedPixels,
            totalPixels: totalPixels,
            changedFraction: (fraction * 1_000_000).rounded() / 1_000_000,
            maxChannelDelta: result.maxChannelDelta,
            boundingBoxes: result.boundingBoxes,
            failureAssociated: failureAssociated,
            diffSynthesized: diffSynthesized)
    }

    func snapshotDeviceInfo(testDetails: TestDetails?, fallbackDevice: Device?) -> SnapshotDeviceInfo {
        func nonEmpty(_ value: String?) -> String? {
            guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return value
        }

        let device = testDetails?.devices.first ?? fallbackDevice
        return SnapshotDeviceInfo(
            name: nonEmpty(device?.modelName) ?? nonEmpty(device?.deviceName),
            deviceName: nonEmpty(device?.deviceName),
            osVersion: nonEmpty(device?.osVersion),
            osBuildNumber: nonEmpty(device?.osBuildNumber),
            platform: nonEmpty(device?.platform),
            identifier: nonEmpty(device?.deviceId))
    }

    func snapshotImageRef(fileName: String, width: Int, height: Int) -> SnapshotImageRef {
        SnapshotImageRef(
            src: attachmentRelativePathForTestPage(fileName: fileName),
            rootSrc: "attachments/\(urlEncodePath(fileName))",
            width: width,
            height: height)
    }

    // MARK: - Comparison

    /// Compares top-left aligned over the union rect; pixels present in only one image count as changed.
    func compareSnapshotBitmaps(
        expected: SnapshotBitmap, actual: SnapshotBitmap, tolerance: Int
    ) -> SnapshotDiffResult {
        let width = max(expected.width, actual.width)
        let height = max(expected.height, actual.height)
        var changed = [Bool](repeating: false, count: max(0, width * height))
        var changedPixels = 0
        var maxChannelDelta = 0
        let boundedTolerance = max(0, tolerance)

        expected.pixels.withUnsafeBufferPointer { expectedBuffer in
            actual.pixels.withUnsafeBufferPointer { actualBuffer in
                for y in 0..<height {
                    let inExpectedRow = y < expected.height
                    let inActualRow = y < actual.height
                    let rowOffset = y * width
                    for x in 0..<width {
                        let inExpected = inExpectedRow && x < expected.width
                        let inActual = inActualRow && x < actual.width
                        if !inExpected || !inActual {
                            changed[rowOffset + x] = true
                            changedPixels += 1
                            maxChannelDelta = 255
                            continue
                        }

                        let expectedIndex = (y * expected.width + x) * 4
                        let actualIndex = (y * actual.width + x) * 4
                        var pixelDelta = 0
                        for channel in 0..<4 {
                            let delta = abs(
                                Int(expectedBuffer[expectedIndex + channel])
                                    - Int(actualBuffer[actualIndex + channel]))
                            if delta > pixelDelta { pixelDelta = delta }
                        }
                        if pixelDelta > maxChannelDelta { maxChannelDelta = pixelDelta }
                        if pixelDelta > boundedTolerance {
                            changed[rowOffset + x] = true
                            changedPixels += 1
                        }
                    }
                }
            }
        }

        return SnapshotDiffResult(
            width: width,
            height: height,
            changed: changed,
            changedPixels: changedPixels,
            maxChannelDelta: maxChannelDelta,
            boundingBoxes: snapshotBoundingBoxes(changed: changed, width: width, height: height))
    }

    /// Connected runs of changed pixels, coalesced into a small set of rectangles.
    func snapshotBoundingBoxes(changed: [Bool], width: Int, height: Int) -> [SnapshotBoundingBox] {
        guard width > 0, height > 0, changed.count >= width * height else { return [] }

        struct Run {
            let y: Int
            let start: Int
            let end: Int
        }

        var runs = [Run]()
        var parents = [Int]()
        var previousRowRange = 0..<0

        func find(_ index: Int) -> Int {
            var root = index
            while parents[root] != root { root = parents[root] }
            var current = index
            while parents[current] != root {
                let next = parents[current]
                parents[current] = root
                current = next
            }
            return root
        }

        func union(_ lhs: Int, _ rhs: Int) {
            let lhsRoot = find(lhs)
            let rhsRoot = find(rhs)
            if lhsRoot != rhsRoot { parents[rhsRoot] = lhsRoot }
        }

        for y in 0..<height {
            let rowStartIndex = runs.count
            var x = 0
            while x < width {
                guard changed[y * width + x] else {
                    x += 1
                    continue
                }
                var end = x
                while end + 1 < width && changed[y * width + end + 1] { end += 1 }
                runs.append(Run(y: y, start: x, end: end))
                parents.append(runs.count - 1)
                let current = runs.count - 1
                for previous in previousRowRange
                where runs[previous].start <= end + 1 && x <= runs[previous].end + 1 {
                    union(previous, current)
                }
                x = end + 2
            }
            previousRowRange = rowStartIndex..<runs.count
        }

        guard !runs.isEmpty else { return [] }

        var boxesByRoot = [Int: (minX: Int, minY: Int, maxX: Int, maxY: Int)]()
        for (index, run) in runs.enumerated() {
            let root = find(index)
            if var box = boxesByRoot[root] {
                box.minX = min(box.minX, run.start)
                box.maxX = max(box.maxX, run.end)
                box.minY = min(box.minY, run.y)
                box.maxY = max(box.maxY, run.y)
                boxesByRoot[root] = box
            } else {
                boxesByRoot[root] = (run.start, run.y, run.end, run.y)
            }
        }

        var boxes = boxesByRoot.values.map {
            SnapshotBoundingBox(
                x: $0.minX, y: $0.minY, w: $0.maxX - $0.minX + 1, h: $0.maxY - $0.minY + 1)
        }
        boxes.sort { ($0.area, -$0.y, -$0.x) > ($1.area, -$1.y, -$1.x) }
        if boxes.count > snapshotMaxComponentsToMerge {
            boxes = Array(boxes.prefix(snapshotMaxComponentsToMerge))
        }

        var merged = coalesceSnapshotBoundingBoxes(boxes, gap: snapshotBoundingBoxMergeGap)
        merged.sort { ($0.area, -$0.y, -$0.x) > ($1.area, -$1.y, -$1.x) }
        return Array(merged.prefix(snapshotMaxBoundingBoxes))
    }

    func coalesceSnapshotBoundingBoxes(_ boxes: [SnapshotBoundingBox], gap: Int)
        -> [SnapshotBoundingBox]
    {
        func overlaps(_ lhs: SnapshotBoundingBox, _ rhs: SnapshotBoundingBox) -> Bool {
            lhs.x - gap <= rhs.x + rhs.w + gap && rhs.x - gap <= lhs.x + lhs.w + gap
                && lhs.y - gap <= rhs.y + rhs.h + gap && rhs.y - gap <= lhs.y + lhs.h + gap
        }

        var result = [SnapshotBoundingBox]()
        for box in boxes {
            var candidate = box
            var index = 0
            while index < result.count {
                if overlaps(result[index], candidate) {
                    let other = result.remove(at: index)
                    let minX = min(candidate.x, other.x)
                    let minY = min(candidate.y, other.y)
                    let maxX = max(candidate.x + candidate.w, other.x + other.w)
                    let maxY = max(candidate.y + candidate.h, other.y + other.h)
                    candidate = SnapshotBoundingBox(
                        x: minX, y: minY, w: maxX - minX, h: maxY - minY)
                    index = 0
                } else {
                    index += 1
                }
            }
            result.append(candidate)
        }
        return result
    }

    // MARK: - Images

    func loadSnapshotBitmap(atPath path: String) -> SnapshotBitmap? {
        guard FileManager.default.fileExists(atPath: path),
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        let width = image.width
        let height = image.height
        guard width > 0, height > 0, width * height <= snapshotMaxPixels else { return nil }

        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var didDraw = false
        pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress,
                let context = CGContext(
                    data: base,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(
                image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            didDraw = true
        }
        guard didDraw else { return nil }
        return SnapshotBitmap(width: width, height: height, pixels: pixels)
    }

    /// Renders the union canvas: unchanged pixels dimmed to grayscale, changed pixels magenta,
    /// and area that exists in only one image hatched so a pure size change is obvious.
    func renderSnapshotDiffPixels(
        expected: SnapshotBitmap, actual: SnapshotBitmap, result: SnapshotDiffResult
    ) -> [UInt8] {
        var output = [UInt8](repeating: 255, count: result.width * result.height * 4)
        for y in 0..<result.height {
            for x in 0..<result.width {
                let outIndex = (y * result.width + x) * 4
                let inExpected = y < expected.height && x < expected.width
                let inActual = y < actual.height && x < actual.width

                if !inExpected || !inActual {
                    let onStripe = ((x + y) % 8) < 4
                    output[outIndex] = onStripe ? 255 : 90
                    output[outIndex + 1] = onStripe ? 0 : 90
                    output[outIndex + 2] = onStripe ? 255 : 90
                    output[outIndex + 3] = 255
                    continue
                }

                if result.changed[y * result.width + x] {
                    output[outIndex] = 255
                    output[outIndex + 1] = 0
                    output[outIndex + 2] = 255
                    output[outIndex + 3] = 255
                    continue
                }

                let expectedIndex = (y * expected.width + x) * 4
                let luminance =
                    0.299 * Double(expected.pixels[expectedIndex])
                    + 0.587 * Double(expected.pixels[expectedIndex + 1])
                    + 0.114 * Double(expected.pixels[expectedIndex + 2])
                let dimmed = UInt8(max(0, min(255, luminance * 0.45 + 110)))
                output[outIndex] = dimmed
                output[outIndex + 1] = dimmed
                output[outIndex + 2] = dimmed
                output[outIndex + 3] = 255
            }
        }
        return output
    }

    private func synthesizeSnapshotDiffImage(
        expected: SnapshotBitmap,
        actual: SnapshotBitmap,
        result: SnapshotDiffResult,
        expectedFileName: String
    ) -> String? {
        guard result.width > 0, result.height > 0 else { return nil }
        let baseName = (expectedFileName as NSString).deletingPathExtension
        let fileName = "\(baseName).synth-diff.png"
        let destinationPath = (attachmentsDirectoryPath as NSString).appendingPathComponent(fileName)
        let pixels = renderSnapshotDiffPixels(expected: expected, actual: actual, result: result)

        var wrote = false
        snapshotDiffWriteQueue.sync {
            wrote = writeSnapshotPNG(
                pixels: pixels, width: result.width, height: result.height, toPath: destinationPath)
        }
        return wrote ? fileName : nil
    }

    @discardableResult
    func writeSnapshotPNG(pixels: [UInt8], width: Int, height: Int, toPath path: String) -> Bool {
        guard width > 0, height > 0, pixels.count == width * height * 4 else { return false }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
            let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent),
            let destination = CGImageDestinationCreateWithURL(
                URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)
        else { return false }

        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
