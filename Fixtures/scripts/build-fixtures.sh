#!/bin/bash
# build-fixtures.sh — build the PreviewKit fixture set.
#
# Creates one minimal-but-valid sample per renderer family in
# Fixtures/files/. Idempotent — overwrites in place. No external
# downloads; everything is generated from system tools (sqlite3,
# /usr/bin/openssl, /usr/bin/sips, etc.) or written inline.
#
# Run:  bash Fixtures/scripts/build-fixtures.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/Fixtures/files"
mkdir -p "$OUT"

# ---------------------------------------------------------------- text

# Markdown
cat > "$OUT/sample.md" <<'EOF'
# PreviewKit Markdown fixture

A short Markdown sample used by `MarkdownRenderer` tests. Includes a
heading, a sub-heading, a paragraph, a fenced code block, a list, and a
link.

## Section two

Some prose with **bold**, *italic*, and `inline code`.

```swift
let preview = "kit"
print(preview)
```

- bullet one
- bullet two
- bullet three

[Neimad](https://neimad.fr)
EOF

# Swift source (for SourceCodeRenderer)
cat > "$OUT/sample.swift" <<'EOF'
// sample.swift — PreviewKit SourceCode fixture
import Foundation

/// A typed identifier for things that can be previewed.
public struct PreviewID: Hashable {
    public let raw: String
    public init(_ raw: String) { self.raw = raw }
}

public protocol Previewable {
    var id: PreviewID { get }
    func describe() -> String
}

public final class SamplePreview: Previewable {
    public let id: PreviewID
    public init(id: PreviewID) { self.id = id }
    public func describe() -> String { "sample(\(id.raw))" }
}

// TODO: cover edge cases
// FIXME: handle empty inputs

extension SamplePreview {
    public static let preset = SamplePreview(id: PreviewID("preset"))
}
EOF

# JSON
cat > "$OUT/sample.json" <<'EOF'
{
  "name": "PreviewKit",
  "version": "1.0.0",
  "platforms": ["macOS"],
  "supported_kinds": 30,
  "renderers": {
    "documents": ["pdf", "markdown", "office"],
    "code": ["swift", "python", "typescript"],
    "data": ["json", "yaml", "csv", "sqlite"]
  },
  "active": true
}
EOF

# YAML
cat > "$OUT/sample.yaml" <<'EOF'
name: PreviewKit
version: 1.0.0
platforms:
  - macOS
renderers:
  documents:
    - pdf
    - markdown
  code:
    - swift
    - python
EOF

# CSV
cat > "$OUT/sample.csv" <<'EOF'
name,kind,priority,active
PDF,document,0,true
SourceCode,code,0,true
SQLite,data,0,true
Calendar,document,0,true
Contact,document,0,true
EOF

# Calendar (.ics, RFC 5545)
cat > "$OUT/sample.ics" <<'EOF'
BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Neimad//PreviewKit Fixture//EN
BEGIN:VEVENT
UID:fixture-001@previewkit
DTSTAMP:20260429T120000Z
DTSTART:20260501T140000Z
DTEND:20260501T150000Z
SUMMARY:PreviewKit fixture meeting
LOCATION:Zoom
DESCRIPTION:A short event used by CalendarRenderer tests.
URL:https://zoom.us/j/12345
RRULE:FREQ=WEEKLY;BYDAY=MO
ATTENDEE;CN=Alice;PARTSTAT=ACCEPTED:mailto:alice@example.com
ATTENDEE;CN=Bob;PARTSTAT=TENTATIVE:mailto:bob@example.com
BEGIN:VALARM
ACTION:DISPLAY
TRIGGER:-PT15M
END:VALARM
END:VEVENT
END:VCALENDAR
EOF

# vCard (.vcf, RFC 6350)
cat > "$OUT/sample.vcf" <<'EOF'
BEGIN:VCARD
VERSION:3.0
FN:Camille Dupont
N:Dupont;Camille;;;
ORG:Neimad
TITLE:Engineer
TEL;TYPE=CELL:+33 6 12 34 56 78
TEL;TYPE=WORK:+33 1 23 45 67 89
EMAIL;TYPE=WORK:camille@neimad.fr
EMAIL;TYPE=HOME:camille@example.com
ADR;TYPE=WORK:;;42 rue de la Paix;Paris;;75002;France
END:VCARD
EOF

# Web shortcut (.webloc, XML plist)
cat > "$OUT/sample.webloc" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyLists-1.0.dtd">
<plist version="1.0">
<dict>
    <key>URL</key>
    <string>https://neimad.fr/?utm_source=fixture&amp;ref=test</string>
</dict>
</plist>
EOF

# .url (Windows-style INI shortcut)
cat > "$OUT/sample.url" <<'EOF'
[InternetShortcut]
URL=https://github.com/NeimadWorks/PreviewKit
EOF

# Patch / diff
cat > "$OUT/sample.patch" <<'EOF'
diff --git a/sample.swift b/sample.swift
index abc1234..def5678 100644
--- a/sample.swift
+++ b/sample.swift
@@ -1,5 +1,6 @@
 import Foundation

+// New imports
 public struct PreviewID: Hashable {
-    public let raw: String
+    public let raw: String  // now stable
 }
EOF

# Plain text / log
cat > "$OUT/sample.txt" <<'EOF'
PreviewKit text fixture
-----------------------
A short plain-text file.

Used by:
  - the binary renderer fallback test
  - generic text inspection tests

Each renderer should treat this as ASCII / UTF-8 with line endings = LF.
EOF

# Plist (Apple property list, XML form)
cat > "$OUT/sample.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyLists-1.0.dtd">
<plist version="1.0">
<dict>
    <key>BundleName</key><string>PreviewKit</string>
    <key>Version</key><string>1.0.0</string>
    <key>SupportedKinds</key><integer>30</integer>
    <key>Active</key><true/>
</dict>
</plist>
EOF

# XML
cat > "$OUT/sample.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<previewkit>
    <name>PreviewKit</name>
    <version>1.0.0</version>
    <renderers>
        <renderer kind="pdf"/>
        <renderer kind="markdown"/>
        <renderer kind="sqlite"/>
    </renderers>
</previewkit>
EOF

# ---------------------------------------------------------------- binary

# SQLite (Safari-history shape, so AppSignatureRegistry detects it)
SQLITE_PATH="$OUT/sample.sqlite"
rm -f "$SQLITE_PATH"
sqlite3 "$SQLITE_PATH" <<'EOF'
CREATE TABLE history_items (id INTEGER PRIMARY KEY, url TEXT, domain TEXT);
CREATE TABLE history_visits (id INTEGER PRIMARY KEY, history_item INTEGER, visit_time REAL);
INSERT INTO history_items (url, domain) VALUES
  ('https://neimad.fr', 'neimad.fr'),
  ('https://github.com/NeimadWorks/PreviewKit', 'github.com'),
  ('https://apple.com', 'apple.com');
INSERT INTO history_visits (history_item, visit_time) VALUES
  (1, 762100000.0),
  (2, 762100100.0),
  (3, 762100200.0);
CREATE INDEX idx_visit_time ON history_visits(visit_time);
PRAGMA journal_mode = WAL;
PRAGMA quick_check;
EOF

# PNG — generated from /usr/bin/sips against an existing system asset
SYSTEM_TIFF="/System/Library/CoreServices/DefaultDesktop.heic"
if [ -f "$SYSTEM_TIFF" ]; then
    sips -s format png "$SYSTEM_TIFF" --out "$OUT/sample.png" --resampleHeightWidthMax 256 >/dev/null 2>&1 || true
fi
# Fallback PNG: a 4×4 red square if sips didn't produce one.
if [ ! -f "$OUT/sample.png" ]; then
    /usr/bin/printf "\x89PNG\r\n\x1a\n" > "$OUT/sample.png"
    /usr/bin/printf "\x00\x00\x00\rIHDR\x00\x00\x00\x04\x00\x00\x00\x04\x08\x02\x00\x00\x00\x26\x93\x09\x29" >> "$OUT/sample.png"
    /usr/bin/printf "\x00\x00\x00\x16IDATx\x9cc\xfc\xff\xff?\x03\x00\x00\x00\x00\x18\x00\x01\x05\xfe\x02\xfe\x9b\x9a\xee\xf4" >> "$OUT/sample.png"
    /usr/bin/printf "\x00\x00\x00\x00IEND\xaeB\x60\x82" >> "$OUT/sample.png"
fi

# JPEG
if [ -f "$OUT/sample.png" ]; then
    sips -s format jpeg "$OUT/sample.png" --out "$OUT/sample.jpg" >/dev/null 2>&1 || true
fi

# HEIC — copy from system if accessible (any DefaultDesktop)
HEIC_SOURCE=$(ls /System/Library/CoreServices/DefaultDesktop.heic 2>/dev/null | head -1)
if [ -n "${HEIC_SOURCE:-}" ] && [ -f "$HEIC_SOURCE" ]; then
    sips -s format heic "$HEIC_SOURCE" --out "$OUT/sample.heic" --resampleHeightWidthMax 512 >/dev/null 2>&1 || true
fi

# Tiny zip archive
ZIP_TMP="$(mktemp -d)"
cp "$OUT/sample.txt" "$OUT/sample.md" "$OUT/sample.swift" "$ZIP_TMP/"
(cd "$ZIP_TMP" && zip -q "$OUT/sample.zip" sample.txt sample.md sample.swift)
rm -rf "$ZIP_TMP"

# Tiny tarball
TAR_TMP="$(mktemp -d)"
cp "$OUT/sample.txt" "$OUT/sample.md" "$TAR_TMP/"
(cd "$TAR_TMP" && tar -cf "$OUT/sample.tar" sample.txt sample.md)
gzip -kf "$OUT/sample.tar"
rm -rf "$TAR_TMP"

# Font — copy a system TTF
SYSTEM_FONT="/System/Library/Fonts/SFNS.ttf"
if [ -f "$SYSTEM_FONT" ]; then
    cp "$SYSTEM_FONT" "$OUT/sample.ttf"
fi
# Fallback: any TTF in /Library/Fonts
if [ ! -f "$OUT/sample.ttf" ]; then
    SYSTEM_FONT_FALLBACK=$(ls /System/Library/Fonts/*.ttf 2>/dev/null | head -1)
    [ -f "$SYSTEM_FONT_FALLBACK" ] && cp "$SYSTEM_FONT_FALLBACK" "$OUT/sample.ttf"
fi

# Symlink the system Calculator app for AppBundle tests
APPLINK="$OUT/sample.app"
rm -f "$APPLINK"
if [ -d "/System/Applications/Calculator.app" ]; then
    ln -s "/System/Applications/Calculator.app" "$APPLINK"
fi

# Audio — system sound .aiff
SYSTEM_AIFF="/System/Library/Sounds/Submarine.aiff"
if [ -f "$SYSTEM_AIFF" ]; then
    cp "$SYSTEM_AIFF" "$OUT/sample.aiff"
fi

# GPG signature ASCII (a literal armored block — not cryptographically valid,
# but the renderer's job is to display the structure, not verify).
cat > "$OUT/sample.asc" <<'EOF'
-----BEGIN PGP SIGNATURE-----

iQEzBAEBCAAdFiEEYWFkZjEzNDU2Nzg5MGFiY2RlZjAxMjM0NTY3ODkwYWJjZGVm
BAUCYxFcAAoJEH//examplesignaturefornoharmwhatsoever//1234567890ab
cdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789+/==
-----END PGP SIGNATURE-----
EOF

# Mobile-provision (text snippet only — real ones are CMS-signed plists)
cat > "$OUT/sample.mobileprovision" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyLists-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AppIDName</key>          <string>PreviewKit Fixture</string>
    <key>TeamName</key>            <string>NeimadWorks</string>
    <key>TeamIdentifier</key>      <array><string>FIXTURE001</string></array>
    <key>CreationDate</key>        <date>2026-04-29T12:00:00Z</date>
    <key>ExpirationDate</key>      <date>2027-04-29T12:00:00Z</date>
    <key>UUID</key>                <string>00000000-0000-0000-0000-FIXTURE0000</string>
    <key>Version</key>             <integer>1</integer>
</dict>
</plist>
EOF

echo
echo "Built fixtures into: $OUT"
ls -lh "$OUT" | awk 'NR>1 {printf "  %s  %s\n", $5, $9}'
