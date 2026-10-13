import Compression
import Foundation

/// Reads the classic ZIP format emitted by ZipArchiveWriter without invoking an external utility.
/// Only flat attachment names are recovered; archive paths are never interpreted as disk paths.
final class ReportBundleReader {
    struct Entry {
        let name: String
        let method: UInt16
        let crc: UInt32
        let compressedSize: Int
        let size: Int
        let localOffset: UInt64
    }

    private let handle: FileHandle
    private let centralOffset: UInt64
    let entries: [Entry]

    init(path: String) throws {
        let file = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        do {
            let fileSize = try file.seekToEnd()
            guard fileSize >= 22 else { throw Self.invalidArchive() }
            let tailSize = Int(min(fileSize, 65_557))
            try file.seek(toOffset: fileSize - UInt64(tailSize))
            let tail = try Self.read(file, count: tailSize)
            let endIndex = stride(from: tail.count - 22, through: 0, by: -1).first { index in
                tail.le32(index) == 0x0605_4B50 && index + 22 + Int(tail.le16(index + 20)) == tail.count
            }
            guard let endIndex, tail.le16(endIndex + 4) == 0, tail.le16(endIndex + 6) == 0,
                tail.le16(endIndex + 8) == tail.le16(endIndex + 10),
                tail.le16(endIndex + 10) != UInt16.max,
                tail.le32(endIndex + 16) != UInt32.max, tail.le32(endIndex + 12) != UInt32.max else { throw Self.invalidArchive() }
            let offset = UInt64(tail.le32(endIndex + 16))
            let size = UInt64(tail.le32(endIndex + 12))
            let endOffset = fileSize - UInt64(tailSize) + UInt64(endIndex)
            guard offset + size == endOffset else { throw Self.invalidArchive() }
            try file.seek(toOffset: offset)
            var parsed: [Entry] = []
            var cursor = offset
            var names = Set<String>()
            for _ in 0..<Int(tail.le16(endIndex + 10)) {
                guard cursor + 46 <= endOffset else { throw Self.invalidArchive() }
                let header = try Self.read(file, count: 46)
                guard header.le32(0) == 0x0201_4B50, header.le16(34) == 0,
                    header.le16(8) & 1 == 0, header.le32(20) != UInt32.max,
                    header.le32(24) != UInt32.max, header.le32(42) != UInt32.max else { throw Self.invalidArchive() }
                let nameCount = Int(header.le16(28))
                let remainder = nameCount + Int(header.le16(30)) + Int(header.le16(32))
                guard cursor + 46 + UInt64(remainder) <= endOffset else { throw Self.invalidArchive() }
                let extra = try Self.read(file, count: remainder)
                guard let name = String(data: extra.prefix(nameCount), encoding: .utf8),
                    names.insert(name).inserted else { throw Self.invalidArchive() }
                parsed.append(Entry(name: name, method: header.le16(10), crc: header.le32(16),
                    compressedSize: Int(header.le32(20)), size: Int(header.le32(24)),
                    localOffset: UInt64(header.le32(42))))
                cursor += 46 + UInt64(remainder)
            }
            guard cursor == endOffset else { throw Self.invalidArchive() }
            handle = file
            centralOffset = offset
            entries = parsed
        } catch {
            try? file.close()
            throw error
        }
    }

    deinit { try? handle.close() }

    func data(for entry: Entry) throws -> Data {
        guard entry.localOffset + 30 <= centralOffset else { throw Self.invalidArchive() }
        try handle.seek(toOffset: entry.localOffset)
        let header = try Self.read(handle, count: 30)
        guard header.le32(0) == 0x0403_4B50, header.le16(8) == entry.method,
            header.le16(6) & 1 == 0 else { throw Self.invalidArchive() }
        let nameCount = Int(header.le16(26))
        let extraCount = Int(header.le16(28))
        let payloadOffset = entry.localOffset + 30 + UInt64(nameCount + extraCount)
        guard payloadOffset + UInt64(entry.compressedSize) <= centralOffset else { throw Self.invalidArchive() }
        let name = try Self.read(handle, count: nameCount)
        guard String(data: name, encoding: .utf8) == entry.name else { throw Self.invalidArchive() }
        try handle.seek(toOffset: payloadOffset)
        let payload = try Self.read(handle, count: entry.compressedSize)
        let decoded: Data
        if entry.method == 0 {
            decoded = payload
        } else if entry.method == 8, entry.size > 0 {
            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: entry.size)
            defer { destination.deallocate() }
            let written = payload.withUnsafeBytes { raw -> Int in
                guard let source = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(destination, entry.size, source, payload.count, nil, COMPRESSION_ZLIB)
            }
            guard written == entry.size else { throw Self.invalidArchive() }
            decoded = Data(bytes: destination, count: written)
        } else { throw Self.invalidArchive() }
        guard decoded.count == entry.size, ZipArchiveWriter.crc32(decoded) == entry.crc else {
            throw Self.invalidArchive()
        }
        return decoded
    }

    private static func read(_ handle: FileHandle, count: Int) throws -> Data {
        let data = try handle.read(upToCount: count) ?? Data()
        guard data.count == count else { throw invalidArchive() }
        return data
    }

    private static func invalidArchive() -> XCTestReport.RuntimeError {
        XCTestReport.RuntimeError(message: "Invalid or unsupported report ZIP bundle; original output was preserved.")
    }
}

private extension Data {
    func le16(_ index: Int) -> UInt16 {
        UInt16(self[index]) | UInt16(self[index + 1]) << 8
    }
    func le32(_ index: Int) -> UInt32 {
        UInt32(le16(index)) | UInt32(le16(index + 2)) << 16
    }
}

extension XCTestReport {
    func recoverBundledAttachments() throws {
        let root = URL(fileURLWithPath: testPagesDirectoryPath)
        guard FileManager.default.fileExists(atPath: root.path) else { return }
        let bundles = try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil).filter { $0.pathExtension.lowercased() == "zip" }
        let attachmentRoot = URL(fileURLWithPath: attachmentsDirectoryPath)
        try FileManager.default.createDirectory(at: attachmentRoot, withIntermediateDirectories: true)
        for url in bundles {
            let reader = try ReportBundleReader(path: url.path)
            for entry in reader.entries where entry.name.hasPrefix(Self.bundleAttachmentsPrefix) {
                let name = String(entry.name.dropFirst(Self.bundleAttachmentsPrefix.count))
                guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
                    !name.contains("\\"), !name.contains("\0") else {
                    throw RuntimeError(message: "Unsafe attachment name in report bundle: \(url.lastPathComponent)")
                }
                let destination = attachmentRoot.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: destination.path) {
                    try reader.data(for: entry).write(to: destination, options: .atomic)
                }
            }
        }
    }

    func validateRegenerationAttachments(_ attachmentsByTest: [String: [AttachmentManifestItem]]) throws {
        let missing = Set(attachmentsByTest.values.flatMap { $0 }.map { $0.exportedFileName }).filter {
            !FileManager.default.fileExists(atPath: URL(fileURLWithPath: attachmentsDirectoryPath).appendingPathComponent($0).path)
        }
        guard missing.isEmpty else {
            throw RuntimeError(message: "Cannot regenerate: \(missing.count) manifest attachments are absent from both loose files and report bundles. Re-run from the original .xcresult; existing output was preserved.")
        }
    }
}
