import AppKit
import Foundation

/// Hard limits on what the app is ever allowed to move to the Trash.
enum SafetyGuard {
    static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path

    /// Exact paths that can never be removed (important top-level folders).
    static let protectedExact: Set<String> = {
        var s: Set<String> = [
            "/", "/Applications", "/Applications/Utilities", "/Library", "/System", "/Users",
            "/usr", "/bin", "/sbin", "/private", "/opt", "/Volumes", "/cores", home,
        ]
        let homeChildren = [
            "Library", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Public",
            "Applications", ".Trash", "Library/Caches", "Library/Logs", "Library/Application Support",
            "Library/Containers", "Library/Group Containers", "Library/Developer", "Library/Mobile Documents",
            "Library/CloudStorage", "Library/Mail", "Library/Messages", "Library/Photos",
        ]
        for c in homeChildren { s.insert(home + "/" + c) }
        return s
    }()

    /// Folders whose contents are never touched.
    static let protectedPrefixes: [String] = [
        home + "/Library/Keychains",
        home + "/Library/Preferences",
        home + "/.ssh",
        home + "/.gnupg",
        "/Applications/Utilities",
    ]

    static func isProtected(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        if protectedExact.contains(p) { return true }
        // Only things inside your home folder or /Applications can be removed.
        guard p.hasPrefix(home + "/") || p.hasPrefix("/Applications/") else { return true }
        for prefix in protectedPrefixes where p == prefix || p.hasPrefix(prefix + "/") {
            return true
        }
        return false
    }
}

enum Permissions {
    /// true = has Full Disk Access, false = doesn't.
    /// Checks several protected locations; if any that exists can't be read, access is missing.
    static func hasFullDiskAccess() -> Bool {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // The privacy database can only be opened with Full Disk Access.
        let tcc = home.appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        if fm.fileExists(atPath: tcc.path) {
            guard let handle = try? FileHandle(forReadingFrom: tcc) else { return false }
            try? handle.close()
        }

        let folders = [".Trash", "Library/Mail", "Library/Messages", "Library/Safari",
                       "Library/Containers/com.apple.stocks"]
        for p in folders {
            let url = home.appendingPathComponent(p)
            if fm.fileExists(atPath: url.path), (try? fm.contentsOfDirectory(atPath: url.path)) == nil {
                return false
            }
        }
        return true
    }

    static func openFullDiskAccessSettings() {
        let links = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
        ]
        for link in links {
            if let url = URL(string: link), NSWorkspace.shared.open(url) { return }
        }
        // Last resort: open System Settings itself.
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    /// Shows this app in Finder so it can be dragged into the Full Disk Access list.
    static func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    static var isRunningAsApp: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    /// Quits and reopens the app (macOS applies Full Disk Access after a restart).
    static func relaunch() {
        guard isRunningAsApp else { NSApp.terminate(nil); return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    /// Asks Finder to empty the Trash. Used when the app can't read ~/.Trash itself.
    static func finderEmptyTrash() {
        var error: NSDictionary?
        NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&error)
    }
}

enum IconCache {
    private static let cache = NSCache<NSString, NSImage>()

    static func icon(for url: URL) -> NSImage {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: 32, height: 32)
        cache.setObject(image, forKey: key)
        return image
    }
}
