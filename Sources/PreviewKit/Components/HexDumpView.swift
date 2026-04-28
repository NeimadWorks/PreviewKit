// HexDumpView — monospaced offset / hex / ASCII grid.
//
// Used by the binary fallback and as a debug aid in other renderers.
// Renders up to `maxBytes` bytes; callers pass whatever slice they care
// about. Selectable text so users can copy portions of the dump.

import SwiftUI

public struct HexDumpView: View {

    public let data: Data
    public let maxBytes: Int
    public let bytesPerRow: Int

    public init(data: Data, maxBytes: Int = 256, bytesPerRow: Int = 16) {
        self.data = data
        self.maxBytes = maxBytes
        self.bytesPerRow = bytesPerRow
    }

    public var body: some View {
        let text = Self.render(data: data, maxBytes: maxBytes, bytesPerRow: bytesPerRow)
        ScrollView(.vertical) {
            Text(text)
                .font(PreviewTokens.fontMono)
                .foregroundStyle(PreviewTokens.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .background(PreviewTokens.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd))
        .overlay(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                .strokeBorder(PreviewTokens.borderFaint, lineWidth: PreviewTokens.borderWidth)
        )
    }

    /// Exposed for tests that want to assert the formatting without
    /// mounting SwiftUI.
    public static func render(data: Data, maxBytes: Int = 256, bytesPerRow: Int = 16) -> String {
        let count = min(data.count, max(1, maxBytes))
        var out = ""
        out.reserveCapacity(count / bytesPerRow * 75)

        var offset = 0
        while offset < count {
            let end = min(offset + bytesPerRow, count)
            let slice = data[offset..<end]

            // Offset column (6 hex digits)
            out += String(format: "%06X  ", offset)

            // Hex column, padded to full row width so ASCII column aligns
            for i in 0..<bytesPerRow {
                if i < (end - offset) {
                    let byte = slice[slice.startIndex + i]
                    out += String(format: "%02X ", byte)
                } else {
                    out += "   "
                }
                if i == bytesPerRow / 2 - 1 { out += " " }   // mid-row gap
            }

            // ASCII column
            out += " "
            for i in 0..<(end - offset) {
                let byte = slice[slice.startIndex + i]
                if byte >= 0x20 && byte < 0x7F {
                    out.append(Character(UnicodeScalar(byte)))
                } else {
                    out += "·"
                }
            }
            out += "\n"
            offset = end
        }

        if data.count > count {
            out += "\n… \(data.count - count) more bytes truncated"
        }
        return out
    }
}
