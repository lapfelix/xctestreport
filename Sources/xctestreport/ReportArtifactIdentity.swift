import Foundation

extension XCTestReport {
    /// Readable, bounded ASCII identifiers with a deterministic suffix from the complete identity.
    /// The suffix distinguishes punctuation, Unicode, and identifiers with identical readable parts.
    static func artifactSlug(identity: String, prefix: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        var readable = ""
        var separator = false
        for byte in identity.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
            if readable.utf8.count >= 80 { continue }
            if (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) {
                if separator && !readable.isEmpty { readable.append("_") }
                readable.append(Character(UnicodeScalar(byte)))
                separator = false
            } else {
                separator = true
            }
        }
        let digest = String(hash, radix: 16)
        return "\(prefix)\(readable.isEmpty ? "item" : readable)-\(String(repeating: "0", count: 16 - digest.count))\(digest)"
    }

    /// Length prefixes avoid ambiguity when a field itself contains the delimiter.
    static func artifactIdentity(_ components: [String]) -> String {
        components.map { "\($0.utf8.count):\($0)" }.joined()
    }
}
