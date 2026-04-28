// ArtifactKind — the type taxonomy PreviewKit dispatches on.
//
// A small enum intentionally — the registry looks up a renderer per
// `ArtifactKind` value, and groups of related formats share a single
// kind (e.g. every RAW flavour collapses to `.raw`, every Mach-O
// flavour to `.machO`). The set is frozen for v1 of PreviewKit; adding
// a new kind is a semver bump.

import Foundation

public enum ArtifactKind: String, Sendable, CaseIterable, Hashable {

    // MARK: Documents
    case pdf, markdown, docx, xlsx, pptx, pages, numbers, keynote, rtf, txt

    // MARK: Images
    case jpeg, png, heic, webp, tiff, gif, bmp, svg
    /// Unified entry for every RAW flavour (DNG, CR3, ARW, RAF, NEF, ORF…).
    case raw

    // MARK: Media
    /// MP4, MOV, ProRes, MKV.
    case video
    /// FLAC, MP3, WAV, AIFF, AAC, OPUS.
    case audio

    // MARK: Source code
    case sourceSwift, sourceJS, sourceTS, sourcePython, sourceRust,
         sourceGo, sourceC, sourceCpp, sourceRuby, sourceKotlin, sourceJava,
         sourceShell, sourceHTML, sourceCSS

    // MARK: Structured data
    case json, yaml, toml, xml, plist, csv, tsv, sqlite

    // MARK: Other
    case font
    case archive
    case machO
    case binary

    // MARK: Addendum v2 — dispatch kinds for specialised renderers.
    // Adding a case here is a semver bump; ArtifactKind is part of the
    // stable public surface. See docs addendum v2 for coverage map.
    case icns
    case patch
    case mobileProvision
    case gpgSignature
    case gpgMessage

    // MARK: Group nodes (navigator-only — never rendered as a leaf)
    /// Cairn Collection — a recognizer-produced grouping of related
    /// artifacts (a photo burst, a source module, a document set).
    case collection
    /// Generic filesystem folder.
    case folder

    // MARK: - Factories

    /// Infer a kind from a file URL. Uses extension first (cheap, almost
    /// always correct), then — only when the caller explicitly asks — the
    /// magic-bytes path via `infer(fromMagicBytes:)`.
    public static func infer(from url: URL) -> ArtifactKind {
        infer(fromExtension: url.pathExtension)
    }

    /// Lowercase-normalised extension lookup. Unknown extensions fall
    /// through to `.binary`.
    public static func infer(fromExtension ext: String) -> ArtifactKind {
        switch ext.lowercased() {

        // Documents
        case "pdf":                 return .pdf
        case "md", "markdown":      return .markdown
        case "docx":                return .docx
        case "xlsx":                return .xlsx
        case "pptx":                return .pptx
        case "pages":               return .pages
        case "numbers":             return .numbers
        case "key", "keynote":      return .keynote
        case "rtf":                 return .rtf
        case "txt", "text", "log":  return .txt

        // Images
        case "jpg", "jpeg":         return .jpeg
        case "png":                 return .png
        case "heic", "heif":        return .heic
        case "webp":                return .webp
        case "tif", "tiff":         return .tiff
        case "gif":                 return .gif
        case "bmp":                 return .bmp
        case "svg":                 return .svg
        case "dng", "cr2", "cr3", "arw", "raf", "nef", "orf",
             "rw2", "raw", "srw", "pef", "x3f":
            return .raw

        // Media
        case "mp4", "mov", "m4v", "mkv", "webm", "prores":
            return .video
        case "mp3", "m4a", "aac", "flac", "wav", "aif", "aiff",
             "ogg", "opus":
            return .audio

        // Code
        case "swift":                        return .sourceSwift
        case "js", "mjs", "cjs", "jsx":      return .sourceJS
        case "ts", "tsx":                    return .sourceTS
        case "py":                           return .sourcePython
        case "rs":                           return .sourceRust
        case "go":                           return .sourceGo
        case "c", "h":                       return .sourceC
        case "cc", "cpp", "cxx", "hpp", "hh": return .sourceCpp
        case "rb":                           return .sourceRuby
        case "kt", "kts":                    return .sourceKotlin
        case "java":                         return .sourceJava
        case "sh", "bash", "zsh", "fish":    return .sourceShell
        case "html", "htm":                  return .sourceHTML
        case "css", "scss", "sass", "less":  return .sourceCSS

        // Data
        case "json":                return .json
        case "yaml", "yml":         return .yaml
        case "toml":                return .toml
        case "xml":                 return .xml
        case "plist":               return .plist
        case "csv":                 return .csv
        case "tsv":                 return .tsv
        case "sqlite", "sqlite3", "db":
                                    return .sqlite

        // Fonts
        case "ttf", "otf", "ttc", "woff", "woff2":
            return .font

        // Archives
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar":
            return .archive

        // Binary
        case "dylib", "so", "a", "bundle":
            return .machO

        // Addendum v2 — specialised dispatch.
        case "icns":                                return .icns
        case "patch", "diff":                       return .patch
        case "mobileprovision", "provisionprofile": return .mobileProvision
        case "sig", "pgp":                          return .gpgSignature
        case "asc":                                 return .gpgSignature
        case "gpg":                                 return .gpgMessage

        default:
            return .binary
        }
    }

    /// Magic-bytes sniff — only invoked when the caller wants certainty
    /// that an extension can't provide (e.g., untrusted input). Falls
    /// through to `.binary` when nothing matches.
    public static func infer(fromMagicBytes bytes: Data) -> ArtifactKind {
        guard bytes.count >= 4 else { return .binary }
        let b = [UInt8](bytes.prefix(16))

        // PDF
        if b.starts(with: [0x25, 0x50, 0x44, 0x46]) { return .pdf }        // %PDF
        // PNG
        if b.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png }
        // JPEG
        if b.starts(with: [0xFF, 0xD8, 0xFF])       { return .jpeg }
        // GIF
        if b.starts(with: [0x47, 0x49, 0x46, 0x38]) { return .gif }
        // HEIC (ftypheic / ftypheix / ftypmif1) — check bytes 4..12
        if bytes.count >= 12 {
            let ftyp = Array(bytes[4..<8])
            if ftyp == [0x66, 0x74, 0x79, 0x70] { // "ftyp"
                let brand = Array(bytes[8..<12])
                let asString = String(decoding: brand, as: UTF8.self)
                if asString == "heic" || asString == "heix" || asString == "mif1" {
                    return .heic
                }
                if asString == "isom" || asString == "mp42" || asString == "qt  " {
                    return .video
                }
            }
        }
        // ZIP / OOXML (OOXML is itself a zip — extension wins)
        if b.starts(with: [0x50, 0x4B, 0x03, 0x04])
            || b.starts(with: [0x50, 0x4B, 0x05, 0x06])
            || b.starts(with: [0x50, 0x4B, 0x07, 0x08]) {
            return .archive
        }
        // Mach-O (32/64/fat, LE/BE)
        let m: UInt32 = bytes.withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self)
        }
        if m == 0xFEEDFACE || m == 0xCEFAEDFE
            || m == 0xFEEDFACF || m == 0xCFFAEDFE
            || m == 0xCAFEBABE || m == 0xBEBAFECA {
            return .machO
        }
        // SQLite ("SQLite format 3\0", 16 bytes)
        if bytes.count >= 16 {
            let magic: [UInt8] = [
                0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66,
                0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00
            ]
            if Array(bytes[0..<16]) == magic { return .sqlite }
        }
        return .binary
    }

    // MARK: - Classification helpers

    /// Group/folder nodes that must never be rendered as a leaf.
    public var isGroup: Bool {
        switch self {
        case .collection, .folder: return true
        default: return false
        }
    }

    /// High-level family used by the overview grid and MIME bar.
    public var family: Family {
        switch self {
        case .pdf, .markdown, .docx, .xlsx, .pptx, .pages, .numbers, .keynote,
             .rtf, .txt:
            return .documents
        case .jpeg, .png, .heic, .webp, .tiff, .gif, .bmp, .svg, .raw:
            return .images
        case .video, .audio:
            return .media
        case .sourceSwift, .sourceJS, .sourceTS, .sourcePython, .sourceRust,
             .sourceGo, .sourceC, .sourceCpp, .sourceRuby, .sourceKotlin,
             .sourceJava, .sourceShell, .sourceHTML, .sourceCSS:
            return .code
        case .json, .yaml, .toml, .xml, .plist, .csv, .tsv, .sqlite:
            return .data
        case .font:
            return .design
        case .archive:
            return .data
        case .machO, .binary:
            return .system
        case .icns:
            return .images
        case .patch:
            return .code
        case .mobileProvision, .gpgSignature, .gpgMessage:
            return .system
        case .collection, .folder:
            return .data   // groups render in the Overview as a "data" family
        }
    }

    /// Display label for context-menu / accessibility text.
    public var displayLabel: String {
        switch self {
        case .sourceSwift:   return "Swift"
        case .sourceJS:      return "JavaScript"
        case .sourceTS:      return "TypeScript"
        case .sourcePython:  return "Python"
        case .sourceRust:    return "Rust"
        case .sourceGo:      return "Go"
        case .sourceC:       return "C"
        case .sourceCpp:     return "C++"
        case .sourceRuby:    return "Ruby"
        case .sourceKotlin:  return "Kotlin"
        case .sourceJava:    return "Java"
        case .sourceShell:   return "Shell"
        case .sourceHTML:    return "HTML"
        case .sourceCSS:     return "CSS"
        case .machO:            return "Mach-O"
        case .icns:             return "Apple Icon"
        case .patch:            return "Patch"
        case .mobileProvision:  return "Provisioning Profile"
        case .gpgSignature:     return "PGP Signature"
        case .gpgMessage:       return "PGP Message"
        default:             return rawValue.capitalized
        }
    }

    /// SF Symbol used in the navigator row and overview grid. Chosen for
    /// availability on macOS 14+ (no 15-only symbols).
    public var symbolName: String {
        switch self {
        case .pdf:              return "doc.richtext"
        case .markdown:         return "text.alignleft"
        case .docx, .pages, .rtf, .txt:
                                return "doc.text"
        case .xlsx, .numbers, .csv, .tsv:
                                return "tablecells"
        case .pptx, .keynote:   return "rectangle.on.rectangle"

        case .jpeg, .png, .heic, .webp, .tiff, .gif, .bmp:
                                return "photo"
        case .svg:              return "scribble"
        case .raw:              return "camera.aperture"

        case .video:            return "film"
        case .audio:            return "waveform"

        case .sourceSwift:      return "swift"
        case .sourceJS, .sourceTS, .sourcePython, .sourceRust, .sourceGo,
             .sourceC, .sourceCpp, .sourceRuby, .sourceKotlin, .sourceJava:
            return "chevron.left.forwardslash.chevron.right"
        case .sourceShell:      return "terminal"
        case .sourceHTML, .sourceCSS:
                                return "curlybraces"

        case .json, .yaml, .toml, .xml, .plist:
                                return "curlybraces.square"
        case .sqlite:           return "cylinder.split.1x2"

        case .font:             return "textformat"
        case .archive:          return "archivebox"
        case .machO:            return "cpu"
        case .binary:           return "doc.on.clipboard"

        case .icns:             return "app.gift"
        case .patch:            return "plusminus.circle"
        case .mobileProvision:  return "lock.shield"
        case .gpgSignature:     return "signature"
        case .gpgMessage:       return "lock.doc"

        case .collection:       return "square.grid.2x2"
        case .folder:           return "folder"
        }
    }

    /// Coarse-grained family used for grouping in the overview grid.
    public enum Family: String, Sendable, CaseIterable, Hashable {
        case documents
        case images
        case media
        case code
        case data
        case design
        case system

        public var displayLabel: String {
            switch self {
            case .documents: return "Documents & Writing"
            case .images:    return "Photo & Images"
            case .media:     return "Media"
            case .code:      return "Code & Dev"
            case .data:      return "Data & Archives"
            case .design:    return "Design & Creative"
            case .system:    return "System & Binary"
            }
        }

        public var symbolName: String {
            switch self {
            case .documents: return "doc.richtext"
            case .images:    return "photo.on.rectangle.angled"
            case .media:     return "play.rectangle"
            case .code:      return "chevron.left.forwardslash.chevron.right"
            case .data:      return "externaldrive"
            case .design:    return "paintpalette"
            case .system:    return "cpu"
            }
        }
    }
}
