// BinaryRenderer — the catch-all fallback.
//
// Accepts every kind (so it can serve as the registry fallback) plus
// the explicit `.binary` and `.machO` kinds. Displays the first 256
// bytes as a hex dump, basic stats, and (when the bytes look like a
// Mach-O) a short load-command summary. Session 4 will swap this to a
// first-class MachORenderer; for Session 1 the fallback is correct
// and ships.

import SwiftUI

public struct BinaryRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { Set(ArtifactKind.allCases) }
    public static var priority: Int { -1000 }
    public static func make() -> BinaryRenderer { BinaryRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(
            BinaryRendererBody(item: item, data: data, url: url)
        )
    }
}

private struct BinaryRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    var body: some View {
        HSplitView {
            renderPane
                .frame(minWidth: PreviewTokens.rendererMinWidth)
            inspectorPane
                .frame(minWidth: PreviewTokens.inspectorMinWidth,
                       idealWidth: PreviewTokens.inspectorIdealWidth)
        }
    }

    // MARK: - Left: hex dump

    private var renderPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let data {
                HexDumpView(data: data, maxBytes: 256)
            } else {
                ContentUnavailableMessage(
                    title: "No byte preview",
                    subtitle: "The data source didn't return in-memory bytes for this item.",
                    symbol: "doc.on.clipboard"
                )
            }
            Spacer()
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: item.kind.symbolName)
                .foregroundStyle(PreviewTokens.mimeColor(for: item.kind.family))
            Text(item.displayName)
                .font(PreviewTokens.fontHeader)
            Text(item.kind.displayLabel)
                .font(PreviewTokens.fontLabel)
                .foregroundStyle(PreviewTokens.textMuted)
            Spacer()
        }
    }

    // MARK: - Right: inspector

    private var inspectorPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                KPITileRow(kpis, columns: 2)
                if !badges.isEmpty {
                    SemanticBadgeRow(badges)
                }
                if let machOSummary = machOSummary {
                    machOPanel(machOSummary)
                }
                CairnMetaBlock(meta: item.cairnMeta)
                Spacer()
            }
            .padding(14)
        }
        .background(PreviewTokens.bgTertiary)
    }

    // MARK: - KPIs

    private var kpis: [KPITile] {
        let mime = item.kind.displayLabel
        let size = formatBytes(Int64(data?.count ?? Int(item.sizeBytes)))
        let entropy = data.map { Self.shannonEntropy(of: $0, limit: 4096) } ?? 0
        return [
            KPITile(value: mime,    label: "Kind"),
            KPITile(value: size,    label: "Size"),
            KPITile(value: String(format: "%.2f", entropy),
                    label: "Entropy",
                    badge: entropy >= 7.5 ? .warning : nil),
            KPITile(value: data?.count.description ?? "—",
                    label: "Bytes read"),
        ]
    }

    private var badges: [SemanticBadgeModel] {
        var out: [SemanticBadgeModel] = []
        if let data, data.count >= 4 {
            let magic = ArtifactKind.infer(fromMagicBytes: data)
            if magic != .binary {
                out.append(SemanticBadgeModel(
                    text: "Magic: \(magic.displayLabel)",
                    style: .info,
                    icon: "shield.checkered"
                ))
            }
        }
        if let data {
            let e = Self.shannonEntropy(of: data, limit: 4096)
            if e >= 7.5 {
                out.append(SemanticBadgeModel(
                    text: "High entropy",
                    style: .warning,
                    icon: "waveform.path.ecg"
                ))
            }
        }
        return out
    }

    // MARK: - Mach-O summary (coarse)

    private var machOSummary: MachOSummary? {
        guard item.kind == .machO, let data else { return nil }
        return MachOSummary.parse(data: data)
    }

    @ViewBuilder
    private func machOPanel(_ s: MachOSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MACH-O")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            row("Type",     s.typeLabel)
            row("Arch",     s.archLabel)
            row("Commands", "\(s.loadCommandCount)")
        }
        .padding(PreviewTokens.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusMd)
                .fill(PreviewTokens.bgSecondary)
        )
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(PreviewTokens.fontMonoLarge)
                .foregroundStyle(PreviewTokens.textPrimary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ b: Int64) -> String {
        let bcf = ByteCountFormatter()
        bcf.countStyle = .file
        return bcf.string(fromByteCount: max(0, b))
    }

    static func shannonEntropy(of data: Data, limit: Int = 4096) -> Double {
        PreviewKit.shannonEntropy(of: data, limit: limit)
    }
}

// MARK: - Module-internal helpers (kept at module scope so tests can
// reach them without elevating everything on BinaryRendererBody to
// public or internal-but-private-looking visibility).

extension PreviewKit {

    /// Shannon entropy over the first `limit` bytes. Exposed so tests
    /// can pin known inputs without mounting a SwiftUI view.
    public static func shannonEntropy(of data: Data, limit: Int = 4096) -> Double {
        let n = min(data.count, limit)
        guard n > 0 else { return 0 }
        var counts = [Int](repeating: 0, count: 256)
        data.prefix(n).forEach { counts[Int($0)] += 1 }
        var h: Double = 0
        let total = Double(n)
        for c in counts where c > 0 {
            let p = Double(c) / total
            h -= p * (log(p) / log(2))
        }
        return h
    }
}

// MARK: - Mach-O minimal parse

/// Minimum-viable Mach-O parse: magic → 32/64/fat + endianness; arch and
/// type from the single-arch header. Good enough for the Session 1
/// fallback. Session 4's dedicated renderer will surface load commands,
/// linked libraries, entitlements, etc.
struct MachOSummary {
    let typeLabel: String
    let archLabel: String
    let loadCommandCount: Int

    static func parse(data: Data) -> MachOSummary? {
        guard data.count >= 32 else { return nil }

        let magic: UInt32 = data.withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self)
        }

        if magic == 0xCAFEBABE || magic == 0xBEBAFECA {
            return MachOSummary(typeLabel: "Fat (universal)",
                                archLabel: "multi-arch",
                                loadCommandCount: 0)
        }

        let is64 = (magic == 0xFEEDFACF || magic == 0xCFFAEDFE)
        let isLE = (magic == 0xFEEDFACE || magic == 0xFEEDFACF)
        guard magic == 0xFEEDFACE || magic == 0xCEFAEDFE
              || magic == 0xFEEDFACF || magic == 0xCFFAEDFE else {
            return nil
        }

        // Offsets in the mach_header[_64]:
        //   0  magic (u32)
        //   4  cputype (i32)
        //   8  cpusubtype (i32)
        //  12  filetype (u32)
        //  16  ncmds (u32)
        let cpuType: Int32   = read(data, at: 4,  as: Int32.self, littleEndian: isLE)
        let filetype: UInt32 = read(data, at: 12, as: UInt32.self, littleEndian: isLE)
        let ncmds: UInt32    = read(data, at: 16, as: UInt32.self, littleEndian: isLE)

        return MachOSummary(
            typeLabel: fileTypeLabel(filetype) + (is64 ? " (64-bit)" : " (32-bit)"),
            archLabel: archLabel(cpuType),
            loadCommandCount: Int(ncmds)
        )
    }

    // Subset of mach-o/loader.h filetype values.
    private static func fileTypeLabel(_ t: UInt32) -> String {
        switch t {
        case 0x1: return "Object"
        case 0x2: return "Executable"
        case 0x3: return "FVMLIB"
        case 0x4: return "Core"
        case 0x5: return "Preload"
        case 0x6: return "Dylib"
        case 0x7: return "Dylinker"
        case 0x8: return "Bundle"
        case 0xA: return "dSYM"
        case 0xB: return "KEXT"
        default:  return "Type \(t)"
        }
    }

    private static func archLabel(_ cpu: Int32) -> String {
        let arm:    Int32 = 0x0000000C
        let arm64:  Int32 = 0x0100000C
        let x86:    Int32 = 0x00000007
        let x86_64: Int32 = 0x01000007
        switch cpu {
        case arm:    return "arm"
        case arm64:  return "arm64"
        case x86:    return "i386"
        case x86_64: return "x86_64"
        default:     return String(format: "cpu 0x%08X", cpu)
        }
    }

    private static func read<T: FixedWidthInteger>(
        _ data: Data, at offset: Int, as: T.Type, littleEndian: Bool
    ) -> T {
        let size = MemoryLayout<T>.size
        guard data.count >= offset + size else { return 0 }
        let raw: T = data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: T.self)
        }
        return littleEndian ? T(littleEndian: raw) : T(bigEndian: raw)
    }
}

// MARK: - Shared content-unavailable block

/// A lightweight in-view empty state used by renderers that can't
/// produce content (no data, load error). Keeps PreviewKit self-
/// contained — we don't rely on macOS 15's `ContentUnavailableView`.
struct ContentUnavailableMessage: View {
    let title: String
    let subtitle: String?
    let symbol: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(PreviewTokens.textGhost)
            Text(title)
                .font(PreviewTokens.fontHeader)
                .foregroundStyle(PreviewTokens.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(PreviewTokens.fontBody)
                    .foregroundStyle(PreviewTokens.textMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusLg)
                .fill(PreviewTokens.bgSecondary)
        )
    }
}
