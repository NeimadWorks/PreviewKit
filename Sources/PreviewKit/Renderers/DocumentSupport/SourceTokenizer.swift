// SourceTokenizer — single-pass, character-scan tokenizer. Produces an
// `AttributedString` directly so the renderer can drop it into `Text`
// with no intermediate allocation per token.
//
// Not a full parser. We tokenize enough to colour syntax categories
// (keyword / type / string / comment / number / operator / default) —
// not enough to build an AST. That's deliberate: a 1 000-line file
// colours in milliseconds, and we don't take on LSP-grade dependencies.

import SwiftUI
import Foundation

public enum SourceTokenizer {

    /// Tokenize `source` and produce an `AttributedString` with per-
    /// token foreground colours pulled from `PreviewTokens`. O(n).
    public static func colorize(_ source: String, language: SourceLanguage) -> AttributedString {
        var out = AttributedString("")
        var scanner = Scanner(source: source, language: language)
        while let token = scanner.next() {
            var piece = AttributedString(token.text)
            piece.foregroundColor = color(for: token.kind)
            if token.kind == .keyword || token.kind == .type {
                // Subtle weight bump for structure — keeps code
                // readable without shouting.
                piece.font = Font.system(.body, design: .monospaced).weight(.medium)
            } else {
                piece.font = Font.system(.body, design: .monospaced)
            }
            out.append(piece)
        }
        return out
    }

    /// Public helper for tests — tokenize into `(text, kind)` pairs.
    public static func tokens(in source: String, language: SourceLanguage) -> [Token] {
        var scanner = Scanner(source: source, language: language)
        var out: [Token] = []
        while let token = scanner.next() { out.append(token) }
        return out
    }

    public struct Token: Hashable, Sendable {
        public let text: String
        public let kind: Kind
    }

    public enum Kind: Hashable, Sendable {
        case keyword, type, string, comment, number, `operator`, identifier, whitespace, `default`
    }

    private static func color(for kind: Kind) -> Color {
        switch kind {
        case .keyword:    return PreviewTokens.syntaxKeyword
        case .type:       return PreviewTokens.syntaxType
        case .string:     return PreviewTokens.syntaxString
        case .comment:    return PreviewTokens.syntaxComment
        case .number:     return PreviewTokens.syntaxNumber
        case .operator:   return PreviewTokens.syntaxOperator
        case .identifier, .whitespace, .default:
            return PreviewTokens.syntaxDefault
        }
    }
}

// MARK: - Scanner

private struct Scanner {
    let source: String
    let language: SourceLanguage
    var index: String.Index

    init(source: String, language: SourceLanguage) {
        self.source = source
        self.language = language
        self.index = source.startIndex
    }

    mutating func next() -> SourceTokenizer.Token? {
        guard index < source.endIndex else { return nil }
        let ch = source[index]

        // Whitespace / newline run.
        if ch.isWhitespace {
            let start = index
            while index < source.endIndex, source[index].isWhitespace {
                index = source.index(after: index)
            }
            return .init(text: String(source[start..<index]), kind: .whitespace)
        }

        // Line comment.
        if let prefix = language.singleLineComment,
           source[index...].hasPrefix(prefix) {
            let start = index
            while index < source.endIndex, source[index] != "\n" {
                index = source.index(after: index)
            }
            return .init(text: String(source[start..<index]), kind: .comment)
        }

        // Block comment.
        if let (open, close) = language.multiLineComment,
           source[index...].hasPrefix(open) {
            let start = index
            index = source.index(index, offsetBy: open.count)
            while index < source.endIndex, !source[index...].hasPrefix(close) {
                index = source.index(after: index)
            }
            if index < source.endIndex {
                index = source.index(index, offsetBy: close.count, limitedBy: source.endIndex) ?? source.endIndex
            }
            return .init(text: String(source[start..<index]), kind: .comment)
        }

        // String literal. Single/double quotes, terminated by matching
        // quote or newline. Backslash escapes the next char.
        if language.stringDelimiters.contains(ch) {
            let quote = ch
            let start = index
            index = source.index(after: index)
            while index < source.endIndex, source[index] != quote, source[index] != "\n" {
                if source[index] == "\\",
                   source.index(after: index) < source.endIndex {
                    index = source.index(index, offsetBy: 2)
                } else {
                    index = source.index(after: index)
                }
            }
            if index < source.endIndex, source[index] == quote {
                index = source.index(after: index)
            }
            return .init(text: String(source[start..<index]), kind: .string)
        }

        // Number literal.
        if ch.isNumber {
            let start = index
            while index < source.endIndex,
                  (source[index].isNumber || source[index] == "." || source[index] == "_"
                   || "xXbBoOeE".contains(source[index]) || "abcdefABCDEF".contains(source[index])) {
                index = source.index(after: index)
            }
            return .init(text: String(source[start..<index]), kind: .number)
        }

        // Identifier / keyword / attribute-or-directive sigil.
        //
        // Sigil leaders (`@`, `#`) are not themselves word chars, so we
        // advance past them explicitly before the word-char run — otherwise
        // a bare sigil followed by whitespace (e.g. `<h1>#</h1>` in HTML,
        // standalone `@` in plain text) would leave `index == start` and
        // the scanner would loop forever. See regression test
        // `testBareSigilDoesNotHang`.
        if ch.isLetter || ch == "_" || ch == "$" || ch == "@" || ch == "#" {
            let start = index
            if ch == "@" || ch == "#" {
                index = source.index(after: index)
            }
            while index < source.endIndex,
                  (source[index].isLetter || source[index].isNumber
                   || source[index] == "_" || source[index] == "$") {
                index = source.index(after: index)
            }
            // If the sigil stood alone (no word chars followed), classify
            // it as an operator so callers still get a useful token.
            if index == start {
                index = source.index(after: index)
                return .init(text: String(source[start..<index]), kind: .operator)
            }
            let text = String(source[start..<index])
            if language.keywords.contains(text) {
                return .init(text: text, kind: .keyword)
            }
            if looksLikeTypeName(text) {
                return .init(text: text, kind: .type)
            }
            return .init(text: text, kind: .identifier)
        }

        // Operator / punctuation.
        let start = index
        index = source.index(after: index)
        return .init(text: String(source[start..<index]), kind: .operator)
    }

    private func looksLikeTypeName(_ s: String) -> Bool {
        // Heuristic: first char uppercase, length >= 2. Works for
        // Swift/Kotlin/C#/Java/Go (TypeCase is the convention). Doesn't
        // work well for C (`HWND` is a macro, not a type) but it's a
        // reasonable colour choice.
        guard s.count >= 2, let first = s.first else { return false }
        return first.isUppercase
    }
}
