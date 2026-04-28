// PreviewExport — NSSavePanel / NSOpenPanel wrappers.
//
// PreviewSplitView exposes `onExport` / `onExportSelection` closures
// but the host rarely wants to re-implement the panel dance. These
// helpers pick a destination URL + copy the bytes or temp file into
// place. All surface area is main-actor (NSSavePanel is main-only).

import Foundation
import AppKit

public enum PreviewExport {

    /// Prompt for a single-file save destination, then copy the
    /// provided bytes. The destination filename defaults to the
    /// item's display name. Returns the chosen URL on success.
    @MainActor
    @discardableResult
    public static func saveSingle(
        data: Data,
        suggestedName: String,
        extensionHint: String? = nil
    ) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        if let ext = extensionHint, !ext.isEmpty {
            panel.allowedContentTypes = []
            panel.allowsOtherFileTypes = true
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            presentError(error, title: "Couldn't save file")
            return nil
        }
    }

    /// Same, but copy from a source URL instead of writing bytes.
    @MainActor
    @discardableResult
    public static func saveSingle(
        sourceURL: URL,
        suggestedName: String
    ) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let dest = panel.url else { return nil }
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: sourceURL, to: dest)
            return dest
        } catch {
            presentError(error, title: "Couldn't save file")
            return nil
        }
    }

    /// Prompt for a directory, then copy multiple items into it.
    /// Returns the chosen directory URL — callers can walk the return
    /// value to verify what landed.
    @MainActor
    @discardableResult
    public static func saveSelection(
        items: [(name: String, data: Data)]
    ) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Export Here"
        guard panel.runModal() == .OK, let dir = panel.url else { return nil }
        for item in items {
            let target = dir.appendingPathComponent(item.name)
            do {
                try item.data.write(to: target, options: .atomic)
            } catch {
                presentError(error, title: "Couldn't save \(item.name)")
            }
        }
        return dir
    }

    @MainActor
    private static func presentError(_ error: Error, title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "\(error)"
        alert.alertStyle = .warning
        alert.runModal()
    }
}
