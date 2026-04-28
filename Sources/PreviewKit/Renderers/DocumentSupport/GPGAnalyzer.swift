// GPGAnalyzer — parse the ASCII-armor envelope of a GPG/PGP file.
//
// Intentionally scoped to the armor header: we never attempt to decode
// OpenPGP packet bodies (decryption/verification requires key material
// Cairn cannot reasonably offer). The armor alone gives us block type,
// optional Version / Comment headers, approximate body size, and — when
// present — a key ID recorded in a "Comment: 0x…" header.

import Foundation

public enum GPGBlockType: String, Sendable {
    case message      = "MESSAGE"
    case signature    = "SIGNATURE"
    case publicKey    = "PUBLIC KEY BLOCK"
    case privateKey   = "PRIVATE KEY BLOCK"
    case signedMessage = "SIGNED MESSAGE"
    case unknown      = "UNKNOWN"
}

public struct GPGSpecimen: Sendable {
    public var isArmored: Bool
    public var blockType: GPGBlockType
    public var version: String?
    public var comment: String?
    public var hashAlgorithm: String?
    public var bodyByteCount: Int
    public var keyIDHex: String?
}

public enum GPGAnalyzer {

    /// Parse an ASCII-armored or binary OpenPGP file. For binary files we
    /// report `isArmored = false` plus block-type `.unknown` — the full
    /// OpenPGP packet parser is out of scope for v1 (see CLAUDE.md).
    public static func parse(data: Data) -> GPGSpecimen {
        guard let text = String(data: data, encoding: .utf8),
              let startRange = text.range(of: "-----BEGIN PGP ")
        else {
            return GPGSpecimen(
                isArmored: false, blockType: .unknown,
                version: nil, comment: nil, hashAlgorithm: nil,
                bodyByteCount: data.count, keyIDHex: nil
            )
        }

        // Block type = substring between "BEGIN PGP " and "-----".
        let afterBegin = text[startRange.upperBound...]
        let blockTypeString: String
        if let dashRange = afterBegin.range(of: "-----") {
            blockTypeString = String(afterBegin[..<dashRange.lowerBound])
        } else {
            blockTypeString = "UNKNOWN"
        }
        let blockType = GPGBlockType(rawValue: blockTypeString) ?? .unknown

        // Walk the header lines (until a blank line marks the start of
        // the armored body).
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var version: String?
        var comment: String?
        var hash: String?
        var keyID: String?
        var bodyStartIdx = 0
        var inHeader = false
        for (i, raw) in lines.enumerated() {
            let line = String(raw)
            if line.hasPrefix("-----BEGIN PGP ") { inHeader = true; continue }
            if !inHeader { continue }
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                bodyStartIdx = i + 1
                break
            }
            if let kv = splitHeader(line) {
                switch kv.0.lowercased() {
                case "version":  version = kv.1
                case "comment":
                    comment = kv.1
                    if keyID == nil,
                       let hex = kv.1.first(where: { _ in true }).map({ _ in kv.1 }),
                       let parsed = extractKeyID(hex) { keyID = parsed }
                case "hash":     hash = kv.1
                default:         break
                }
            }
        }
        // Crude body byte count: characters from body start to the matching END marker.
        let body = lines.dropFirst(bodyStartIdx)
            .prefix { !$0.hasPrefix("-----END PGP ") }
            .joined(separator: "\n")
        let bodyBytes = body.count

        return GPGSpecimen(
            isArmored: true,
            blockType: blockType,
            version: version,
            comment: comment,
            hashAlgorithm: hash,
            bodyByteCount: bodyBytes,
            keyIDHex: keyID
        )
    }

    // MARK: - Helpers

    private static func splitHeader(_ line: String) -> (String, String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let k = line[..<colon].trimmingCharacters(in: .whitespaces)
        let v = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return (k, v)
    }

    /// Recognise a hex key-id (8 or 16 hex chars, optionally 0x-prefixed) in
    /// a free-form comment string.
    public static func extractKeyID(_ text: String) -> String? {
        let upper = text.uppercased()
        let hexes = upper.components(separatedBy: .whitespaces)
        for token in hexes {
            let stripped = token.hasPrefix("0X") ? String(token.dropFirst(2)) : token
            let isHex = !stripped.isEmpty && stripped.allSatisfy { $0.isHexDigit }
            if isHex && (stripped.count == 8 || stripped.count == 16) {
                return "0x" + stripped
            }
        }
        return nil
    }
}

private extension Character {
    var isHexDigit: Bool {
        isASCII && (isNumber || ("A"..."F").contains(self) || ("a"..."f").contains(self))
    }
}
