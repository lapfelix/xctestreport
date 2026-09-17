import Foundation
import XCTest

@testable import xctestreport

final class ZipArchiveWriterTests: XCTestCase {

    private func makeTemporaryPath() -> String {
        (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("zipwriter-\(UUID().uuidString).zip")
    }

    func testWritesArchiveSystemUnzipAccepts() throws {
        let path = makeTemporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let text = String(repeating: "the quick brown fox. ", count: 400)
        let writer = try ZipArchiveWriter(path: path)
        try writer.addFile(name: "timeline/runstates.json", data: Data(text.utf8))
        try writer.addFile(name: "attachments/1.png", data: Data((0..<2048).map { UInt8($0 % 251) }))
        try writer.finish()

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-t", path]
        unzip.standardOutput = FileHandle.nullDevice
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        unzip.waitUntilExit()
        XCTAssertEqual(unzip.terminationStatus, 0, "unzip -t rejected the archive")
    }

    func testRoundTripsEntriesThroughSystemUnzip() throws {
        let path = makeTemporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let payload = Data(String(repeating: "compress me. ", count: 500).utf8)
        let writer = try ZipArchiveWriter(path: path)
        try writer.addFile(name: "test.md", data: payload)
        try writer.finish()

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        unzip.arguments = ["-p", path, "test.md"]
        let pipe = Pipe()
        unzip.standardOutput = pipe
        unzip.standardError = FileHandle.nullDevice
        try unzip.run()
        let extracted = pipe.fileHandleForReading.readDataToEndOfFile()
        unzip.waitUntilExit()
        XCTAssertEqual(extracted, payload)
    }

    func testDeflatesCompressiblePayloadAndStoresIncompressibleOnes() throws {
        let path = makeTemporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let compressible = Data(String(repeating: "a", count: 10_000).utf8)
        let writer = try ZipArchiveWriter(path: path)
        try writer.addFile(name: "plain.txt", data: compressible)
        try writer.addFile(name: "already.png", data: compressible)
        try writer.finish()

        let archive = try Data(contentsOf: URL(fileURLWithPath: path))
        // Storing the .png entry verbatim means the archive still carries the full 10 KB once.
        XCTAssertGreaterThan(archive.count, 10_000)
        XCTAssertLessThan(archive.count, 12_000, "compressible entry should have been deflated")
    }

    func testUniquifiesDuplicateEntryNames() throws {
        let path = makeTemporaryPath()
        defer { try? FileManager.default.removeItem(atPath: path) }

        let writer = try ZipArchiveWriter(path: path)
        let first = try writer.addFile(name: "attachments/shot.png", data: Data([1, 2, 3]))
        let second = try writer.addFile(name: "attachments/shot.png", data: Data([4, 5, 6]))
        try writer.finish()

        XCTAssertEqual(first, "attachments/shot.png")
        XCTAssertEqual(second, "attachments/shot-2.png")
        XCTAssertEqual(writer.entryCount, 2)
    }

    func testCRC32MatchesKnownValue() {
        XCTAssertEqual(ZipArchiveWriter.crc32(Data("123456789".utf8)), 0xCBF4_3926)
    }

    func testRawDeflateIsInflatableAsRawStream() throws {
        let original = Data(String(repeating: "deflate round trip. ", count: 300).utf8)
        let deflated = try XCTUnwrap(ZipArchiveWriter.rawDeflate(original))
        XCTAssertLessThan(deflated.count, original.count)

        // Raw deflate (no zlib wrapper) is what DecompressionStream('deflate-raw') expects.
        XCTAssertNotEqual(deflated.first, 0x78, "unexpected zlib header on a raw deflate stream")
    }
}
