import Foundation

// MARK: - File Role

public enum FileRole: String, Sendable {
    case test, ui, model, service, configuration, contract, entryPoint, extensionFile, script, migration

    public var displayName: String {
        switch self {
        case .test: return "Test"
        case .ui: return "Vue"
        case .model: return "Mod\u{00E8}le"
        case .service: return "Service"
        case .configuration: return "Configuration"
        case .contract: return "Contrat"
        case .entryPoint: return "Point d\u{2019}entr\u{00E9}e"
        case .extensionFile: return "Extension"
        case .script: return "Script"
        case .migration: return "Migration"
        }
    }
}

// MARK: - File Role Rule

public struct FileRoleRule: Sendable {
    public let role: FileRole
    public let filenamePatterns: [String]
    public let contentPatterns: [String]
    public let priority: Int

    public init(role: FileRole, filenamePatterns: [String], contentPatterns: [String], priority: Int) {
        self.role = role
        self.filenamePatterns = filenamePatterns
        self.contentPatterns = contentPatterns
        self.priority = priority
    }
}

// MARK: - File Role Registry

public enum FileRoleRegistry {
    public static let rules: [FileRoleRule] = [
        .init(role: .test, filenamePatterns: ["test", "spec", "test_"],
              contentPatterns: [":View", ": View", "UIView", "Component"], priority: 100),
        .init(role: .ui, filenamePatterns: ["View", "Screen", "Page", "Cell", "Widget", "Component"],
              contentPatterns: [":View", ": View", "UIView", "Component"], priority: 90),
        .init(role: .service, filenamePatterns: ["Service", "Manager", "Handler"],
              contentPatterns: ["Service", "Manager", "Handler"], priority: 80),
        .init(role: .model, filenamePatterns: ["Model", "Entity"],
              contentPatterns: ["Model", "Entity"], priority: 70),
        .init(role: .entryPoint, filenamePatterns: ["main", "index", "app."],
              contentPatterns: [], priority: 60),
        .init(role: .configuration, filenamePatterns: ["config", "settings"],
              contentPatterns: [], priority: 50),
    ]

    /// Detect primary role from filename and content.
    public static func detect(filename: String, contentSample: String) -> String? {
        let lower = filename.lowercased()

        // Test detection (filename-based, highest priority)
        if lower.contains("test") || lower.contains("spec") || lower.hasPrefix("test_") {
            return FileRole.test.displayName
        }

        // Content-based detection
        if contentSample.contains(":View") || contentSample.contains("UIView") ||
           contentSample.contains("Component") || contentSample.contains(": View") {
            return FileRole.ui.displayName
        }
        if contentSample.contains("Service") || contentSample.contains("Manager") || contentSample.contains("Handler") {
            return FileRole.service.displayName
        }
        if contentSample.contains("Model") || contentSample.contains("Entity") {
            return FileRole.model.displayName
        }
        if lower.contains("main") || lower.contains("index") || lower.hasPrefix("app.") || lower.hasPrefix("app ") {
            return FileRole.entryPoint.displayName
        }
        if lower.contains("config") || lower.contains("settings") {
            return FileRole.configuration.displayName
        }
        return nil
    }

    // MARK: - Secondary Roles

    public static let secondaryRules: [(label: String, patterns: [String])] = [
        ("Observable", ["@Published", "@Observable"]),
        ("Networking", ["URLSession", "fetch(", "XMLHttpRequest"]),
        ("Async", ["async ", "await "]),
    ]

    public static func detectSecondary(content: String) -> String? {
        if content.contains("@Published") || content.contains("@Observable") { return "Observable" }
        if content.contains("URLSession") || content.contains("fetch(") || content.contains("XMLHttpRequest") { return "Networking" }
        if content.contains("async ") && content.contains("await ") { return "Async" }
        return nil
    }
}
