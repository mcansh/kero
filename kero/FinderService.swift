//
//  FinderService.swift
//  kero
//

import AppKit

/// Provides Kero's Finder service. The advertised menu item lives in
/// Info.plist; AppKit forwards matching service requests to this object.
@MainActor
final class KeroApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // AppSettings is first initialized from SwiftUI's App.init(), where
        // NSApp may not exist yet. Reapply the saved override once AppKit is
        // ready, before SwiftUI creates the first window.
        AppSettings.shared.applyAppearance()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = self
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(installFullScreenMenuItem(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        // SwiftUI finishes assembling the main menu after the launch callback.
        DispatchQueue.main.async { self.installFullScreenMenuItem(nil) }
    }

    @objc private func installFullScreenMenuItem(_ notification: Notification?) {
        guard let menu = NSApp.mainMenu?.item(withTitle: String(localized: "View"))?.submenu
        else { return }
        let action = #selector(NSWindow.toggleFullScreen(_:))
        guard !menu.items.contains(where: { $0.action == action }) else { return }

        // A nil target lets NSWindow validate the command, including its native
        // Enter/Exit Full Screen title. Reinstall if SwiftUI rebuilds the menu.
        let item = NSMenuItem(
            title: String(localized: "Enter Full Screen"),
            action: action,
            keyEquivalent: "f"
        )
        item.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(.separator())
        menu.addItem(item)
    }

    /// Opens every directory Finder placed on the service pasteboard as a
    /// project in the active Kero window.
    @objc func openInKero(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let directories = Self.directories(from: pasteboard)
        guard !directories.isEmpty else {
            error.pointee = String(localized: "Select one or more folders to open in Kero.") as NSString
            return
        }

        NSApp.activate()
        TerminalManager.openDirectories(directories)
    }

    private static func directories(from pasteboard: NSPasteboard) -> [String] {
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        var candidates = pasteboard.propertyList(forType: filenamesType) as? [String] ?? []

        if candidates.isEmpty,
           let urls = pasteboard.readObjects(
               forClasses: [NSURL.self],
               options: [.urlReadingFileURLsOnly: true]
           ) as? [URL] {
            candidates = urls.map(\.path)
        }

        if candidates.isEmpty, let text = pasteboard.string(forType: .string) {
            candidates = text.split(whereSeparator: \.isNewline).map(String.init)
        }

        let fileManager = FileManager.default
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            let path: String
            if let url = URL(string: candidate), url.isFileURL {
                path = url.path
            } else {
                path = (candidate as NSString).expandingTildeInPath
            }

            let standardized = URL(
                fileURLWithPath: path,
                isDirectory: true
            ).standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: standardized,
                isDirectory: &isDirectory
            ), isDirectory.boolValue, seen.insert(standardized).inserted else {
                return nil
            }
            return standardized
        }
    }
}
