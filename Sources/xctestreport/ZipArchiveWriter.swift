import Compression
import Foundation

/// Minimal streaming ZIP writer for per-test report bundles.
///
/// Entries use either store (0) or raw deflate (8) so a browser can inflate them with
/// `DecompressionStream('deflate-raw')`; the central directory lands at the end of the file, which
/// is what lets the reader pull one entry out of a remote bundle with two Range requests.
final class ZipArchiveWriter {
    struct Options {
        /// Already-compressed payloads (PNG, JPEG, MP4) only grow when deflated again.
        static let incompressibleExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "heic", "mp4", "mov", "m4v", "zip", "gz",
        ]
    }

    private struct CentralEntry {
        let name: [UInt8]
        let method: UInt16
        let crc: UInt32
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
    }

    private let handle: FileHandle
    private var entries: [CentralEntry] = []
    private var offset: UInt64 = 0
    private var names = Set<String>()
    private var finished = false

    /// Fixed DOS timestamp (1980-01-01) keeps bundles byte-identical across runs of the same result.
    private static let dosTime: UInt16 = 0
    private static let dosDate: UInt16 = 0x0021

    init(path: String) throws {
        let fm = FileManager.default
        try? fm.removeItem(atPath: path)
        fm.createFile(atPath: path, contents: nil)
        guard let handle = FileHandle(forWritingAtPath: path) else {
            throw XCTestReport.RuntimeError(message: "Could not open bundle for writing: \(path)")
        }
        self.handle = handle
    }

    /// Returns the name the entry was stored under, which may be uniquified on collision.
    @discardableResult
    func addFile(name: String, data: Data, compress: Bool? = nil) throws -> String {
        precondition(!finished, "ZipArchiveWriter.addFile after finish()")
        // Offsets and sizes are 32-bit in a classic archive; refuse rather than trap on overflow.
        guard data.count <= Int(UInt32.max), offset < UInt64(UInt32.max) else {
            throw XCTestReport.RuntimeError(
                message: "Report bundle exceeds the 4 GB ZIP limit while adding \(name).")
        }
        let storedName = uniqueName(for: name)
        let nameBytes = Array(storedName.utf8)

        let shouldCompress =
            compress ?? !Options.incompressibleExtensions.contains(
                (storedName as NSString).pathExtension.lowercased())

        var method: UInt16 = 0
        var payload = data
        if shouldCompress, data.count > 64, let deflated = Self.rawDeflate(data),
            deflated.count < data.count
        {
            method = 8
            payload = deflated
        }

        let crc = Self.crc32(data)
        let localHeaderOffset = UInt32(offset)

        var header = Data()
        header.appendLE(UInt32(0x0403_4B50))
        header.appendLE(UInt16(20))  // version needed
        header.appendLE(UInt16(0x0800))  // UTF-8 names
        header.appendLE(method)
        header.appendLE(Self.dosTime)
        header.appendLE(Self.dosDate)
        header.appendLE(crc)
        header.appendLE(UInt32(payload.count))
        header.appendLE(UInt32(data.count))
        header.appendLE(UInt16(nameBytes.count))
        header.appendLE(UInt16(0))  // extra field length
        header.append(contentsOf: nameBytes)

        handle.write(header)
        handle.write(payload)
        offset += UInt64(header.count + payload.count)

        entries.append(
            CentralEntry(
                name: nameBytes,
                method: method,
                crc: crc,
                compressedSize: UInt32(payload.count),
                uncompressedSize: UInt32(data.count),
                localHeaderOffset: localHeaderOffset))
        return storedName
    }

    @discardableResult
    func addFile(name: String, contentsOfFile path: String, compress: Bool? = nil) throws -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try addFile(name: name, data: data, compress: compress)
    }

    func finish() throws {
        guard !finished else { return }
        finished = true

        let centralStart = offset
        guard centralStart < UInt64(UInt32.max) else {
            throw XCTestReport.RuntimeError(message: "Report bundle exceeds the 4 GB ZIP limit.")
        }
        var central = Data()
        for entry in entries {
            central.appendLE(UInt32(0x0201_4B50))
            central.appendLE(UInt16(20))  // version made by
            central.appendLE(UInt16(20))  // version needed
            central.appendLE(UInt16(0x0800))
            central.appendLE(entry.method)
            central.appendLE(Self.dosTime)
            central.appendLE(Self.dosDate)
            central.appendLE(entry.crc)
            central.appendLE(entry.compressedSize)
            central.appendLE(entry.uncompressedSize)
            central.appendLE(UInt16(entry.name.count))
            central.appendLE(UInt16(0))  // extra
            central.appendLE(UInt16(0))  // comment
            central.appendLE(UInt16(0))  // disk number
            central.appendLE(UInt16(0))  // internal attrs
            central.appendLE(UInt32(0))  // external attrs
            central.appendLE(entry.localHeaderOffset)
            central.append(contentsOf: entry.name)
        }

        let centralDirectorySize = UInt32(central.count)
        central.appendLE(UInt32(0x0605_4B50))
        central.appendLE(UInt16(0))  // disk number
        central.appendLE(UInt16(0))  // disk with central directory
        central.appendLE(UInt16(entries.count))
        central.appendLE(UInt16(entries.count))
        central.appendLE(centralDirectorySize)
        central.appendLE(UInt32(centralStart))
        central.appendLE(UInt16(0))  // comment length

        handle.write(central)
        try? handle.close()
    }

    var entryCount: Int { entries.count }

    private func uniqueName(for name: String) -> String {
        guard names.contains(name) else {
            names.insert(name)
            return name
        }
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var counter = 2
        while true {
            let candidate = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
            if !names.contains(candidate) {
                names.insert(candidate)
                return candidate
            }
            counter += 1
        }
    }

    static func rawDeflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = data.count + 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }
        let written = data.withUnsafeBytes { raw -> Int in
            guard let source = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(
                destination, capacity, source, data.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { return nil }
        return Data(bytes: destination, count: written)
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { raw in
            for byte in raw.bindMemory(to: UInt8.self) {
                crc = Self.crcTable[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }
}

extension Data {
    fileprivate mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    fileprivate mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}
