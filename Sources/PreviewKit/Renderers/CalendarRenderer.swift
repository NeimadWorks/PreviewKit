// CalendarRenderer — parses `.ics` (RFC 5545) and renders the first event
// with date/time, location, attendees with RSVP status, recurrence rule,
// and reminders / video-call detection. Multi-event files surface the
// count and let the user scroll through them.
//
// Origin: Canopy's `CalendarInspectorHero`, merged on extraction.
// Translation/labels via `ICalendarMappings`.

import SwiftUI

public struct CalendarRenderer: RendererProtocol {

    public static var supportedKinds: Set<ArtifactKind> { [.iCalendar] }
    public static var priority: Int { 0 }
    public static func make() -> CalendarRenderer { CalendarRenderer() }

    public init() {}

    public func body(for item: PreviewItem, data: Data?, url: URL?) -> AnyView {
        AnyView(CalendarRendererBody(item: item, data: data, url: url))
    }
}

private struct CalendarRendererBody: View {

    let item: PreviewItem
    let data: Data?
    let url: URL?

    @State private var events: [ParsedEvent] = []
    @State private var index: Int = 0
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PreviewTokens.sectionGap) {
                if let event = events[safe: index] {
                    eventCard(event)
                    if !badges(for: event).isEmpty {
                        SemanticBadgeRow(badges(for: event))
                    }
                    if let recur = event.recurrence {
                        infoRow(icon: "repeat", text: ICalendarMappings.formatRecurrence(recur))
                    }
                    if !event.attendees.isEmpty {
                        attendeeList(event.attendees)
                    }
                    if events.count > 1 {
                        navigation
                    }
                } else if let loadError {
                    Text(loadError).foregroundStyle(.red)
                } else {
                    ProgressView("Reading…").frame(maxWidth: .infinity)
                }
            }
            .padding(PreviewTokens.cardPadding)
        }
        .task(id: item.id) { await load() }
        .background(PreviewTokens.bgPrimary)
    }

    @ViewBuilder
    private func eventCard(_ event: ParsedEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.summary.isEmpty ? "(no title)" : event.summary)
                .font(PreviewTokens.fontHeader)
            if let when = event.formattedWhen {
                infoRow(icon: "clock", text: when)
            }
            if let loc = event.location, !loc.isEmpty {
                infoRow(icon: "mappin.and.ellipse", text: loc)
            }
            if let url = event.url {
                infoRow(icon: "link", text: url)
            }
        }
    }

    private func attendeeList(_ attendees: [ParsedAttendee]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Attendees")
                .font(PreviewTokens.fontLabel)
                .foregroundStyle(PreviewTokens.textMuted)
                .textCase(.uppercase)
            ForEach(Array(attendees.enumerated()), id: \.offset) { _, a in
                HStack(spacing: 6) {
                    Circle()
                        .fill(a.isPositive ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)
                    Text(a.email)
                        .font(PreviewTokens.fontBody)
                    if !a.statusLabel.isEmpty {
                        Text(a.statusLabel)
                            .font(PreviewTokens.fontLabel)
                            .foregroundStyle(PreviewTokens.textMuted)
                    }
                }
            }
        }
    }

    private var navigation: some View {
        HStack {
            Button("←") { index = max(0, index - 1) }
                .disabled(index == 0)
            Text("Event \(index + 1) / \(events.count)")
                .font(PreviewTokens.fontLabel)
                .foregroundStyle(PreviewTokens.textMuted)
            Button("→") { index = min(events.count - 1, index + 1) }
                .disabled(index >= events.count - 1)
        }
    }

    private func badges(for event: ParsedEvent) -> [SemanticBadgeModel] {
        var b: [SemanticBadgeModel] = []
        if event.hasReminder {
            b.append(SemanticBadgeModel(text: "Reminder", style: .info, icon: "bell"))
        }
        if event.isVideoCall {
            b.append(SemanticBadgeModel(text: "Video", style: .info, icon: "video"))
        }
        if event.recurrence != nil {
            b.append(SemanticBadgeModel(text: "Recurring", style: .neutral, icon: "repeat"))
        }
        return b
    }

    private func infoRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon).foregroundStyle(PreviewTokens.textMuted)
            Text(text).font(PreviewTokens.fontBody)
        }
    }

    // MARK: - Parsing

    private func load() async {
        let bytes: Data?
        if let data { bytes = data }
        else if let url { bytes = try? Data(contentsOf: url) }
        else { bytes = nil }
        guard let bytes, let text = String(data: bytes, encoding: .utf8) else {
            loadError = "Couldn't read calendar"
            return
        }
        events = ICSParser.parse(text)
        if events.isEmpty {
            loadError = "No VEVENT blocks found"
        }
    }
}

// MARK: - ICS parser

private struct ParsedEvent: Hashable {
    let summary: String
    let location: String?
    let url: String?
    let dtStart: String?
    let dtEnd: String?
    let recurrence: String?
    let attendees: [ParsedAttendee]
    let hasReminder: Bool
    let isVideoCall: Bool

    var formattedWhen: String? {
        let parts = [dtStart, dtEnd].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " → ")
    }
}

private struct ParsedAttendee: Hashable {
    let email: String
    let statusLabel: String
    let isPositive: Bool
}

private enum ICSParser {

    static func parse(_ text: String) -> [ParsedEvent] {
        // RFC 5545: lines folded with leading whitespace continue prior line.
        var unfolded: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            if (raw.first == " " || raw.first == "\t"), !unfolded.isEmpty {
                unfolded[unfolded.count - 1] += String(raw.dropFirst())
            } else {
                unfolded.append(raw)
            }
        }

        var events: [ParsedEvent] = []
        var inEvent = false
        var current: [String: [String]] = [:]
        var attendees: [ParsedAttendee] = []
        var hasReminder = false

        for line in unfolded {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "BEGIN:VEVENT" {
                inEvent = true; current = [:]; attendees = []; hasReminder = false
                continue
            }
            if trimmed == "END:VEVENT", inEvent {
                events.append(ParsedEvent(
                    summary: current["SUMMARY"]?.first ?? "",
                    location: current["LOCATION"]?.first,
                    url: current["URL"]?.first,
                    dtStart: current["DTSTART"]?.first,
                    dtEnd: current["DTEND"]?.first,
                    recurrence: current["RRULE"]?.first,
                    attendees: attendees,
                    hasReminder: hasReminder,
                    isVideoCall: detectVideo(current)
                ))
                inEvent = false
                continue
            }
            if !inEvent { continue }

            // Reminders are nested VALARM blocks
            if trimmed == "BEGIN:VALARM" { hasReminder = true; continue }

            // ATTENDEE;PARTSTAT=ACCEPTED:mailto:foo@bar.com
            if trimmed.hasPrefix("ATTENDEE") {
                let (params, value) = splitParameters(trimmed)
                let status = params["PARTSTAT"] ?? ""
                let mapped = ICalendarMappings.attendeeStatuses[status] ?? ("", false)
                let email = value.replacingOccurrences(of: "mailto:", with: "")
                attendees.append(ParsedAttendee(email: email, statusLabel: mapped.label, isPositive: mapped.isPositive))
                continue
            }

            // Generic key:value (with optional ;params before colon)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            var key = String(trimmed[..<colon])
            if let semi = key.firstIndex(of: ";") { key = String(key[..<semi]) }
            let val = String(trimmed[trimmed.index(after: colon)...])
            current[key, default: []].append(val)
        }

        return events
    }

    private static func splitParameters(_ raw: String) -> (params: [String: String], value: String) {
        guard let colon = raw.firstIndex(of: ":") else { return ([:], raw) }
        let head = String(raw[..<colon])
        let value = String(raw[raw.index(after: colon)...])
        var params: [String: String] = [:]
        for chunk in head.split(separator: ";").dropFirst() {
            let kv = chunk.split(separator: "=", maxSplits: 1)
            if kv.count == 2 { params[String(kv[0])] = String(kv[1]) }
        }
        return (params, value)
    }

    private static func detectVideo(_ event: [String: [String]]) -> Bool {
        let candidates = (event["URL"] ?? []) + (event["LOCATION"] ?? []) + (event["DESCRIPTION"] ?? [])
        for s in candidates {
            for domain in ICalendarMappings.videoCallDomains {
                if s.lowercased().contains(domain) { return true }
            }
        }
        return false
    }
}

// MARK: - Helpers

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
