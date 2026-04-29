// PKL10n — typed accessors over PreviewKit's Localizable.strings.
//
// Renderers never call NSLocalizedString or `String(localized:)`
// directly. They go through this enum, which guarantees:
//
//   - Every key referenced in code exists in the .strings file
//     (compile-time checked: rename a case, every callsite updates).
//   - Translations live next to each other and are reviewed as a
//     single delta in PRs.
//   - The host application's preferred locale picks the matching
//     lproj at runtime via `Bundle.module` — PreviewKit never reads
//     the host's locale settings or links any host i18n machinery.
//
// To add a string:
//   1. Add the key + EN value in Resources/en.lproj/Localizable.strings.
//   2. Add the FR translation in Resources/fr.lproj/Localizable.strings.
//   3. Add the case here under the matching namespace.
//
// Renderers use `Text(verbatim:)` with the resolved string for plain
// text, or `Text(_:bundle:)` directly when SwiftUI's automatic locale
// reactivity matters (preferred for static labels). Both paths route
// through `Bundle.module`.

import SwiftUI
import Foundation

/// Localized string accessor for PreviewKit.
///
/// `PKL10n.Section.schema` resolves to the localized "Schema" / "Schéma"
/// at the host's locale. Use the `.text` property for a SwiftUI `Text`
/// that re-renders on locale change, or `.value` for a plain `String`.
public enum PKL10n {

    // MARK: - Plumbing

    /// Resolve a key against PreviewKit's bundle. Falls back to the
    /// raw key string when the bundle lookup fails (which only happens
    /// in dev when a key was renamed but not yet retranslated).
    
    public static func string(_ key: String) -> String {
        // Bypass `String(localized:)` (which wants StaticString for the
        // comment) and go through Bundle.localizedString directly so
        // we can pass a runtime key. Falls back to the raw key when
        // the lookup fails.
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    /// `Text(_:bundle:)` shorthand — preferred at view construction
    /// time so SwiftUI re-renders on locale change.
    
    public static func text(_ key: String) -> Text {
        Text(LocalizedStringKey(key), bundle: .module)
    }

    /// Format a string with positional arguments. SwiftUI's
    /// `Text(_:tableName:bundle:)` doesn't support runtime args
    /// without `String.LocalizationValue` interpolation, so we route
    /// through `String(format:)` for variadic cases.
    
    public static func format(_ key: String, _ args: CVarArg...) -> String {
        let template = string(key)
        return String(format: template, locale: Locale.current, arguments: args)
    }

    // MARK: - Namespaces
    //
    // Each nested enum mirrors a `MARK: -` group inside the .strings
    // files. Cases use the literal key path so grep across the codebase
    // works either by key or by Swift symbol.

    public enum Common {
        public static var loading: String     { string("common.loading") }
        public static var unavailable: String { string("common.unavailable") }
        public static var modified: String    { string("common.modified") }
        public static var created: String     { string("common.created") }
        public static var size: String        { string("common.size") }
    }

    public enum KPI {
        public static var lines: String          { string("kpi.lines") }
        public static var functions: String      { string("kpi.functions") }
        public static var types: String          { string("kpi.types") }
        public static var todos: String          { string("kpi.todos") }
        public static var imports: String        { string("kpi.imports") }
        public static var tests: String          { string("kpi.tests") }
        public static var words: String          { string("kpi.words") }
        public static var paragraphs: String     { string("kpi.paragraphs") }
        public static var changes: String        { string("kpi.changes") }
        public static var comments: String       { string("kpi.comments") }
        public static var pages: String          { string("kpi.pages") }
        public static var images: String         { string("kpi.images") }
        public static var tables: String         { string("kpi.tables") }
        public static var sheets: String         { string("kpi.sheets") }
        public static var rows: String           { string("kpi.rows") }
        public static var columns: String        { string("kpi.columns") }
        public static var formulas: String       { string("kpi.formulas") }
        public static var namedRanges: String    { string("kpi.named_ranges") }
        public static var slides: String         { string("kpi.slides") }
        public static var slideLayouts: String   { string("kpi.slide_layouts") }
        public static var duration: String       { string("kpi.duration") }
        public static var codec: String          { string("kpi.codec") }
        public static var sampleRate: String     { string("kpi.sample_rate") }
        public static var bitDepth: String       { string("kpi.bit_depth") }
        public static var resolution: String     { string("kpi.resolution") }
        public static var fps: String            { string("kpi.fps") }
        public static var indexes: String        { string("kpi.indexes") }
        public static var estimatedRows: String  { string("kpi.estimated_rows") }
        public static var journal: String        { string("kpi.journal") }
        public static var version: String        { string("kpi.version") }
        public static var build: String          { string("kpi.build") }
        public static var minMacOS: String       { string("kpi.min_macos") }
        public static var architecture: String   { string("kpi.architecture") }
        public static var entries: String        { string("kpi.entries") }
        public static var compressed: String     { string("kpi.compressed") }
        public static var glyphs: String         { string("kpi.glyphs") }
        public static var weight: String         { string("kpi.weight") }
        public static var encoding: String       { string("kpi.encoding") }
        public static var gps: String            { string("kpi.gps") }
    }

    public enum Section {
        public static var schema: String       { string("section.schema") }
        public static var outline: String      { string("section.outline") }
        public static var structure: String    { string("section.structure") }
        public static var preview: String      { string("section.preview") }
        public static var attendees: String    { string("section.attendees") }
        public static var phones: String       { string("section.phones") }
        public static var emails: String       { string("section.emails") }
        public static var addresses: String    { string("section.addresses") }
        public static var frameworks: String   { string("section.frameworks") }
        public static var metadata: String     { string("section.metadata") }
        public static var history: String      { string("section.history") }
        public static var security: String     { string("section.security") }
        public static var dependencies: String { string("section.dependencies") }
        public static var health: String       { string("section.health") }
        public static var identity: String     { string("section.identity") }
        public static var exif: String         { string("section.exif") }
        public static var location: String     { string("section.location") }
        public static var histogram: String    { string("section.histogram") }
    }

    public enum Badge {
        public static var macros: String          { string("badge.macros") }
        public static var trackedChanges: String  { string("badge.tracked_changes") }
        public static var hasSpeakerNotes: String { string("badge.has_speaker_notes") }
        public static var wal: String             { string("badge.wal") }
        public static var integrityOK: String     { string("badge.integrity_ok") }
        public static var corrupted: String       { string("badge.corrupted") }
        public static var sandboxed: String       { string("badge.sandboxed") }
        public static var hardened: String        { string("badge.hardened") }
        public static var notarized: String       { string("badge.notarized") }
        public static var universal: String       { string("badge.universal") }
        public static var https: String           { string("badge.https") }
        public static var http: String            { string("badge.http") }
        public static var ipHost: String          { string("badge.ip_host") }
        public static var tracking: String        { string("badge.tracking") }
        public static var reminder: String        { string("badge.reminder") }
        public static var videoCall: String       { string("badge.video_call") }
        public static var recurring: String       { string("badge.recurring") }
        public static var encrypted: String       { string("badge.encrypted") }
        public static var hasAlpha: String        { string("badge.has_alpha") }
        public static var hdr: String             { string("badge.hdr") }
        public static var animated: String        { string("badge.animated") }
        public static var large: String           { string("badge.large") }
    }

    public enum Image {
        public enum Profile {
            public static var photo: String        { string("image.profile.photo") }
            public static var screenshot: String   { string("image.profile.screenshot") }
            public static var icon: String         { string("image.profile.icon") }
            public static var illustration: String { string("image.profile.illustration") }
        }
        public static var noEXIF: String { string("image.no_exif") }
        public static var noGPS: String  { string("image.no_gps") }
    }

    public enum Contact {
        public static var noName: String { string("contact.no_name") }
        public static func nOfM(_ n: Int, _ m: Int) -> String { format("contact.contact_n_of_m", n, m) }
    }

    public enum Calendar {
        public static var noTitle: String { string("calendar.no_title") }
        public static func nOfM(_ n: Int, _ m: Int) -> String { format("calendar.event_n_of_m", n, m) }
    }

    public enum WebShortcut {
        public static var noHost: String          { string("webshortcut.no_host") }
        public static var withoutTracking: String { string("webshortcut.without_tracking") }
    }

    public enum SQLite {
        public static var detectedApp: String { string("sqlite.detected_app") }
        public static var databaseSize: String { string("sqlite.database_size") }
        public static var bundleID: String     { string("sqlite.bundle_id") }
        public static var encoding: String     { string("sqlite.encoding") }
    }

    public enum Directory {
        public static var spectrum: String   { string("directory.spectrum") }
        public static var biggest: String    { string("directory.biggest") }
        public static var mostRecent: String { string("directory.most_recent") }
        public static var subfolders: String { string("directory.subfolders") }
    }

    public enum Binary {
        public static var magicBytes: String { string("binary.magic_bytes") }
        public static var entropy: String    { string("binary.entropy") }
        public static var misnamed: String   { string("binary.misnamed") }
    }

    public enum App {
        public static var copyright: String { string("app.copyright") }
        public static var bundleID: String  { string("app.bundle_id") }
        public static func frameworksMore(_ n: Int) -> String { format("app.frameworks_more", n) }
    }

    public enum Jupyter {
        public static var kernel: String         { string("jupyter.kernel") }
        public static var cellsCode: String      { string("jupyter.cells_code") }
        public static var cellsMarkdown: String  { string("jupyter.cells_markdown") }
        public static var libraries: String      { string("jupyter.libraries") }
    }

    public enum Source {
        public static var density: String { string("source.density") }
        public static var complex: String { string("source.complex") }
        public enum Role {
            public static var test: String       { string("source.role.test") }
            public static var ui: String         { string("source.role.ui") }
            public static var model: String      { string("source.role.model") }
            public static var service: String    { string("source.role.service") }
            public static var config: String     { string("source.role.config") }
            public static var entrypoint: String { string("source.role.entrypoint") }
            public static var fileExtension: String { string("source.role.extension") }
            public static var script: String     { string("source.role.script") }
        }
    }

    public enum Office {
        public static var noMetadata: String     { string("office.no_metadata") }
        public static var lastModifiedBy: String { string("office.last_modified_by") }
    }
}
