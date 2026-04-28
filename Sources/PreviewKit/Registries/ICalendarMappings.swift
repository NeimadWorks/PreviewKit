// ICalendarMappings — labels and helpers for `.ics` (iCalendar / RFC 5545)
// rendering. Day-name and frequency translations, recurrence formatting,
// video-call domain detection.
//
// Origin: Canopy. Strings are localized for fr-FR — hosts that ship in
// other locales can override `dayNames`/`frequencyLabels` by passing a
// custom mapping into the renderer (TODO when we add CalendarRenderer
// configurability).

import Foundation

public enum ICalendarMappings {
    public static let dayNames: [String: String] = [
        "MO": "lundi", "TU": "mardi", "WE": "mercredi", "TH": "jeudi",
        "FR": "vendredi", "SA": "samedi", "SU": "dimanche"
    ]

    public static let frequencyLabels: [String: String] = [
        "DAILY":   "Chaque jour",
        "WEEKLY":  "Chaque semaine",
        "MONTHLY": "Chaque mois",
        "YEARLY":  "Chaque ann\u{00E9}e"
    ]

    public static let attendeeStatuses: [String: (label: String, isPositive: Bool)] = [
        "ACCEPTED":     ("accept\u{00E9}", true),
        "TENTATIVE":    ("tentative", false),
        "DECLINED":     ("d\u{00E9}clin\u{00E9}", false),
        "NEEDS-ACTION": ("en attente", false)
    ]

    public static let videoCallDomains: Set<String> = [
        "zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com", "whereby.com"
    ]

    /// Format an RRULE (RFC 5545) recurrence string into a French label.
    /// Handles FREQ, INTERVAL, BYDAY, BYMONTHDAY.
    public static func formatRecurrence(_ rrule: String) -> String {
        var parts: [String: String] = [:]
        for component in rrule.components(separatedBy: ";") {
            let kv = component.components(separatedBy: "=")
            if kv.count == 2 { parts[kv[0]] = kv[1] }
        }
        let freq = parts["FREQ"] ?? ""
        let interval = Int(parts["INTERVAL"] ?? "1") ?? 1
        let byday = parts["BYDAY"]

        var result = frequencyLabels[freq] ?? freq
        if interval > 1 {
            switch freq {
            case "WEEKLY":  result = "Toutes les \(interval) semaines"
            case "MONTHLY": result = "Tous les \(interval) mois"
            case "DAILY":   result = "Tous les \(interval) jours"
            default:        break
            }
        }
        if let dayStr = byday {
            let days = dayStr.split(separator: ",").compactMap { dayNames[String($0)] }
            if days.count == 1 {
                result = "Chaque \(days[0])"
            } else if !days.isEmpty {
                result = "Chaque \(days.joined(separator: ", "))"
            }
        }
        if let md = parts["BYMONTHDAY"] {
            result += " (le \(md))"
        }
        return result
    }
}
