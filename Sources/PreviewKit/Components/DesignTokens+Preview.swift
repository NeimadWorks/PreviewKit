// DesignTokens+Preview — layout / colour / typography vocabulary.
//
// Every colour resolves through `Color(nsColor:)` or `Color.primary` /
// `Color.secondary` so the palette adapts to both appearances without
// custom assets. The single hard-coded hue is `accentOrange`, which
// matches the existing CairnTokens accent in the Vitals view.
//
// No hex literals leak into renderers; renderers import these tokens and
// compose them. Adding a semantic colour is a one-line change here.

import SwiftUI
import AppKit

public enum PreviewTokens {

    // MARK: - Layout

    public static let navigatorMinWidth:     CGFloat = 200
    public static let navigatorDefaultWidth: CGFloat = 240
    public static let navigatorMaxWidth:     CGFloat = 360

    public static let inspectorMinWidth:   CGFloat = 320
    public static let inspectorIdealWidth: CGFloat = 420

    public static let rendererMinWidth:   CGFloat = 420

    public static let filmstripHeight: CGFloat = 48
    public static let kpiTileMinWidth: CGFloat = 72
    public static let kpiRowGap:       CGFloat = 8

    public static let rowPadding:     CGFloat = 8
    public static let sectionGap:     CGFloat = 16
    public static let cardPadding:    CGFloat = 14

    public static let cornerRadiusSm: CGFloat = 4
    public static let cornerRadiusMd: CGFloat = 6
    public static let cornerRadiusLg: CGFloat = 8

    public static let borderWidth:       CGFloat = 0.5
    public static let selectionBarWidth: CGFloat = 2

    // MARK: - Timing

    public static let hoverPreviewDelay:     Double = 0.4
    public static let loadingDebounce:       Double = 0.2
    public static let foldAnimationDuration: Double = 0.2

    // MARK: - TOC / Outline

    public static let outlineCompactMaxItems:   Int     = 7
    public static let outlineScrollHeight:      CGFloat = 200
    public static let outlineIndentStep:        CGFloat = 10
    public static let outlineWeightBarMaxWidth: CGFloat = 24
    public static let outlineWeightBarHeight:   CGFloat = 3
    public static let outlineRowHeight:         CGFloat = 22

    // MARK: - Backgrounds

    public static let bgPrimary   = Color(nsColor: .textBackgroundColor)
    public static let bgSecondary = Color(nsColor: .controlBackgroundColor)
    public static let bgTertiary  = Color(nsColor: .windowBackgroundColor)
    public static let bgHover     = Color.primary.opacity(0.06)
    public static let bgSelected  = Color.accentColor.opacity(0.18)

    // MARK: - Borders / dividers

    public static let borderFaint    = Color.secondary.opacity(0.12)
    public static let borderSubtle   = Color.secondary.opacity(0.22)
    public static let borderEmphasis = Color.secondary.opacity(0.35)

    // MARK: - Text

    public static let textPrimary   = Color.primary
    public static let textSecondary = Color.primary.opacity(0.85)
    public static let textMuted     = Color.secondary
    public static let textFaint     = Color.secondary.opacity(0.7)
    public static let textGhost     = Color.secondary.opacity(0.5)

    // MARK: - Typography

    public static let fontLabel     = Font.caption2.weight(.medium)
    public static let fontBody      = Font.caption
    public static let fontBodyLarge = Font.footnote
    public static let fontValue     = Font.footnote.weight(.medium)
    public static let fontHeader    = Font.headline
    public static let fontKPIValue  = Font.title3.weight(.semibold)
    public static let fontMono      = Font.system(.caption, design: .monospaced)
    public static let fontMonoLarge = Font.system(.footnote, design: .monospaced)
    public static let fontMonoBody  = Font.system(.body, design: .monospaced)

    public static let labelLetterSpacing: CGFloat = 0.8

    // MARK: - Accent (brand)

    public static let accentOrange       = Color(hex: 0xFF7A1A)
    public static let accentOrangeTint   = Color(hex: 0xFF7A1A).opacity(0.10)
    public static let accentOrangeBorder = Color(hex: 0xFF7A1A).opacity(0.35)

    /// Cairn identity teal — only used in `CompressionRing`'s outer band
    /// to distinguish "Cairn ratio" from a nested archive's own ratio.
    public static let cairnTeal = Color(hex: 0x1FA39A)

    // MARK: - Semantic (badges, tile dots)

    public static func semanticFill(_ style: BadgeStyle) -> Color {
        switch style {
        case .success: return Color.green.opacity(0.18)
        case .warning: return Color.orange.opacity(0.22)
        case .danger:  return Color.red.opacity(0.22)
        case .info:    return Color.blue.opacity(0.18)
        case .neutral: return Color.secondary.opacity(0.16)
        }
    }

    public static func semanticText(_ style: BadgeStyle) -> Color {
        switch style {
        case .success: return Color.green
        case .warning: return Color.orange
        case .danger:  return Color.red
        case .info:    return Color.blue
        case .neutral: return Color.secondary
        }
    }

    // MARK: - Syntax highlight (dark-mode aware)
    //
    // Values are chosen to have reasonable contrast in both appearances
    // without being garish. Renderers pick by token category, never by
    // language — language-specific nuance lives in the tokenizer.

    public static let syntaxKeyword  = Color(nsColor: .systemPink)
    public static let syntaxType     = Color(nsColor: .systemTeal)
    public static let syntaxString   = Color(nsColor: .systemOrange)
    public static let syntaxComment  = Color.secondary.opacity(0.75)
    public static let syntaxNumber   = Color(nsColor: .systemBlue)
    public static let syntaxOperator = Color(nsColor: .systemIndigo)
    public static let syntaxDefault  = Color.primary

    // MARK: - MIME bar palette

    public static let mimeCode     = Color(nsColor: .systemBlue)
    public static let mimeImage    = Color(nsColor: .systemTeal)
    public static let mimeDocument = Color(nsColor: .systemOrange)
    public static let mimeMedia    = Color(nsColor: .systemPurple)
    public static let mimeData     = Color(nsColor: .systemIndigo)
    public static let mimeOther    = Color.secondary.opacity(0.5)

    public static func mimeColor(for family: ArtifactKind.Family) -> Color {
        switch family {
        case .code:      return mimeCode
        case .images:    return mimeImage
        case .documents: return mimeDocument
        case .media:     return mimeMedia
        case .data:      return mimeData
        case .design:    return Color(nsColor: .systemBrown)
        case .system:    return mimeOther
        }
    }

    // MARK: - Outline kind → accent

    public static func outlineKindColor(_ kind: OutlineKind) -> Color {
        switch kind {
        case .heading, .chapter, .section, .page:   return Color(nsColor: .systemBlue)
        case .function:                             return Color(nsColor: .systemOrange)
        case .type:                                 return Color(nsColor: .systemTeal)
        case .protocol:                             return Color(nsColor: .systemGreen)
        case .extension:                            return Color.secondary
        case .property:                             return Color(nsColor: .systemPurple)
        case .slide:                                return Color(nsColor: .systemIndigo)
        case .sheet:                                return Color(nsColor: .systemMint)
        case .table:                                return Color(nsColor: .systemBrown)
        case .generic:                              return Color.secondary.opacity(0.6)
        }
    }
}

// MARK: - Color(hex:) helper (internal to PreviewKit)
//
// Kept internal so it doesn't collide with the identically-named helper
// in CairnApp's `CairnTokens`. External consumers compose tokens from
// `PreviewTokens` symbolically and never see hex integers.

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red:    Double((hex >> 16) & 0xFF) / 255,
            green:  Double((hex >>  8) & 0xFF) / 255,
            blue:   Double( hex        & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// String-form `Color(hex: "#RRGGBB")` overload, used by registry
    /// entries that store colors as text. Falls back to `.gray` on
    /// malformed input rather than trapping.
    init(hex: String, opacity: Double = 1) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let n = UInt32(s, radix: 16) else {
            self = .gray
            return
        }
        self.init(hex: n, opacity: opacity)
    }
}
