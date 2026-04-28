// URLSecurityRegistry — tracking-parameter detection and stripping,
// IP-address heuristic. Used by `WebShortcutRenderer` to flag suspicious
// `.webloc` / `.url` shortcuts.
//
// Origin: Canopy.

import Foundation

public enum URLSecurityRegistry {
    public static let trackingParams: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term",
        "fbclid", "gclid", "ref", "source", "mc_cid", "mc_eid", "yclid",
        "msclkid", "_ga", "igshid"
    ]

    public static func hasTracking(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return components.queryItems?.contains { trackingParams.contains($0.name) } ?? false
    }

    public static func stripTracking(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        components.queryItems = components.queryItems?.filter { !trackingParams.contains($0.name) }
        if components.queryItems?.isEmpty == true { components.queryItems = nil }
        return components.url ?? url
    }

    public static func isDomainIP(_ host: String) -> Bool {
        host.range(of: "^\\d+\\.\\d+\\.\\d+\\.\\d+$", options: .regularExpression) != nil
    }
}
