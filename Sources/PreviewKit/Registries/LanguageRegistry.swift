import SwiftUI

// MARK: - Language Definition

public struct LanguageDefinition: Sendable {
    public let id: String
    public let displayName: String
    public let colorHex: String
    public let extensions: Set<String>
    public let commentPatterns: [String]
    public let importPattern: String?
    public let declPattern: String?
    public let funcPattern: String?
    public let propPattern: String?
    public let systemModules: Set<String>

    public init(
        id: String, displayName: String, colorHex: String,
        extensions: Set<String>, commentPatterns: [String],
        importPattern: String? = nil, declPattern: String? = nil,
        funcPattern: String? = nil, propPattern: String? = nil,
        systemModules: Set<String> = []
    ) {
        self.id = id; self.displayName = displayName; self.colorHex = colorHex
        self.extensions = extensions; self.commentPatterns = commentPatterns
        self.importPattern = importPattern; self.declPattern = declPattern
        self.funcPattern = funcPattern; self.propPattern = propPattern
        self.systemModules = systemModules
    }

    public var color: Color { Color(hex: colorHex) }
}

// MARK: - Language Registry

public enum LanguageRegistry {
    public static let all: [LanguageDefinition] = [
        LanguageDefinition(
            id: "swift", displayName: "Swift", colorHex: "#F05138",
            extensions: ["swift"],
            commentPatterns: ["^\\s*//", "^\\s*/\\*"],
            importPattern: "^import\\s+\\w+",
            declPattern: "^(?:public\\s+|private\\s+|internal\\s+|open\\s+|final\\s+)*(?:class|struct|enum|protocol|extension|actor)\\s+\\w+",
            funcPattern: "(?:func|init)\\s+\\w+",
            propPattern: "(?:var|let)\\s+\\w+",
            systemModules: ["SwiftUI", "Foundation", "UIKit", "AppKit", "Combine", "CoreData",
                            "CoreGraphics", "CoreImage", "CoreText", "CoreLocation", "MapKit",
                            "AVFoundation", "PDFKit", "QuickLook", "QuickLookThumbnailing",
                            "Security", "CryptoKit", "Network", "OSLog", "Observation",
                            "UniformTypeIdentifiers", "Darwin", "Swift", "Dispatch"]),
        LanguageDefinition(
            id: "python", displayName: "Python", colorHex: "#3572A5",
            extensions: ["py"],
            commentPatterns: ["^\\s*#"],
            importPattern: "^(?:import|from)\\s+\\w+",
            declPattern: "^class\\s+\\w+",
            funcPattern: "^\\s*def\\s+\\w+",
            propPattern: "self\\.\\w+\\s*=",
            systemModules: ["os", "sys", "json", "re", "math", "datetime", "collections",
                            "functools", "itertools", "pathlib", "typing", "io", "csv",
                            "hashlib", "http", "urllib", "socket", "threading", "subprocess",
                            "logging", "unittest", "argparse", "copy", "time", "random",
                            "string", "struct", "abc", "enum", "dataclasses", "contextlib"]),
        LanguageDefinition(
            id: "javascript", displayName: "JavaScript", colorHex: "#F7DF1E",
            extensions: ["js", "jsx"],
            commentPatterns: ["^\\s*//"],
            importPattern: "^import\\s+|\\brequire\\s*\\(",
            declPattern: "^(?:export\\s+)?(?:class|function)\\s+\\w+",
            funcPattern: "(?:function\\s+\\w+|(?:const|let|var)\\s+\\w+\\s*=\\s*(?:async\\s+)?(?:\\([^)]*\\)|\\w+)\\s*=>)",
            propPattern: "(?:this\\.\\w+\\s*=|static\\s+\\w+\\s*=)",
            systemModules: ["fs", "path", "http", "https", "url", "os", "util", "events",
                            "stream", "crypto", "child_process", "buffer", "net", "dns",
                            "assert", "querystring", "readline", "zlib", "cluster", "tls"]),
        LanguageDefinition(
            id: "typescript", displayName: "TypeScript", colorHex: "#3178C6",
            extensions: ["ts", "tsx"],
            commentPatterns: ["^\\s*//"],
            importPattern: "^import\\s+|\\brequire\\s*\\(",
            declPattern: "^(?:export\\s+)?(?:class|function)\\s+\\w+",
            funcPattern: "(?:function\\s+\\w+|(?:const|let|var)\\s+\\w+\\s*=\\s*(?:async\\s+)?(?:\\([^)]*\\)|\\w+)\\s*=>)",
            propPattern: "(?:this\\.\\w+\\s*=|static\\s+\\w+\\s*=)",
            systemModules: ["fs", "path", "http", "https", "url", "os", "util", "events",
                            "stream", "crypto", "child_process", "buffer", "net", "dns",
                            "assert", "querystring", "readline", "zlib", "cluster", "tls"]),
        LanguageDefinition(
            id: "go", displayName: "Go", colorHex: "#00ADD8",
            extensions: ["go"],
            commentPatterns: ["^\\s*//"],
            importPattern: "^import\\s+|^\\s*\"[^\"]+\"",
            declPattern: "^type\\s+\\w+\\s+(?:struct|interface)",
            funcPattern: "^func\\s+(?:\\([^)]+\\)\\s+)?\\w+",
            propPattern: "^\\s+\\w+\\s+\\w+",
            systemModules: ["fmt", "os", "io", "net", "http", "strings", "strconv", "sync",
                            "context", "errors", "log", "math", "time", "sort", "encoding",
                            "bytes", "bufio", "regexp", "testing", "reflect", "runtime",
                            "path", "filepath"]),
        LanguageDefinition(
            id: "rust", displayName: "Rust", colorHex: "#DEA584",
            extensions: ["rs"],
            commentPatterns: ["^\\s*//"],
            importPattern: "^use\\s+",
            declPattern: "^(?:pub(?:\\(crate\\))?\\s+)?(?:struct|enum|trait|impl)\\s+\\w+",
            funcPattern: "(?:pub(?:\\(crate\\))?\\s+)?fn\\s+\\w+",
            propPattern: "^\\s+(?:pub\\s+)?\\w+:\\s+",
            systemModules: ["std", "core", "alloc"]),
        LanguageDefinition(
            id: "java", displayName: "Java", colorHex: "#B07219",
            extensions: ["java"],
            commentPatterns: ["^\\s*//"],
            importPattern: "^import\\s+",
            declPattern: "(?:public|private|protected|internal)?\\s*(?:class|interface|enum|object)\\s+\\w+",
            funcPattern: "(?:public|private|protected|internal|override)?\\s*(?:fun|void|static)?\\s*\\w+\\s*\\(",
            propPattern: "(?:private|public|protected)?\\s*(?:val|var|static)?\\s+\\w+\\s*[:=]",
            systemModules: ["java", "javax", "kotlin"]),
        LanguageDefinition(
            id: "kotlin", displayName: "Kotlin", colorHex: "#B07219",
            extensions: ["kt"],
            commentPatterns: ["^\\s*//"],
            importPattern: "^import\\s+",
            declPattern: "(?:public|private|protected|internal)?\\s*(?:class|interface|enum|object)\\s+\\w+",
            funcPattern: "(?:public|private|protected|internal|override)?\\s*(?:fun|void|static)?\\s*\\w+\\s*\\(",
            propPattern: "(?:private|public|protected)?\\s*(?:val|var|static)?\\s+\\w+\\s*[:=]",
            systemModules: ["java", "javax", "kotlin"]),
        LanguageDefinition(
            id: "c", displayName: "C", colorHex: "#555555",
            extensions: ["c", "h"],
            commentPatterns: ["^\\s*//"],
            importPattern: "^#include\\s+",
            declPattern: "^(?:class|struct|enum|namespace)\\s+\\w+",
            funcPattern: "^\\w[\\w:*&<> ]+\\s+\\w+\\s*\\(",
            propPattern: nil,
            systemModules: ["stdio", "stdlib", "string", "math", "time", "assert", "ctype",
                            "errno", "float", "limits", "locale", "signal", "stdarg",
                            "iostream", "vector", "map", "string", "algorithm", "memory",
                            "functional", "utility", "set", "queue", "stack", "array"]),
        LanguageDefinition(
            id: "cpp", displayName: "C++", colorHex: "#F34B7D",
            extensions: ["cpp", "hpp"],
            commentPatterns: ["^\\s*//"],
            importPattern: "^#include\\s+",
            declPattern: "^(?:class|struct|enum|namespace)\\s+\\w+",
            funcPattern: "^\\w[\\w:*&<> ]+\\s+\\w+\\s*\\(",
            propPattern: nil,
            systemModules: ["stdio", "stdlib", "string", "math", "time", "assert", "ctype",
                            "errno", "float", "limits", "locale", "signal", "stdarg",
                            "iostream", "vector", "map", "string", "algorithm", "memory",
                            "functional", "utility", "set", "queue", "stack", "array"]),
        LanguageDefinition(
            id: "ruby", displayName: "Ruby", colorHex: "#701516",
            extensions: ["rb"],
            commentPatterns: ["^\\s*#"],
            importPattern: "^require\\s+",
            declPattern: "^(?:class|module)\\s+\\w+",
            funcPattern: "^\\s*def\\s+\\w+",
            propPattern: "@\\w+",
            systemModules: ["json", "yaml", "csv", "net", "uri", "open-uri", "fileutils",
                            "set", "date", "time", "pathname", "optparse", "logger"]),
        LanguageDefinition(
            id: "php", displayName: "PHP", colorHex: "#4F5D95",
            extensions: ["php"],
            commentPatterns: ["^\\s*(?://|#)"],
            importPattern: "^(?:use|require|include)\\s+",
            declPattern: "^(?:class|interface|trait)\\s+\\w+",
            funcPattern: "(?:public|private|protected|static)?\\s*function\\s+\\w+",
            propPattern: "(?:public|private|protected|static)?\\s*\\$\\w+",
            systemModules: []),
        LanguageDefinition(
            id: "shell", displayName: "Shell", colorHex: "#89E051",
            extensions: ["sh", "bash", "zsh"],
            commentPatterns: ["^\\s*#"],
            importPattern: "^(?:source|\\.)\\s+",
            declPattern: nil,
            funcPattern: "^(?:function\\s+)?\\w+\\s*\\(\\s*\\)",
            propPattern: nil,
            systemModules: []),
        LanguageDefinition(
            id: "sql", displayName: "SQL", colorHex: "#E38C00",
            extensions: ["sql"],
            commentPatterns: ["^\\s*--"],
            importPattern: nil,
            declPattern: "^CREATE\\s+(?:TABLE|VIEW|FUNCTION|PROCEDURE)",
            funcPattern: nil,
            propPattern: nil,
            systemModules: []),
        LanguageDefinition(
            id: "perl", displayName: "Perl", colorHex: "#0298C3",
            extensions: ["pl", "pm"],
            commentPatterns: ["^\\s*#"],
            importPattern: "^(?:use|require)\\s+",
            declPattern: "^package\\s+\\w+",
            funcPattern: "^sub\\s+\\w+",
            propPattern: nil,
            systemModules: []),
        LanguageDefinition(
            id: "html", displayName: "HTML", colorHex: "#E34C26",
            extensions: ["html", "htm", "xhtml"],
            commentPatterns: ["^\\s*<!--"],
            importPattern: nil,
            declPattern: nil,
            funcPattern: nil,
            propPattern: nil,
            systemModules: []),
        LanguageDefinition(
            id: "css", displayName: "CSS", colorHex: "#563D7C",
            extensions: ["css", "scss", "less"],
            commentPatterns: ["^\\s*/\\*"],
            importPattern: "^@import\\s+",
            declPattern: nil,
            funcPattern: nil,
            propPattern: nil,
            systemModules: []),
    ]

    /// Detect language from file extension
    public static func detect(extension ext: String) -> LanguageDefinition? {
        all.first { $0.extensions.contains(ext.lowercased()) }
    }

    /// Get language color from file extension
    public static func color(for ext: String) -> Color {
        detect(extension: ext)?.color ?? Color(red: 0.53, green: 0.53, blue: 0.50)
    }

    /// Default (fallback) color for unrecognized extensions
    public static let defaultColor = Color(red: 0.53, green: 0.53, blue: 0.50)
}
