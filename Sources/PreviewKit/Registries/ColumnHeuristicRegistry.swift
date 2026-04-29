import Foundation

// MARK: - Column Heuristic Registry

public enum ColumnHeuristicRegistry {
    public static let timestampNames: Set<String> = [
        "created_at", "updated_at", "timestamp", "date", "time", "visit_time",
        "modified", "created", "datetime", "last_modified", "inserted_at",
        "occurred_at", "event_time", "start_date", "end_date", "deleted_at"
    ]

    public static let sensitiveNames: Set<String> = [
        "password", "passwd", "pwd", "secret", "token", "api_key", "apikey",
        "access_key", "private_key", "credential", "auth", "ssn",
        "social_security", "credit_card", "card_number", "cvv", "pin"
    ]

    public static let piiNames: Set<String> = [
        "email", "phone", "mobile", "address", "date_of_birth", "dob",
        "ip_address", "latitude", "longitude", "location", "first_name",
        "last_name", "full_name"
    ]

    public static func isTimestamp(_ name: String) -> Bool { timestampNames.contains(name.lowercased()) }
    public static func isSensitive(_ name: String) -> Bool { sensitiveNames.contains(name.lowercased()) }
    public static func isPII(_ name: String) -> Bool { piiNames.contains(name.lowercased()) }
}
