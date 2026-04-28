// SourceLanguage — keyword sets, comment syntax, and structural-outline
// patterns for every source kind we tokenize. Kept in one file so a
// new language is a ~15-line addition, not a refactor.

import Foundation

public enum SourceLanguage: String, Sendable, CaseIterable, Hashable {
    case swift, javascript, typescript, python, rust, go,
         c, cpp, ruby, kotlin, java, shell, html, css, unknown

    public init(kind: ArtifactKind) {
        switch kind {
        case .sourceSwift:   self = .swift
        case .sourceJS:      self = .javascript
        case .sourceTS:      self = .typescript
        case .sourcePython:  self = .python
        case .sourceRust:    self = .rust
        case .sourceGo:      self = .go
        case .sourceC:       self = .c
        case .sourceCpp:     self = .cpp
        case .sourceRuby:    self = .ruby
        case .sourceKotlin:  self = .kotlin
        case .sourceJava:    self = .java
        case .sourceShell:   self = .shell
        case .sourceHTML:    self = .html
        case .sourceCSS:     self = .css
        default:             self = .unknown
        }
    }

    public var displayName: String {
        switch self {
        case .swift:      return "Swift"
        case .javascript: return "JavaScript"
        case .typescript: return "TypeScript"
        case .python:     return "Python"
        case .rust:       return "Rust"
        case .go:         return "Go"
        case .c:          return "C"
        case .cpp:        return "C++"
        case .ruby:       return "Ruby"
        case .kotlin:     return "Kotlin"
        case .java:       return "Java"
        case .shell:      return "Shell"
        case .html:       return "HTML"
        case .css:        return "CSS"
        case .unknown:    return "Plain text"
        }
    }

    // MARK: - Keywords

    public var keywords: Set<String> {
        switch self {
        case .swift:
            return [
                "actor", "any", "as", "async", "await", "break", "case", "catch",
                "class", "continue", "default", "defer", "deinit", "do", "else",
                "enum", "extension", "fallthrough", "false", "fileprivate", "for",
                "func", "get", "guard", "if", "import", "in", "init", "inout",
                "internal", "is", "let", "mutating", "nil", "open", "operator",
                "override", "private", "protocol", "public", "repeat", "required",
                "return", "self", "set", "static", "struct", "subscript", "super",
                "switch", "throw", "throws", "true", "try", "typealias", "var",
                "where", "while", "Self", "Type",
            ]
        case .javascript, .typescript:
            var base: Set<String> = [
                "async", "await", "break", "case", "catch", "class", "const",
                "continue", "debugger", "default", "delete", "do", "else", "enum",
                "export", "extends", "false", "finally", "for", "function", "if",
                "import", "in", "instanceof", "let", "new", "null", "of", "return",
                "static", "super", "switch", "this", "throw", "true", "try",
                "typeof", "undefined", "var", "void", "while", "with", "yield",
            ]
            if self == .typescript {
                base.formUnion([
                    "any", "as", "boolean", "declare", "interface", "is",
                    "keyof", "namespace", "never", "number", "readonly",
                    "string", "symbol", "type", "unknown", "override",
                ])
            }
            return base
        case .python:
            return [
                "and", "as", "assert", "async", "await", "break", "class",
                "continue", "def", "del", "elif", "else", "except", "False",
                "finally", "for", "from", "global", "if", "import", "in", "is",
                "lambda", "None", "nonlocal", "not", "or", "pass", "raise",
                "return", "True", "try", "while", "with", "yield", "match", "case",
            ]
        case .rust:
            return [
                "as", "async", "await", "break", "const", "continue", "crate",
                "dyn", "else", "enum", "extern", "false", "fn", "for", "if",
                "impl", "in", "let", "loop", "match", "mod", "move", "mut",
                "pub", "ref", "return", "self", "Self", "static", "struct",
                "super", "trait", "true", "type", "unsafe", "use", "where",
                "while",
            ]
        case .go:
            return [
                "break", "case", "chan", "const", "continue", "default", "defer",
                "else", "fallthrough", "for", "func", "go", "goto", "if",
                "import", "interface", "map", "package", "range", "return",
                "select", "struct", "switch", "type", "var",
            ]
        case .c:
            return [
                "auto", "break", "case", "char", "const", "continue", "default",
                "do", "double", "else", "enum", "extern", "float", "for", "goto",
                "if", "int", "long", "register", "return", "short", "signed",
                "sizeof", "static", "struct", "switch", "typedef", "union",
                "unsigned", "void", "volatile", "while",
            ]
        case .cpp:
            return [
                "alignas", "alignof", "and", "asm", "auto", "break", "case",
                "catch", "class", "const", "constexpr", "continue", "decltype",
                "default", "delete", "do", "double", "dynamic_cast", "else",
                "enum", "explicit", "extern", "false", "final", "float", "for",
                "friend", "if", "inline", "int", "long", "mutable", "namespace",
                "new", "noexcept", "not", "nullptr", "operator", "override",
                "private", "protected", "public", "register", "reinterpret_cast",
                "return", "short", "signed", "sizeof", "static", "static_cast",
                "struct", "switch", "template", "this", "throw", "true", "try",
                "typedef", "typeid", "typename", "union", "unsigned", "using",
                "virtual", "void", "volatile", "while",
            ]
        case .ruby:
            return [
                "__ENCODING__", "__FILE__", "__LINE__", "alias", "and", "begin",
                "break", "case", "class", "def", "defined?", "do", "else",
                "elsif", "end", "ensure", "false", "for", "if", "in", "module",
                "next", "nil", "not", "or", "redo", "rescue", "retry", "return",
                "self", "super", "then", "true", "undef", "unless", "until",
                "when", "while", "yield",
            ]
        case .kotlin:
            return [
                "as", "break", "by", "catch", "class", "companion", "const",
                "continue", "crossinline", "data", "do", "dynamic", "else",
                "enum", "false", "final", "finally", "for", "fun", "get", "if",
                "import", "in", "infix", "init", "inline", "inner", "interface",
                "internal", "is", "lateinit", "native", "noinline", "null",
                "object", "open", "operator", "out", "override", "package",
                "private", "protected", "public", "reified", "return", "sealed",
                "set", "super", "suspend", "tailrec", "this", "throw", "true",
                "try", "typealias", "val", "var", "vararg", "when", "where",
                "while",
            ]
        case .java:
            return [
                "abstract", "assert", "boolean", "break", "byte", "case",
                "catch", "char", "class", "const", "continue", "default", "do",
                "double", "else", "enum", "extends", "final", "finally", "float",
                "for", "goto", "if", "implements", "import", "instanceof", "int",
                "interface", "long", "native", "new", "null", "package",
                "private", "protected", "public", "return", "short", "static",
                "strictfp", "super", "switch", "synchronized", "this", "throw",
                "throws", "transient", "try", "void", "volatile", "while",
                "record", "sealed", "permits",
            ]
        case .shell:
            return [
                "alias", "bg", "break", "case", "cd", "command", "continue",
                "do", "done", "echo", "elif", "else", "esac", "eval", "exec",
                "exit", "export", "fi", "for", "function", "if", "in", "local",
                "return", "select", "set", "shift", "source", "then", "trap",
                "umask", "unset", "until", "while",
            ]
        case .html:
            return []  // HTML colouring is attribute-oriented, handled separately
        case .css:
            return [
                "auto", "inherit", "initial", "none", "normal", "revert",
                "unset",
            ]
        case .unknown:
            return []
        }
    }

    // MARK: - Comments

    public var singleLineComment: String? {
        switch self {
        case .swift, .javascript, .typescript, .rust, .go, .c, .cpp, .kotlin,
             .java, .css:  return "//"
        case .python, .ruby, .shell: return "#"
        case .html: return nil
        case .unknown: return nil
        }
    }

    public var multiLineComment: (open: String, close: String)? {
        switch self {
        case .swift, .javascript, .typescript, .rust, .go, .c, .cpp, .kotlin,
             .java, .css: return ("/*", "*/")
        case .html: return ("<!--", "-->")
        case .python: return ("\"\"\"", "\"\"\"")
        case .ruby:   return ("=begin", "=end")
        default:      return nil
        }
    }

    // MARK: - String delimiters

    public var stringDelimiters: Set<Character> {
        switch self {
        case .python, .ruby, .shell: return ["\"", "'"]
        case .html, .css:            return ["\"", "'"]
        default:                     return ["\"", "'"]
        }
    }
}
