import Foundation

/// How safe it is to remove an item.
enum Safety: Int, Comparable {
    case safe = 0, review = 1, keep = 2

    static func < (a: Safety, b: Safety) -> Bool { a.rawValue < b.rawValue }

    var label: String {
        switch self {
        case .safe: return "Safe"
        case .review: return "Review"
        case .keep: return "Keep"
        }
    }

    var help: String {
        switch self {
        case .safe: return "Rebuilt or re-downloaded automatically when needed."
        case .review: return "Could matter to you. Check before removing."
        case .keep: return "Part of macOS or protected. Can't be removed here."
        }
    }
}

/// One file, folder or app found by a scan.
struct ScanItem: Identifiable, Hashable {
    let url: URL
    var name: String
    var detail: String
    var group: String = ""
    var size: Int64
    var safety: Safety
    var isFolder: Bool = false
    var date: Date? = nil
    var dateLabel: String = "Modified"
    /// Extra paths removed together with this item (e.g. an app's data folders).
    var extras: [URL] = []
    var extrasSize: Int64 = 0

    var id: URL { url }
    var totalSize: Int64 { size + extrasSize }
    var selectable: Bool { safety != .keep && !SafetyGuard.isProtected(url) }
}

struct ScanResult {
    var items: [ScanItem] = []
    var isScanning = false
    var status = ""
    var scannedAt: Date? = nil

    var totalSize: Int64 { items.reduce(0) { $0 + $1.totalSize } }
    var safeSize: Int64 { items.filter { $0.safety == .safe }.reduce(0) { $0 + $1.totalSize } }
}

struct DuplicateGroup: Identifiable {
    let id: String
    let size: Int64
    var files: [ScanItem]
    var wasted: Int64 { size * Int64(max(files.count - 1, 0)) }
}

struct TrashOutcome: Identifiable {
    let id = UUID()
    let moved: Int
    let freed: Int64
    let failures: [String]
}

struct DiskInfo {
    var name: String
    var total: Int64
    var available: Int64
    var used: Int64 { max(total - available, 0) }
    var fraction: Double { total > 0 ? Double(used) / Double(total) : 0 }

    static func current() -> DiskInfo {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
        ]
        let v = try? home.resourceValues(forKeys: keys)
        let total = Int64(v?.volumeTotalCapacity ?? 0)
        var available = v?.volumeAvailableCapacityForImportantUsage ?? 0
        if available <= 0 { available = Int64(v?.volumeAvailableCapacity ?? 0) }
        return DiskInfo(name: v?.volumeLocalizedName ?? "Macintosh HD", total: total, available: available)
    }
}

enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case overview, cleanup, projects, largeFiles, installers, duplicates, applications, explorer

    var id: SidebarSection { self }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .cleanup: return "Caches & Junk"
        case .projects: return "Project Dependencies"
        case .largeFiles: return "Large Files"
        case .installers: return "Installers"
        case .duplicates: return "Duplicates"
        case .applications: return "Applications"
        case .explorer: return "Space Explorer"
        }
    }

    var icon: String {
        switch self {
        case .overview: return "internaldrive"
        case .cleanup: return "sparkles"
        case .projects: return "shippingbox"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .installers: return "opticaldiscdrive"
        case .duplicates: return "doc.on.doc"
        case .applications: return "square.grid.2x2"
        case .explorer: return "folder"
        }
    }

    var blurb: String {
        switch self {
        case .overview:
            return "See how full your disk is and scan for things you can clean up."
        case .cleanup:
            return "App caches, logs and developer caches. Most of these are rebuilt automatically when needed."
        case .projects:
            return "node_modules, Python virtual environments and build folders inside your projects. Reinstall them with npm install, pip install and similar commands."
        case .largeFiles:
            return "Big files in your home folder, biggest first. Old videos, disk images and archives are common finds."
        case .installers:
            return "Disk images and installer packages (.dmg, .pkg, .iso, .xip). You don't need them once the app is installed."
        case .duplicates:
            return "Files with exactly the same content in more than one place (1 MB and larger)."
        case .applications:
            return "Installed apps, with the date you last opened them. Removing an app also removes its data in your Library."
        case .explorer:
            return "Browse any folder and see which subfolders take the most space."
        }
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func relativeDate(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f.localizedString(for: date, relativeTo: Date())
}
