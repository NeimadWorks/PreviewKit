// AppSignatureRegistry — fingerprints for SQLite databases produced by
// well-known macOS / iOS applications. Used by `SQLiteRenderer` to display
// "Safari History" instead of the generic "SQLite database" when a schema
// matches a known signature.
//
// Origin: Canopy (Plugins/Documents/Registries/AppSignatureRegistry.swift),
// merged into PreviewKit on extraction so all hosts inherit the same
// fingerprint set. Adding a signature is a one-line entry below.

import Foundation

public struct AppSignature: Sendable, Hashable {
    public let id: String
    public let appName: String
    public let description: String
    public let requiredTables: Set<String>
    public let bundleIdentifier: String?
    public let priority: Int

    public init(
        id: String,
        appName: String,
        description: String,
        requiredTables: Set<String>,
        bundleIdentifier: String? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.appName = appName
        self.description = description
        self.requiredTables = requiredTables
        self.bundleIdentifier = bundleIdentifier
        self.priority = priority
    }
}

public enum AppSignatureRegistry {
    public static let signatures: [AppSignature] = [
        .init(id: "safari_history",  appName: "Safari History",          description: "Browsing history",
              requiredTables: ["history_visits", "history_items"], bundleIdentifier: "com.apple.Safari", priority: 100),
        .init(id: "chrome_history",  appName: "Chrome / Edge History",   description: "History",
              requiredTables: ["urls", "visits"], bundleIdentifier: "com.google.Chrome", priority: 100),
        .init(id: "imessage",        appName: "iMessage",                description: "Conversations",
              requiredTables: ["message", "chat", "handle"], bundleIdentifier: "com.apple.MobileSMS", priority: 100),
        .init(id: "photos",          appName: "Photos",                  description: "Library",
              requiredTables: ["zgenericasset"], bundleIdentifier: "com.apple.Photos", priority: 100),
        .init(id: "notes",           appName: "Notes",                   description: "Notes",
              requiredTables: ["ziccloudsyncingobject"], bundleIdentifier: "com.apple.Notes", priority: 100),
        .init(id: "contacts",        appName: "Contacts",                description: "Address book",
              requiredTables: ["abperson", "abmultivalue"], bundleIdentifier: "com.apple.AddressBook", priority: 90),
        .init(id: "mail",            appName: "Mail",                    description: "Messages",
              requiredTables: ["messages", "mailboxes"], bundleIdentifier: "com.apple.mail", priority: 90),
        .init(id: "calendar",        appName: "Calendar",                description: "Events",
              requiredTables: ["calendaritem", "calendar"], bundleIdentifier: "com.apple.iCal", priority: 90),
        .init(id: "firefox",         appName: "Firefox",                 description: "Places",
              requiredTables: ["moz_places", "moz_bookmarks"], bundleIdentifier: "org.mozilla.firefox", priority: 100),
        .init(id: "coredata",        appName: "Core Data",               description: "Core Data store",
              requiredTables: ["z_primarykey", "z_metadata"], priority: 10),
    ]

    /// Match table names against known app signatures. Table names should be
    /// lowercased before calling. Returns the highest-priority match, or nil
    /// when nothing matches.
    public static func match(tables: Set<String>) -> AppSignature? {
        signatures
            .sorted { $0.priority > $1.priority }
            .first { $0.requiredTables.isSubset(of: tables) }
    }
}
