// VCardMappings — type-parameter labels for `.vcf` (vCard / RFC 6350)
// rendering. Phone, email, and address type aliases.
//
// Origin: Canopy. Strings localized for fr-FR.

import Foundation

public enum VCardMappings {
    public static let phoneTypes: [String: String] = [
        "CELL":  "Mobile",
        "WORK":  "Bureau",
        "HOME":  "Domicile",
        "FAX":   "Fax",
        "PAGER": "Pager",
        "VOICE": "T\u{00E9}l\u{00E9}phone",
        "MAIN":  "Principal"
    ]

    public static let emailTypes: [String: String] = [
        "WORK":  "Bureau",
        "HOME":  "Perso",
        "OTHER": "Autre"
    ]

    public static let addressTypes: [String: String] = [
        "WORK": "Bureau",
        "HOME": "Domicile"
    ]

    public static func resolvePhoneType(_ rawType: String) -> String {
        phoneTypes[rawType.uppercased()] ?? rawType
    }

    public static func resolveEmailType(_ rawType: String) -> String {
        emailTypes[rawType.uppercased()] ?? rawType
    }

    public static func resolveAddressType(_ rawType: String) -> String {
        addressTypes[rawType.uppercased()] ?? rawType
    }
}
