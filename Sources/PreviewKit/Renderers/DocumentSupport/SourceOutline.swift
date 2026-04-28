// SourceOutline — structural outline extraction. Uses regex patterns
// per language to produce `OutlineEntry` values; keeps the coverage
// narrow on purpose (top-level declarations + methods). Not a parser.

import Foundation

public struct SourceSummary: Sendable, Hashable {
    public let lineCount: Int
    public let functionCount: Int
    public let typeCount: Int
    public let todoCount: Int
    public let importCount: Int
    public let importNames: [String]
    public let hasAsync: Bool
    public let hasMainActor: Bool
    public let hasTests: Bool

    public init(
        lineCount: Int,
        functionCount: Int,
        typeCount: Int,
        todoCount: Int,
        importCount: Int,
        importNames: [String],
        hasAsync: Bool,
        hasMainActor: Bool,
        hasTests: Bool
    ) {
        self.lineCount = lineCount
        self.functionCount = functionCount
        self.typeCount = typeCount
        self.todoCount = todoCount
        self.importCount = importCount
        self.importNames = importNames
        self.hasAsync = hasAsync
        self.hasMainActor = hasMainActor
        self.hasTests = hasTests
    }
}

public enum SourceOutline {

    public static func summarise(source: String, language: SourceLanguage) -> SourceSummary {
        let lines = source.count > 0 ? source.components(separatedBy: .newlines).count : 0
        let functions = countMatches(source, pattern: functionPattern(for: language))
        let types = countMatches(source, pattern: typePattern(for: language))
        let todos = countMatches(source, pattern: #"\b(TODO|FIXME|XXX|HACK)\b"#)
        let imports = extractImports(source: source, language: language)
        let hasAsync = source.range(of: #"\basync\b"#, options: .regularExpression) != nil
        let hasMain = source.range(of: #"@MainActor"#, options: .literal) != nil
        let hasTests = source.range(of: #"\bXCTest|@Test\b|\btest_"#, options: .regularExpression) != nil

        return SourceSummary(
            lineCount: lines,
            functionCount: functions,
            typeCount: types,
            todoCount: todos,
            importCount: imports.count,
            importNames: imports,
            hasAsync: hasAsync,
            hasMainActor: hasMain,
            hasTests: hasTests
        )
    }

    public static func extractOutline(source: String, language: SourceLanguage) -> [OutlineEntry] {
        switch language {
        case .swift:       return swiftOutline(source: source)
        case .javascript, .typescript: return jsOutline(source: source)
        case .python:      return pythonOutline(source: source)
        case .rust:        return rustOutline(source: source)
        case .go:          return goOutline(source: source)
        case .java, .kotlin: return jvmOutline(source: source)
        case .c, .cpp:     return cOutline(source: source)
        default:           return []
        }
    }

    public static func extractImports(source: String, language: SourceLanguage) -> [String] {
        let pattern: String
        switch language {
        case .swift, .kotlin:
            pattern = #"^\s*import\s+([A-Za-z0-9_.]+)"#
        case .javascript, .typescript:
            pattern = #"^\s*import\s+.*from\s+['\"]([^'\"]+)['\"]"#
        case .python:
            pattern = #"^\s*(?:from\s+([A-Za-z0-9_.]+)\s+)?import\s+([A-Za-z0-9_.,\s]+)"#
        case .rust:
            pattern = #"^\s*use\s+([A-Za-z0-9_:]+)"#
        case .go:
            pattern = #"^\s*import\s+(?:\(([^)]*)\)|\"([^\"]+)\")"#
        case .java:
            pattern = #"^\s*import\s+([A-Za-z0-9_.]+)"#
        case .c, .cpp:
            pattern = #"^\s*#include\s+[<\"]([^>\"]+)[>\"]"#
        default:
            return []
        }
        return regexFindAll(source, pattern: pattern, anchored: true)
            .compactMap { $0.first }
            .filter { !$0.isEmpty }
    }

    // MARK: - Language-specific outline

    private static func swiftOutline(source: String) -> [OutlineEntry] {
        let typePattern = #"^\s*(?:public|private|internal|fileprivate|open|final)?\s*(?:@[\w.]+\s+)*(struct|class|enum|actor|protocol|extension)\s+([A-Za-z_][A-Za-z0-9_<>, ]*)"#
        let funcPattern = #"^\s*(?:public|private|internal|fileprivate|open|final|static|class|override|mutating)?\s*func\s+([A-Za-z_][A-Za-z0-9_]*)"#
        var entries: [OutlineEntry] = []
        entries.append(contentsOf: matchEntries(
            source: source, pattern: typePattern, kind: .type, depth: 0,
            titleIndex: 2, subtitlePrefix: "\\1"))
        entries.append(contentsOf: matchEntries(
            source: source, pattern: funcPattern, kind: .function, depth: 0,
            titleIndex: 1, subtitlePrefix: "func"))
        return assignWeights(entries, source: source)
    }

    private static func jsOutline(source: String) -> [OutlineEntry] {
        let typePattern = #"^\s*(?:export\s+)?(?:default\s+)?(class|interface|type|enum)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        let funcPattern = #"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_][A-Za-z0-9_]*)"#
        var entries: [OutlineEntry] = []
        entries.append(contentsOf: matchEntries(
            source: source, pattern: typePattern, kind: .type, depth: 0,
            titleIndex: 2, subtitlePrefix: "\\1"))
        entries.append(contentsOf: matchEntries(
            source: source, pattern: funcPattern, kind: .function, depth: 0,
            titleIndex: 1, subtitlePrefix: "function"))
        return assignWeights(entries, source: source)
    }

    private static func pythonOutline(source: String) -> [OutlineEntry] {
        let classPattern = #"^(?:class)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        let funcPattern  = #"^(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)"#
        var entries: [OutlineEntry] = []
        entries.append(contentsOf: matchEntries(
            source: source, pattern: classPattern, kind: .type, depth: 0,
            titleIndex: 1, subtitlePrefix: "class"))
        entries.append(contentsOf: matchEntries(
            source: source, pattern: funcPattern, kind: .function, depth: 0,
            titleIndex: 1, subtitlePrefix: "def"))
        return assignWeights(entries, source: source)
    }

    private static func rustOutline(source: String) -> [OutlineEntry] {
        let typePattern = #"^\s*(?:pub\s+)?(fn|struct|enum|trait|impl|mod)\s+([A-Za-z_][A-Za-z0-9_<>, ]*)"#
        return assignWeights(
            matchEntries(source: source, pattern: typePattern,
                         kind: .type, depth: 0,
                         titleIndex: 2, subtitlePrefix: "\\1"),
            source: source
        )
    }

    private static func goOutline(source: String) -> [OutlineEntry] {
        let funcPattern = #"^\s*func\s+(?:\([^)]+\)\s+)?([A-Za-z_][A-Za-z0-9_]*)"#
        let typePattern = #"^\s*type\s+([A-Za-z_][A-Za-z0-9_]*)\s+(struct|interface)"#
        var entries: [OutlineEntry] = []
        entries.append(contentsOf: matchEntries(
            source: source, pattern: typePattern, kind: .type, depth: 0,
            titleIndex: 1, subtitlePrefix: "\\2"))
        entries.append(contentsOf: matchEntries(
            source: source, pattern: funcPattern, kind: .function, depth: 0,
            titleIndex: 1, subtitlePrefix: "func"))
        return assignWeights(entries, source: source)
    }

    private static func jvmOutline(source: String) -> [OutlineEntry] {
        let typePattern = #"^\s*(?:public|private|protected|internal|open|abstract|final|sealed|data|enum)?\s*(class|interface|object|enum)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        let funcPattern = #"^\s*(?:public|private|protected|internal|override|fun|suspend)?\s*fun\s+([A-Za-z_][A-Za-z0-9_]*)"#
        var entries: [OutlineEntry] = []
        entries.append(contentsOf: matchEntries(
            source: source, pattern: typePattern, kind: .type, depth: 0,
            titleIndex: 2, subtitlePrefix: "\\1"))
        entries.append(contentsOf: matchEntries(
            source: source, pattern: funcPattern, kind: .function, depth: 0,
            titleIndex: 1, subtitlePrefix: "fun"))
        return assignWeights(entries, source: source)
    }

    private static func cOutline(source: String) -> [OutlineEntry] {
        let structPattern = #"^\s*(?:typedef\s+)?(struct|union|enum|class)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        return assignWeights(
            matchEntries(source: source, pattern: structPattern,
                         kind: .type, depth: 0,
                         titleIndex: 2, subtitlePrefix: "\\1"),
            source: source
        )
    }

    // MARK: - Match helpers

    private struct EntryPosition { let offset: Int; let entry: OutlineEntry }

    private static func matchEntries(
        source: String,
        pattern: String,
        kind: OutlineKind,
        depth: Int,
        titleIndex: Int,
        subtitlePrefix: String
    ) -> [OutlineEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.anchorsMatchLines]
        ) else { return [] }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var positions: [EntryPosition] = []
        regex.enumerateMatches(in: source, options: [], range: range) { match, _, _ in
            guard let match else { return }
            guard titleIndex < match.numberOfRanges,
                  let titleRange = Range(match.range(at: titleIndex), in: source)
            else { return }
            let title = String(source[titleRange]).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return }
            let subtitle = resolveSubtitle(prefix: subtitlePrefix, match: match, source: source)
            let entry = OutlineEntry(
                title: title,
                subtitle: subtitle,
                depth: depth,
                weightFraction: 0,
                children: [],
                kind: kind
            )
            let offset = match.range.location
            positions.append(EntryPosition(offset: offset, entry: entry))
        }
        return positions.sorted { $0.offset < $1.offset }.map(\.entry)
    }

    private static func resolveSubtitle(prefix: String, match: NSTextCheckingResult, source: String) -> String {
        if prefix.hasPrefix("\\") {
            let idxString = prefix.dropFirst()
            if let idx = Int(idxString), idx < match.numberOfRanges,
               let range = Range(match.range(at: idx), in: source) {
                return String(source[range])
            }
        }
        return prefix
    }

    private static func assignWeights(_ entries: [OutlineEntry], source: String) -> [OutlineEntry] {
        guard !entries.isEmpty else { return entries }
        let total = max(1, source.count)
        let each = min(0.25, 1.0 / Double(entries.count))
        return entries.map {
            OutlineEntry(
                id: $0.id,
                title: $0.title,
                subtitle: $0.subtitle,
                depth: $0.depth,
                weightFraction: each + Double($0.title.count) / Double(total) * 0.1,
                children: $0.children,
                kind: $0.kind
            )
        }
    }

    private static func countMatches(_ source: String, pattern: String,
                                     options: NSRegularExpression.Options = [.anchorsMatchLines]) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return 0
        }
        return regex.numberOfMatches(in: source,
                                     options: [],
                                     range: NSRange(source.startIndex..<source.endIndex, in: source))
    }

    private static func regexFindAll(_ source: String, pattern: String, anchored: Bool) -> [[String]] {
        let options: NSRegularExpression.Options = anchored ? [.anchorsMatchLines] : []
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else {
            return []
        }
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        var out: [[String]] = []
        regex.enumerateMatches(in: source, options: [], range: range) { match, _, _ in
            guard let match else { return }
            var groups: [String] = []
            for i in 1..<match.numberOfRanges {
                if let r = Range(match.range(at: i), in: source) {
                    groups.append(String(source[r]))
                } else {
                    groups.append("")
                }
            }
            out.append(groups)
        }
        return out
    }

    private static func functionPattern(for language: SourceLanguage) -> String {
        switch language {
        case .swift:       return #"\bfunc\s+[A-Za-z_]"#
        case .javascript, .typescript: return #"\bfunction\s+[A-Za-z_]|=>\s*\{"#
        case .python:      return #"\bdef\s+[A-Za-z_]"#
        case .rust:        return #"\bfn\s+[A-Za-z_]"#
        case .go:          return #"\bfunc\s+[A-Za-z_]"#
        case .kotlin:      return #"\bfun\s+[A-Za-z_]"#
        case .java:        return #"\b(?:public|private|protected|static|final)\s+[\w<>\[\]]+\s+[A-Za-z_]\w*\s*\("#
        case .ruby:        return #"\bdef\s+[A-Za-z_]"#
        case .c, .cpp:     return #"\b[\w\*]+\s+[A-Za-z_]\w*\s*\("#
        case .shell:       return #"^\w+\s*\(\s*\)"#
        default:           return #"$^"#
        }
    }

    private static func typePattern(for language: SourceLanguage) -> String {
        switch language {
        case .swift:       return #"\b(?:struct|class|enum|actor|protocol|extension)\s+[A-Za-z_]"#
        case .javascript, .typescript: return #"\b(?:class|interface|type|enum)\s+[A-Za-z_]"#
        case .python:      return #"\bclass\s+[A-Za-z_]"#
        case .rust:        return #"\b(?:struct|enum|trait|impl|mod)\s+[A-Za-z_]"#
        case .go:          return #"\btype\s+[A-Za-z_]"#
        case .kotlin:      return #"\b(?:class|interface|object|enum)\s+[A-Za-z_]"#
        case .java:        return #"\b(?:class|interface|enum|record)\s+[A-Za-z_]"#
        case .c, .cpp:     return #"\b(?:struct|union|enum|class)\s+[A-Za-z_]"#
        default:           return #"$^"#
        }
    }
}
