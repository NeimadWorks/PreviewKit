// ContextMenuActions — the 5-group context menu the brief specified.
// Kept separate from PreviewSplitView so unit tests can exercise the
// action catalogue without mounting SwiftUI.
//
// The top-level `Group` enum enumerates every slot; each slot has an
// opt-in activation predicate that the view uses to hide/show rows.

import SwiftUI
import AppKit

public enum PreviewContextAction: Sendable, Hashable {

    // Group 1 — Inspection
    case preview
    case showInHistory
    case showInVitals
    case showInSearch

    // Group 2 — Manipulation
    case openWithDefault
    case exportTo
    case exportAsZIP

    // Group 3 — Copy
    case copyName
    case copyLogicalPath
    case copyBLAKE3

    // Group 4 — Selection (multi-select)
    case exportSelection
    case computeSelectionTotal

    // Group 5 — Archive-level
    case revealInFinder
    case showArchiveInfo
}

/// Execution context the host provides when wiring the context menu.
/// `selectedItems` carries the multi-select set (empty if only one
/// item is focused); `archiveOpen` gates the archive-level rows.
public struct PreviewContextEnvironment: Sendable {
    public let focusedItem: PreviewItem
    public let selectedItems: [PreviewItem]
    public let archiveOpen: Bool
    public let hasCairnMeta: Bool

    public init(
        focusedItem: PreviewItem,
        selectedItems: [PreviewItem] = [],
        archiveOpen: Bool = false,
        hasCairnMeta: Bool = false
    ) {
        self.focusedItem = focusedItem
        self.selectedItems = selectedItems
        self.archiveOpen = archiveOpen
        self.hasCairnMeta = hasCairnMeta
    }
}

public extension PreviewContextAction {

    enum Group: Int, CaseIterable {
        case inspection = 1
        case manipulation = 2
        case copy = 3
        case selection = 4
        case archive = 5
    }

    var group: Group {
        switch self {
        case .preview, .showInHistory, .showInVitals, .showInSearch:
            return .inspection
        case .openWithDefault, .exportTo, .exportAsZIP:
            return .manipulation
        case .copyName, .copyLogicalPath, .copyBLAKE3:
            return .copy
        case .exportSelection, .computeSelectionTotal:
            return .selection
        case .revealInFinder, .showArchiveInfo:
            return .archive
        }
    }

    var displayLabel: String {
        switch self {
        case .preview:                return "Preview"
        case .showInHistory:          return "Show in History"
        case .showInVitals:           return "Show in Vitals"
        case .showInSearch:           return "Show in Search"
        case .openWithDefault:        return "Open with default app"
        case .exportTo:               return "Export to…"
        case .exportAsZIP:            return "Export as ZIP…"
        case .copyName:               return "Copy name"
        case .copyLogicalPath:        return "Copy logical path"
        case .copyBLAKE3:             return "Copy BLAKE3 hash"
        case .exportSelection:        return "Export selection"
        case .computeSelectionTotal:  return "Compute total size"
        case .revealInFinder:         return "Reveal in Finder"
        case .showArchiveInfo:        return "Show archive info"
        }
    }

    /// Predicate deciding whether the row is available for a given
    /// environment. Rows that don't apply are hidden — not disabled —
    /// to keep the menu tight.
    func isAvailable(in env: PreviewContextEnvironment) -> Bool {
        switch self {
        case .copyBLAKE3:
            return env.hasCairnMeta
        case .exportSelection, .computeSelectionTotal:
            return env.selectedItems.count > 1
        case .revealInFinder, .showArchiveInfo:
            return env.archiveOpen
        default:
            return true
        }
    }

    /// Canonical ordering used by `PreviewContextMenu`. Group order
    /// first, then per-group order.
    static var canonicalOrder: [PreviewContextAction] {
        [
            .preview, .showInHistory, .showInVitals, .showInSearch,
            .openWithDefault, .exportTo, .exportAsZIP,
            .copyName, .copyLogicalPath, .copyBLAKE3,
            .exportSelection, .computeSelectionTotal,
            .revealInFinder, .showArchiveInfo,
        ]
    }
}

// MARK: - View

/// Renders the 5-group context menu. Each group emits a trailing
/// `Divider()` unless it would produce a trailing empty group.
public struct PreviewContextMenu: View {

    public let environment: PreviewContextEnvironment
    public let onAction: (PreviewContextAction) -> Void

    public init(
        environment: PreviewContextEnvironment,
        onAction: @escaping (PreviewContextAction) -> Void
    ) {
        self.environment = environment
        self.onAction = onAction
    }

    public var body: some View {
        let groups = PreviewContextAction.Group.allCases.compactMap { group -> (PreviewContextAction.Group, [PreviewContextAction])? in
            let items = PreviewContextAction.canonicalOrder
                .filter { $0.group == group && $0.isAvailable(in: environment) }
            return items.isEmpty ? nil : (group, items)
        }
        ForEach(groups.indices, id: \.self) { i in
            let entry = groups[i]
            ForEach(entry.1, id: \.self) { action in
                Button(action.displayLabel) {
                    onAction(action)
                }
            }
            if i < groups.count - 1 {
                Divider()
            }
        }
    }
}

// MARK: - Default handlers

public enum PreviewContextHandler {

    /// Perform the "pure" actions that don't need the host's help —
    /// pasteboard writes + reveal-in-Finder for items that have a real
    /// filesystem URL. Returns `true` if the action was handled here;
    /// the caller is expected to do the rest.
    @MainActor
    public static func handleLocally(
        _ action: PreviewContextAction,
        for item: PreviewItem,
        resolvedURL: URL? = nil
    ) -> Bool {
        switch action {
        case .copyName:
            copyString(item.displayName)
            return true
        case .copyLogicalPath:
            copyString(item.logicalPath)
            return true
        case .copyBLAKE3:
            guard let meta = item.cairnMeta else { return false }
            copyString(meta.firstCommit?.shortHash ?? "")
            return true
        case .openWithDefault:
            if let url = resolvedURL {
                NSWorkspace.shared.open(url)
                return true
            }
            return false
        case .revealInFinder:
            if let url = resolvedURL {
                NSWorkspace.shared.activateFileViewerSelecting([url])
                return true
            }
            return false
        default:
            return false
        }
    }

    @MainActor
    public static func copyString(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
