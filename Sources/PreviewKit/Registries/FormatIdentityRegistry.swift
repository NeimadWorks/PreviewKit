// FormatIdentityRegistry — extension → display identity (color + family
// + label) for OOXML / iWork / SQLite / Jupyter / iCal / vCard / web
// shortcuts. Used by renderers' header cards.
//
// Origin: Canopy. Hex colors translated to Color(hex:) at use site.

import SwiftUI

public struct FormatIdentity: Sendable {
    public let extensions: Set<String>
    public let dotColorHex: String
    public let familyName: String
    public let genericLabel: String
    public let macroExtensions: Set<String>

    public init(
        extensions: Set<String>,
        dotColorHex: String,
        familyName: String,
        genericLabel: String,
        macroExtensions: Set<String> = []
    ) {
        self.extensions = extensions
        self.dotColorHex = dotColorHex
        self.familyName = familyName
        self.genericLabel = genericLabel
        self.macroExtensions = macroExtensions
    }

    /// Convenience accessor — pure SwiftUI Color from the hex.
    public var dotColor: Color { Color(hex: dotColorHex) }
}

public enum FormatIdentityRegistry {
    public static let identities: [FormatIdentity] = [
        .init(extensions: ["docx", "dotx", "docm"], dotColorHex: "#378ADD", familyName: "Word",
              genericLabel: "Word Document", macroExtensions: ["docm"]),
        .init(extensions: ["xlsx", "xltx", "xlsm"], dotColorHex: "#639922", familyName: "Excel",
              genericLabel: "Excel Workbook", macroExtensions: ["xlsm"]),
        .init(extensions: ["pptx", "potx", "pptm"], dotColorHex: "#D85A30", familyName: "PowerPoint",
              genericLabel: "Presentation", macroExtensions: ["pptm"]),
        .init(extensions: ["pages"], dotColorHex: "#378ADD", familyName: "Pages",
              genericLabel: "Pages Document"),
        .init(extensions: ["numbers"], dotColorHex: "#639922", familyName: "Numbers",
              genericLabel: "Numbers Spreadsheet"),
        .init(extensions: ["key"], dotColorHex: "#D85A30", familyName: "Keynote",
              genericLabel: "Keynote Presentation"),
        .init(extensions: ["sqlite", "sqlite3", "db"], dotColorHex: "#BA7517", familyName: "SQLite",
              genericLabel: "SQLite Database"),
        .init(extensions: ["ipynb"], dotColorHex: "#F24D33", familyName: "Jupyter",
              genericLabel: "Jupyter Notebook"),
        .init(extensions: ["ics", "ical", "icalendar"], dotColorHex: "#E24B4A", familyName: "Calendar",
              genericLabel: "iCalendar Event"),
        .init(extensions: ["vcf", "vcard"], dotColorHex: "#534AB7", familyName: "Contact",
              genericLabel: "vCard Contact"),
        .init(extensions: ["webloc", "url", "website"], dotColorHex: "#378ADD", familyName: "Web",
              genericLabel: "Web Shortcut"),
    ]

    public static func identity(for ext: String) -> FormatIdentity? {
        identities.first { $0.extensions.contains(ext.lowercased()) }
    }

    public static func hasMacros(_ ext: String) -> Bool {
        identities.contains { $0.macroExtensions.contains(ext.lowercased()) }
    }
}
