// MobileProvisionAnalyzer — extract the embedded plist from a CMS-signed
// `.mobileprovision` / `.provisionprofile` blob, then surface the fields
// developers actually care about (expiry, team, bundle id, entitlements,
// provisioned devices).
//
// Uses a marker-based extraction (`<?xml … </plist>`) rather than
// CMSDecoder so the code is portable and testable without Security.framework
// ceremony. The CMS wrapper around Apple provisioning profiles is always
// detached-signed ASCII plist content; scanning the raw bytes for the plist
// boundaries is the standard technique.

import Foundation

public struct ProvisionProfile: Sendable {
    public enum ProfileType: String, Sendable { case appStore, adHoc, development, enterprise, unknown }

    public var name: String
    public var teamName: String
    public var teamIdentifier: String
    public var bundleIdentifier: String
    public var profileType: ProfileType
    public var creationDate: Date?
    public var expirationDate: Date?
    public var provisionedDevices: [String]
    public var entitlements: [(key: String, value: String)]
    public var uuid: String

    public var daysUntilExpiry: Int? {
        guard let exp = expirationDate else { return nil }
        let days = Calendar(identifier: .gregorian)
            .dateComponents([.day], from: Date(), to: exp).day
        return days
    }
}

public enum MobileProvisionAnalyzer {

    /// Extract the inner plist bytes from a CMS-signed provisioning
    /// profile. Returns nil if no plist markers are found.
    public static func extractPlistData(from data: Data) -> Data? {
        // Scan for "<?xml" and "</plist>".
        let head: [UInt8] = [0x3C, 0x3F, 0x78, 0x6D, 0x6C]             // <?xml
        let tail: [UInt8] = [0x3C, 0x2F, 0x70, 0x6C, 0x69, 0x73, 0x74, 0x3E]  // </plist>
        let bytes = [UInt8](data)
        guard let start = index(of: head, in: bytes) else { return nil }
        guard let endStart = index(of: tail, in: bytes, from: start) else { return nil }
        let end = endStart + tail.count
        return Data(bytes[start..<end])
    }

    public static func parse(data: Data) -> ProvisionProfile? {
        guard let plistData = extractPlistData(from: data) else { return nil }
        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData, options: [], format: nil
        ) as? [String: Any] else {
            return nil
        }
        return parse(plist: plist)
    }

    /// Exposed for tests — lets a test build a plist dictionary directly
    /// and exercise the field extraction without fabricating CMS bytes.
    public static func parse(plist p: [String: Any]) -> ProvisionProfile {
        let ents = (p["Entitlements"] as? [String: Any]) ?? [:]
        let appID = ents["application-identifier"] as? String ?? ""
        let teamID = (p["TeamIdentifier"] as? [String])?.first
                   ?? (ents["com.apple.developer.team-identifier"] as? String)
                   ?? ""
        // Bundle id = appID with the leading team prefix stripped.
        let bundleID: String = {
            if appID.hasPrefix(teamID + "."), !teamID.isEmpty {
                return String(appID.dropFirst(teamID.count + 1))
            }
            return appID
        }()
        let devices = p["ProvisionedDevices"] as? [String] ?? []
        let provisionsAll = p["ProvisionsAllDevices"] as? Bool ?? false
        let getTaskAllow = ents["get-task-allow"] as? Bool ?? false

        let type: ProvisionProfile.ProfileType
        if provisionsAll               { type = .enterprise }
        else if getTaskAllow           { type = .development }
        else if devices.isEmpty        { type = .appStore }
        else                           { type = .adHoc }

        // Stable-order entitlements rendering (alphabetical).
        let entitlements: [(String, String)] = ents
            .sorted { $0.key < $1.key }
            .map { ($0.key, stringify($0.value)) }

        return ProvisionProfile(
            name: p["Name"] as? String ?? "",
            teamName: p["TeamName"] as? String ?? "",
            teamIdentifier: teamID,
            bundleIdentifier: bundleID,
            profileType: type,
            creationDate: p["CreationDate"] as? Date,
            expirationDate: p["ExpirationDate"] as? Date,
            provisionedDevices: devices,
            entitlements: entitlements,
            uuid: p["UUID"] as? String ?? ""
        )
    }

    // MARK: - Helpers

    private static func index(of needle: [UInt8], in haystack: [UInt8], from: Int = 0) -> Int? {
        guard !needle.isEmpty, haystack.count >= needle.count + from else { return nil }
        let limit = haystack.count - needle.count
        var i = from
        while i <= limit {
            if Array(haystack[i..<i+needle.count]) == needle { return i }
            i += 1
        }
        return nil
    }

    private static func stringify(_ v: Any) -> String {
        switch v {
        case let b as Bool:    return b ? "true" : "false"
        case let s as String:  return s
        case let a as [Any]:   return a.map { stringify($0) }.joined(separator: ", ")
        case let d as [String: Any]:
            return d.map { "\($0.key)=\(stringify($0.value))" }.joined(separator: "; ")
        default:               return String(describing: v)
        }
    }
}
