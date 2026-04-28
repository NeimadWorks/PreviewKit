// FontRenderer — CoreText-powered font inspector.
//
// Surface: multi-size specimen (12 / 18 / 24 / 36 / 48pt) + pangram
// + first 96 Unicode glyphs in a grid. Inspector shows family / style
// / version / glyph count / variable / color / monospaced / ligature
// badges + covered Unicode ranges.

import SwiftUI
import CoreText
import AppKit

public struct FontRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.font] }
    public static var priority: Int { 0 }
    public static func make() -> FontRenderer { FontRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(FontRendererBody(item: item, data: data, url: url))
    }
}

// MARK: - Font stats

public struct FontSpecimen: Sendable {
    public let family: String
    public let style: String
    public let version: String
    public let glyphCount: Int
    public let isMonospaced: Bool
    public let hasColorGlyphs: Bool
    public let isVariable: Bool
    public let unicodeRanges: [String]
    public let pangram: String
    public let firstGlyphs: [Character]

    public init(family: String, style: String, version: String, glyphCount: Int,
                isMonospaced: Bool, hasColorGlyphs: Bool, isVariable: Bool,
                unicodeRanges: [String], pangram: String, firstGlyphs: [Character]) {
        self.family = family
        self.style = style
        self.version = version
        self.glyphCount = glyphCount
        self.isMonospaced = isMonospaced
        self.hasColorGlyphs = hasColorGlyphs
        self.isVariable = isVariable
        self.unicodeRanges = unicodeRanges
        self.pangram = pangram
        self.firstGlyphs = firstGlyphs
    }
}

public enum FontAnalyzer {

    /// Load a font from file-system data. Returns nil for unreadable
    /// bytes. Exposed as a public helper for tests.
    public static func loadCTFont(from url: URL, size: CGFloat = 24) -> CTFont? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return loadCTFont(from: data, size: size)
    }

    public static func loadCTFont(from data: Data, size: CGFloat = 24) -> CTFont? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        guard let cgFont = CGFont(provider) else { return nil }
        return CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    }

    /// Pull the front-stage attributes. Ranges + monospaced detection
    /// via CoreText's trait flags.
    public static func specimen(for font: CTFont) -> FontSpecimen {
        let family  = (CTFontCopyName(font, kCTFontFamilyNameKey)    as String?) ?? "Unknown"
        let style   = (CTFontCopyName(font, kCTFontStyleNameKey)     as String?) ?? ""
        let version = (CTFontCopyName(font, kCTFontVersionNameKey)   as String?) ?? ""
        let count   = Int(CTFontGetGlyphCount(font))

        let traits = CTFontGetSymbolicTraits(font)
        let isMonospaced   = traits.contains(.traitMonoSpace)
        let hasColorGlyphs = traits.contains(.traitColorGlyphs)

        // Variable fonts expose a kCTFontVariationAttribute dictionary.
        let isVariable = (CTFontCopyVariationAxes(font) as? [CFDictionary])?.isEmpty == false

        let ranges = unicodeRanges(for: font)
        let first = firstGlyphs(for: font, limit: 96)
        let pangram = "Le vif zéphyr jubile sur les kumquats des gorges de Patagonie."
        return FontSpecimen(
            family: family,
            style: style,
            version: version,
            glyphCount: count,
            isMonospaced: isMonospaced,
            hasColorGlyphs: hasColorGlyphs,
            isVariable: isVariable,
            unicodeRanges: ranges,
            pangram: pangram,
            firstGlyphs: first
        )
    }

    /// Report covered Unicode blocks from `CTFontCopyCharacterSet`.
    /// Limited to a handful of common ranges so the badge list stays
    /// readable.
    public static func unicodeRanges(for font: CTFont) -> [String] {
        let set = CTFontCopyCharacterSet(font) as CharacterSet
        let probes: [(label: String, range: ClosedRange<UInt32>)] = [
            ("Basic Latin",         0x0020...0x007E),
            ("Latin-1 Supplement",  0x00A0...0x00FF),
            ("Latin Extended",      0x0100...0x024F),
            ("Greek",               0x0370...0x03FF),
            ("Cyrillic",            0x0400...0x04FF),
            ("Hebrew",              0x0590...0x05FF),
            ("Arabic",              0x0600...0x06FF),
            ("Devanagari",          0x0900...0x097F),
            ("Hiragana",            0x3040...0x309F),
            ("Katakana",            0x30A0...0x30FF),
            ("Symbols",             0x2600...0x26FF),
            ("Dingbats",            0x2700...0x27BF),
            ("Emoji",               0x1F600...0x1F64F),
        ]
        return probes.compactMap { probe -> String? in
            for scalar in probe.range {
                if let u = Unicode.Scalar(scalar), set.contains(u) {
                    return probe.label
                }
            }
            return nil
        }
    }

    /// First N glyphs that the font actually maps. Pure helper, used
    /// by both the glyph grid and the specimen builder.
    public static func firstGlyphs(for font: CTFont, limit: Int = 96) -> [Character] {
        let set = CTFontCopyCharacterSet(font) as CharacterSet
        var out: [Character] = []
        for scalar in (0x20...0xFFFF) {
            guard let u = Unicode.Scalar(scalar), set.contains(u) else { continue }
            out.append(Character(u))
            if out.count == limit { break }
        }
        return out
    }
}

// MARK: - View

private struct FontRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var font: CTFont?
    @State private var specimen: FontSpecimen?
    @State private var loadError: String?

    var body: some View {
        HSplitView {
            leftPane
                .frame(minWidth: PreviewTokens.rendererMinWidth)
            inspectorPane
                .frame(minWidth: PreviewTokens.inspectorMinWidth,
                       idealWidth: PreviewTokens.inspectorIdealWidth)
        }
        .task(id: item.id) { await load() }
    }

    // MARK: - Left

    @ViewBuilder
    private var leftPane: some View {
        if let loadError {
            ContentUnavailableMessage(
                title: "Couldn't read font",
                subtitle: loadError,
                symbol: "exclamationmark.triangle"
            )
            .padding(24)
        } else if let font, let specimen {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 20) {
                    specimenRows(font: font)
                    Divider().opacity(0.3)
                    pangramRow(font: font, specimen: specimen)
                    Divider().opacity(0.3)
                    glyphGrid(font: font, specimen: specimen)
                }
                .padding(20)
            }
            .background(PreviewTokens.bgPrimary)
        } else {
            ProgressView("Loading font…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func specimenRows(font: CTFont) -> some View {
        let sizes: [CGFloat] = [12, 18, 24, 36, 48]
        let text = "Aa Bb Cc Dd Ee Ff Gg Hh 0123456789 .,:!?"
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(sizes, id: \.self) { s in
                Text(text)
                    .font(Font(CTFontCreateCopyWithAttributes(font, s, nil, nil)))
                    .foregroundStyle(PreviewTokens.textPrimary)
                    .lineLimit(1)
            }
        }
    }

    private func pangramRow(font: CTFont, specimen: FontSpecimen) -> some View {
        Text(specimen.pangram)
            .font(Font(CTFontCreateCopyWithAttributes(font, 22, nil, nil)))
            .foregroundStyle(PreviewTokens.textSecondary)
            .lineLimit(2)
            .padding(.vertical, 6)
    }

    private func glyphGrid(font: CTFont, specimen: FontSpecimen) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 8)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(Array(specimen.firstGlyphs.enumerated()), id: \.offset) { _, ch in
                Text(String(ch))
                    .font(Font(CTFontCreateCopyWithAttributes(font, 22, nil, nil)))
                    .foregroundStyle(PreviewTokens.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusSm)
                            .fill(PreviewTokens.bgSecondary)
                    )
            }
        }
    }

    // MARK: - Right

    private var inspectorPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                if let specimen {
                    KPITileRow(kpis(for: specimen), columns: 2)
                    if !badges(for: specimen).isEmpty {
                        SemanticBadgeRow(badges(for: specimen))
                    }
                    rangesBlock(for: specimen)
                } else {
                    KPITileRow([
                        .placeholder(label: "Family"),
                        .placeholder(label: "Style"),
                        .placeholder(label: "Glyphs"),
                        .placeholder(label: "Version"),
                    ], columns: 2)
                }
                CairnMetaBlock(meta: item.cairnMeta)
                Spacer(minLength: 6)
            }
            .padding(14)
        }
        .background(PreviewTokens.bgTertiary)
    }

    private func kpis(for s: FontSpecimen) -> [KPITile] {
        [
            KPITile(value: s.family,            label: "Family"),
            KPITile(value: s.style.isEmpty ? "Regular" : s.style, label: "Style"),
            KPITile(value: "\(s.glyphCount)",   label: "Glyphs"),
            KPITile(value: s.version.isEmpty ? "—" : s.version, label: "Version"),
        ]
    }

    private func badges(for s: FontSpecimen) -> [SemanticBadgeModel] {
        var out: [SemanticBadgeModel] = []
        if s.isVariable {
            out.append(.init(text: "Variable", style: .info, icon: "slider.horizontal.3"))
        }
        if s.hasColorGlyphs {
            out.append(.init(text: "Color", style: .info, icon: "paintpalette"))
        }
        if s.isMonospaced {
            out.append(.init(text: "Monospaced", style: .info, icon: "rectangle.split.3x1"))
        }
        return out
    }

    private func rangesBlock(for s: FontSpecimen) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("UNICODE RANGES")
                .font(PreviewTokens.fontLabel)
                .tracking(PreviewTokens.labelLetterSpacing)
                .foregroundStyle(PreviewTokens.textMuted)
            if s.unicodeRanges.isEmpty {
                Text("None detected")
                    .font(PreviewTokens.fontBody)
                    .foregroundStyle(PreviewTokens.textGhost)
            } else {
                FlowLayout(spacing: 6, runSpacing: 6) {
                    ForEach(s.unicodeRanges, id: \.self) { name in
                        Text(name)
                            .font(PreviewTokens.fontLabel)
                            .padding(.vertical, 2)
                            .padding(.horizontal, 7)
                            .background(
                                RoundedRectangle(cornerRadius: PreviewTokens.cornerRadiusSm)
                                    .fill(PreviewTokens.bgSecondary)
                            )
                    }
                }
            }
        }
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        font = nil
        specimen = nil
        loadError = nil

        let loaded: CTFont? = {
            if let data { return FontAnalyzer.loadCTFont(from: data) }
            if let url { return FontAnalyzer.loadCTFont(from: url) }
            return nil
        }()
        guard let loaded else {
            loadError = "Couldn't construct a CoreText font from the provided bytes."
            return
        }
        self.font = loaded
        self.specimen = FontAnalyzer.specimen(for: loaded)
    }
}
