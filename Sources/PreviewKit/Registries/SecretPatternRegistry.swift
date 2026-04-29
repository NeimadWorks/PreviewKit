import Foundation

// MARK: - Secret Pattern

public struct SecretPattern: Sendable {
    public let id: String
    public let displayName: String
    public let regex: String
    public let severity: SecretSeverity

    public enum SecretSeverity: Sendable { case critical, warning, info }
}

// MARK: - Secret Pattern Registry

public enum SecretPatternRegistry {
    public static let patterns: [SecretPattern] = [
        .init(id: "aws_key", displayName: "AWS Key", regex: "AKIA[0-9A-Z]{16}", severity: .critical),
        .init(id: "gcp_key", displayName: "GCP Key", regex: "AIza[0-9A-Za-z_\\-]{35}", severity: .critical),
        .init(id: "github_pat", displayName: "GitHub Token", regex: "ghp_[0-9a-zA-Z]{36}", severity: .critical),
        .init(id: "stripe_key", displayName: "Stripe Key", regex: "sk_(?:live|test)_\\w+", severity: .critical),
        .init(id: "secret_assign", displayName: "Secret assign\u{00E9}", regex: "(?:password|secret|api_key|token)\\s*=\\s*\"[^\"]{8,}\"", severity: .critical),
        .init(id: "private_key", displayName: "Cl\u{00E9} priv\u{00E9}e", regex: "BEGIN (?:RSA|EC|OPENSSH) PRIVATE KEY", severity: .critical),
        .init(id: "jwt", displayName: "JWT Token", regex: "eyJ[A-Za-z0-9_-]+\\.eyJ[A-Za-z0-9_-]+\\.", severity: .warning),
        .init(id: "slack_bot", displayName: "Token Slack", regex: "xoxb-[0-9]{10,}-[0-9a-zA-Z]{24,}", severity: .critical),
        .init(id: "url_creds", displayName: "URL avec credentials", regex: "https?://[^:]+:[^@]+@[^\\s\"']+", severity: .critical),
    ]

    public static let exclusionPattern = "(?:process\\.env|os\\.environ|getenv|xxx|your_key_here|TODO|CHANGEME|placeholder)"

    /// Language-specific dangerous patterns
    public static let languagePatterns: [String: [(displayName: String, regex: String, severity: SecretPattern.SecretSeverity)]] = [
        "rs": [("unsafe", "\\bunsafe\\b", .warning)],
        "go": [("import unsafe", "\"unsafe\"", .warning)],
        "js": [("eval/innerHTML", "\\b(?:eval)\\s*\\(|innerHTML\\s*=", .critical)],
        "jsx": [("eval/innerHTML", "\\b(?:eval)\\s*\\(|innerHTML\\s*=", .critical)],
        "ts": [("eval/innerHTML", "\\b(?:eval)\\s*\\(|innerHTML\\s*=", .critical)],
        "tsx": [("eval/innerHTML", "\\b(?:eval)\\s*\\(|innerHTML\\s*=", .critical)],
        "sh": [("Commande dangereuse", "\\b(?:eval|rm\\s+-rf\\s+/|curl\\s+[^|]*\\|\\s*(?:sh|bash))", .critical)],
        "bash": [("Commande dangereuse", "\\b(?:eval|rm\\s+-rf\\s+/|curl\\s+[^|]*\\|\\s*(?:sh|bash))", .critical)],
        "zsh": [("Commande dangereuse", "\\b(?:eval|rm\\s+-rf\\s+/|curl\\s+[^|]*\\|\\s*(?:sh|bash))", .critical)],
        "pl": [("Ex\u{00E9}cution shell", "system\\(|exec\\(|`[^`]+`", .critical),
               ("Eval dynamique", "eval\\s*\\(\\s*\\$", .critical)],
        "pm": [("Ex\u{00E9}cution shell", "system\\(|exec\\(|`[^`]+`", .critical),
               ("Eval dynamique", "eval\\s*\\(\\s*\\$", .critical)],
        "sql": [("SQL dynamique", "EXECUTE\\s+IMMEDIATE|EXEC\\s*\\(@", .warning),
                ("Permissions larges", "GRANT\\s+ALL", .warning)],
    ]
}
