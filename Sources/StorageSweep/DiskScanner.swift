import AppKit
import CryptoKit
import Foundation

/// Shared between a running scan and the UI: cancellation flag + throttled status messages.
final class ScanControl {
    private let lock = NSLock()
    private var cancelled = false
    private var lastReport = Date.distantPast
    private let onStatus: (String) -> Void

    init(onStatus: @escaping (String) -> Void) {
        self.onStatus = onStatus
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func report(_ message: @autoclosure () -> String) {
        lock.lock()
        let now = Date()
        let shouldSend = now.timeIntervalSince(lastReport) > 0.15
        if shouldSend { lastReport = now }
        lock.unlock()
        if shouldSend { onStatus(message()) }
    }
}

private struct KnownLocation {
    let path: String
    let name: String
    let note: String
    let safety: Safety
    let group: String
    var expandChildren = false
}

enum DiskScanner {
    static let fm = FileManager.default
    static var home: URL { fm.homeDirectoryForCurrentUser.standardizedFileURL }

    private static let sizeKeys: [URLResourceKey] = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
    ]
    private static let sizeKeySet = Set(sizeKeys)

    // MARK: - Basic helpers

    /// Space a file or folder actually takes on disk.
    static func allocatedSize(_ url: URL, ctl: ScanControl? = nil) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let rv = try? url.resourceValues(forKeys: keys) else { return 0 }
        if rv.isSymbolicLink == true { return 0 }
        if rv.isDirectory != true {
            return Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
        }
        guard let en = fm.enumerator(at: url, includingPropertiesForKeys: sizeKeys, options: [], errorHandler: { _, _ in true }) else {
            return 0
        }
        var total: Int64 = 0
        var count = 0
        while let file = en.nextObject() as? URL {
            count += 1
            if count % 4096 == 0, ctl?.isCancelled == true { break }
            guard let v = try? file.resourceValues(forKeys: sizeKeySet), v.isRegularFile == true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func children(_ url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey], options: [])) ?? []
    }

    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    static func isPackage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
    }

    static func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func displayPath(_ url: URL) -> String {
        let p = url.standardizedFileURL.path
        let h = home.path
        if p == h { return "~" }
        if p.hasPrefix(h + "/") { return "~" + p.dropFirst(h.count) }
        return p
    }

    /// The first folder under home ("Desktop", "Documents"…), used to group results.
    static func topFolder(_ url: URL) -> String {
        let p = url.standardizedFileURL.path
        let h = home.path
        guard p.hasPrefix(h + "/") else { return "Other" }
        let parts = p.dropFirst(h.count + 1).split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : "Home folder"
    }

    /// Measures many folders in parallel and turns each into a ScanItem.
    static func measure(_ urls: [URL], ctl: ScanControl, make: (URL, Int64) -> ScanItem?) -> [ScanItem] {
        let lock = NSLock()
        var out: [ScanItem] = []
        var done = 0
        DispatchQueue.concurrentPerform(iterations: urls.count) { i in
            if ctl.isCancelled { return }
            let url = urls[i]
            let size = allocatedSize(url, ctl: ctl)
            let item = make(url, size)
            lock.lock()
            if let item { out.append(item) }
            done += 1
            let finished = done
            lock.unlock()
            ctl.report("Measured \(finished) of \(urls.count): \(url.lastPathComponent)")
        }
        return out.sorted { $0.totalSize > $1.totalSize }
    }

    // MARK: - Caches & junk

    private static let knownLocations: [KnownLocation] = [
        KnownLocation(path: "Library/Caches", name: "", note: "App cache, rebuilt automatically", safety: .safe, group: "App caches", expandChildren: true),
        KnownLocation(path: "Library/Logs", name: "", note: "Log files", safety: .safe, group: "Logs", expandChildren: true),
        KnownLocation(path: ".cache", name: "", note: "Developer tool cache, re-downloaded when needed", safety: .safe, group: "Developer caches", expandChildren: true),
        KnownLocation(path: ".npm/_cacache", name: "npm cache", note: "Re-downloads packages when needed", safety: .safe, group: "Developer caches"),
        KnownLocation(path: ".yarn/berry/cache", name: "Yarn cache", note: "Re-downloads packages when needed", safety: .safe, group: "Developer caches"),
        KnownLocation(path: "Library/pnpm/store", name: "pnpm store", note: "Re-downloads packages when needed", safety: .safe, group: "Developer caches"),
        KnownLocation(path: ".gradle/caches", name: "Gradle build cache", note: "Re-downloaded on the next build", safety: .safe, group: "Developer caches"),
        KnownLocation(path: ".gradle/wrapper/dists", name: "Downloaded Gradle versions", note: "Projects download the version they need again", safety: .safe, group: "Developer caches"),
        KnownLocation(path: ".gradle/daemon", name: "Gradle daemon files", note: "Logs and temporary files", safety: .safe, group: "Developer caches"),
        KnownLocation(path: ".m2/repository", name: "Maven downloads", note: "Re-downloaded on the next build", safety: .safe, group: "Developer caches"),
        KnownLocation(path: ".pub-cache", name: "Dart & Flutter packages", note: "Restored by flutter pub get", safety: .safe, group: "Developer caches"),
        KnownLocation(path: ".cocoapods/repos", name: "CocoaPods specs", note: "Re-downloaded by pod install", safety: .safe, group: "Developer caches"),
        KnownLocation(path: ".cargo/registry", name: "Rust crate cache", note: "Re-downloaded by cargo", safety: .safe, group: "Developer caches"),
        KnownLocation(path: "go/pkg/mod", name: "Go module cache", note: "Re-downloaded by go build", safety: .safe, group: "Developer caches"),
        KnownLocation(path: "Library/Developer/Xcode/DerivedData", name: "Xcode build data", note: "Rebuilt the next time you build", safety: .safe, group: "Xcode"),
        KnownLocation(path: "Library/Developer/Xcode/iOS DeviceSupport", name: "iOS device support files", note: "Re-created when you connect a device", safety: .safe, group: "Xcode"),
        KnownLocation(path: "Library/Developer/CoreSimulator/Caches", name: "Simulator caches", note: "Rebuilt automatically", safety: .safe, group: "Xcode"),
        KnownLocation(path: "Library/Developer/Xcode/Archives", name: "Xcode archives", note: "Old app builds. Keep any you may need to re-upload or debug", safety: .review, group: "Xcode"),
        KnownLocation(path: "Library/Developer/CoreSimulator/Devices", name: "iOS Simulators", note: "Simulator devices and their data", safety: .review, group: "Xcode"),
        KnownLocation(path: ".android/avd", name: "Android emulators", note: "Your emulator devices and their data", safety: .review, group: "Android"),
        KnownLocation(path: "Library/Android/sdk/system-images", name: "Android system images", note: "Re-download from Android Studio's SDK Manager", safety: .review, group: "Android"),
        KnownLocation(path: ".ollama/models", name: "Ollama AI models", note: "Re-download with ollama pull", safety: .review, group: "AI models"),
        KnownLocation(path: "Library/Application Support/MobileSync/Backup", name: "", note: "iPhone or iPad backup. Only remove if you have another backup", safety: .review, group: "Device backups", expandChildren: true),
        KnownLocation(path: "Library/Containers/com.apple.mail/Data/Library/Mail Downloads", name: "Mail attachment copies", note: "Copies of attachments you opened", safety: .safe, group: "Mail"),
    ]

    private static func friendlyName(_ folderName: String) -> String {
        if folderName.contains("."),
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: folderName) {
            return appURL.deletingPathExtension().lastPathComponent
        }
        return folderName
    }

    static func cleanupItems(ctl: ScanControl) -> [ScanItem] {
        struct Target { let url: URL; let name: String; let note: String; let safety: Safety; let group: String }
        var targets: [Target] = []
        for loc in knownLocations {
            let base = home.appendingPathComponent(loc.path)
            guard fm.fileExists(atPath: base.path) else { continue }
            if loc.expandChildren {
                for child in children(base) {
                    let n = child.lastPathComponent
                    if n.hasPrefix("com.apple.") || n.hasPrefix(".") { continue }
                    var safety = loc.safety
                    var note = loc.note
                    let lower = n.lowercased()
                    if lower.contains("huggingface") || lower == "torch" || lower == "whisper" {
                        safety = .review
                        note = "Downloaded AI models, re-downloaded when needed"
                    }
                    targets.append(Target(url: child.standardizedFileURL, name: friendlyName(n), note: note, safety: safety, group: loc.group))
                }
            } else {
                targets.append(Target(url: base.standardizedFileURL, name: loc.name, note: loc.note, safety: loc.safety, group: loc.group))
            }
        }
        let info = Dictionary(targets.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
        ctl.report("Measuring \(info.count) locations…")
        return measure(Array(info.keys), ctl: ctl) { url, size in
            guard size >= 1_000_000, let t = info[url] else { return nil }
            return ScanItem(url: url, name: t.name, detail: "\(displayPath(url)) · \(t.note)", group: t.group,
                            size: size, safety: t.safety, isFolder: isDirectory(url), date: modificationDate(url))
        }
    }

    // MARK: - Project dependency folders

    private static func dependencyNote(_ dir: URL) -> String? {
        let name = dir.lastPathComponent
        let parent = dir.deletingLastPathComponent()
        func has(_ file: String) -> Bool { fm.fileExists(atPath: parent.appendingPathComponent(file).path) }
        switch name {
        case "node_modules":
            return "Node.js packages. Restore with npm install"
        case ".venv", "venv", "env":
            return fm.fileExists(atPath: dir.appendingPathComponent("pyvenv.cfg").path)
                ? "Python virtual environment. Recreate with python3 -m venv" : nil
        case ".next", ".nuxt", ".turbo", ".parcel-cache", ".svelte-kit":
            return "Web build cache. Rebuilt on the next build"
        case ".dart_tool":
            return "Dart tool cache. Restored by flutter pub get"
        case "Pods":
            return has("Podfile") ? "CocoaPods. Restore with pod install" : nil
        case ".gradle":
            return (has("build.gradle") || has("build.gradle.kts") || has("settings.gradle") || has("settings.gradle.kts"))
                ? "Gradle project cache" : nil
        case "build":
            return (has("build.gradle") || has("build.gradle.kts") || has("pubspec.yaml"))
                ? "Build output. Rebuilt on the next build" : nil
        case "target":
            return (has("Cargo.toml") || has("pom.xml")) ? "Build output. Rebuilt on the next build" : nil
        default:
            return nil
        }
    }

    static func dependencyFolders(root: URL, ctl: ScanControl) -> [ScanItem] {
        let libraryPath = home.appendingPathComponent("Library").path
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants], errorHandler: { _, _ in true }) else {
            return []
        }
        var found: [URL: String] = [:]
        while let url = en.nextObject() as? URL {
            if ctl.isCancelled { return [] }
            guard let rv = try? url.resourceValues(forKeys: Set(keys)), rv.isDirectory == true, rv.isSymbolicLink != true else { continue }
            let name = url.lastPathComponent
            if url.path == libraryPath || name == ".Trash" {
                en.skipDescendants()
                continue
            }
            if let note = dependencyNote(url) {
                found[url.standardizedFileURL] = note
                en.skipDescendants()
                continue
            }
            if name.hasPrefix(".") {
                en.skipDescendants()
                continue
            }
            ctl.report("Looking in \(displayPath(url))")
        }
        return measure(Array(found.keys), ctl: ctl) { url, size in
            guard size >= 1_000_000, let note = found[url] else { return nil }
            let project = url.deletingLastPathComponent()
            return ScanItem(url: url, name: "\(project.lastPathComponent) › \(url.lastPathComponent)",
                            detail: "\(displayPath(project)) · \(note)", group: topFolder(url),
                            size: size, safety: .safe, isFolder: true,
                            date: modificationDate(project), dateLabel: "Project changed")
        }
    }

    // MARK: - Walking user files (large files, installers, duplicates)

    private static let skipFolderNames: Set<String> = ["node_modules", "venv", "Pods", "DerivedData"]
    private static let libraryPackageExtensions: Set<String> = [
        "photoslibrary", "photolibrary", "migratedphotolibrary", "imovielibrary", "fcpbundle",
        "tvlibrary", "musiclibrary", "logicx", "band", "xcarchive",
    ]
    private static let walkKeys: [URLResourceKey] = [
        .isRegularFileKey, .isDirectoryKey, .isPackageKey, .fileSizeKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey,
    ]

    /// Visits regular files under the given folders. Skips ~/Library, hidden folders,
    /// dependency folders and the inside of packages.
    static func walkUserFiles(roots: [URL], ctl: ScanControl,
                              visit: (URL, URLResourceValues) -> Void,
                              visitPackage: ((URL) -> Void)? = nil) {
        let keySet = Set(walkKeys)
        let libraryPath = home.appendingPathComponent("Library").path
        for root in roots {
            guard fm.fileExists(atPath: root.path),
                  let en = fm.enumerator(at: root, includingPropertiesForKeys: walkKeys,
                                         options: [.skipsHiddenFiles, .skipsPackageDescendants],
                                         errorHandler: { _, _ in true }) else { continue }
            while let url = en.nextObject() as? URL {
                if ctl.isCancelled { return }
                guard let rv = try? url.resourceValues(forKeys: keySet) else { continue }
                if rv.isDirectory == true {
                    if url.path == libraryPath || skipFolderNames.contains(url.lastPathComponent) {
                        en.skipDescendants()
                        continue
                    }
                    if rv.isPackage == true { visitPackage?(url) }
                    ctl.report("Scanning \(displayPath(url))")
                    continue
                }
                if rv.isRegularFile == true { visit(url, rv) }
            }
        }
    }

    static func largeFiles(minSize: Int64, ctl: ScanControl) -> [ScanItem] {
        var out: [ScanItem] = []
        walkUserFiles(roots: [home], ctl: ctl, visit: { url, rv in
            let size = Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
            guard size >= minSize else { return }
            out.append(ScanItem(url: url.standardizedFileURL, name: url.lastPathComponent,
                                detail: displayPath(url.deletingLastPathComponent()), group: topFolder(url),
                                size: size, safety: .review, date: rv.contentModificationDate))
        }, visitPackage: { url in
            guard libraryPackageExtensions.contains(url.pathExtension.lowercased()) else { return }
            let size = allocatedSize(url, ctl: ctl)
            guard size >= minSize else { return }
            out.append(ScanItem(url: url.standardizedFileURL, name: url.lastPathComponent,
                                detail: "\(displayPath(url.deletingLastPathComponent())) · Library (contains many files)",
                                group: topFolder(url), size: size, safety: .review, date: modificationDate(url)))
        })
        return out.sorted { $0.size > $1.size }
    }

    private static let installerExtensions: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]

    static func installers(ctl: ScanControl) -> [ScanItem] {
        let roots = ["Downloads", "Desktop", "Documents"].map { home.appendingPathComponent($0) }
        var out: [ScanItem] = []
        walkUserFiles(roots: roots, ctl: ctl, visit: { url, rv in
            guard installerExtensions.contains(url.pathExtension.lowercased()) else { return }
            let size = Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
            out.append(ScanItem(url: url.standardizedFileURL, name: url.lastPathComponent,
                                detail: "\(displayPath(url.deletingLastPathComponent())) · Installer file",
                                group: topFolder(url), size: size, safety: .safe, date: rv.contentModificationDate))
        }, visitPackage: { url in
            // .pkg installers can be folder packages too.
            guard ["pkg", "mpkg"].contains(url.pathExtension.lowercased()) else { return }
            out.append(ScanItem(url: url.standardizedFileURL, name: url.lastPathComponent,
                                detail: "\(displayPath(url.deletingLastPathComponent())) · Installer package",
                                group: topFolder(url), size: allocatedSize(url, ctl: ctl), safety: .safe,
                                date: modificationDate(url)))
        })
        return out.sorted { $0.size > $1.size }
    }

    // MARK: - Duplicates

    private static func sha256(_ url: URL, limit: Int?, ctl: ScanControl) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var readBytes = 0
        while true {
            if ctl.isCancelled { return nil }
            let chunkSize = limit.map { min(1 << 20, $0 - readBytes) } ?? (1 << 20)
            if chunkSize <= 0 { break }
            guard let data = try? handle.read(upToCount: chunkSize), !data.isEmpty else { break }
            hasher.update(data: data)
            readBytes += data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func duplicates(minSize: Int64 = 1_000_000, ctl: ScanControl) -> [DuplicateGroup] {
        struct Candidate { let url: URL; let allocated: Int64; let date: Date? }
        var bySize: [Int64: [Candidate]] = [:]
        walkUserFiles(roots: [home], ctl: ctl, visit: { url, rv in
            let logical = Int64(rv.fileSize ?? 0)
            let allocated = Int64(rv.totalFileAllocatedSize ?? rv.fileAllocatedSize ?? 0)
            // allocated == 0 means a cloud placeholder that isn't downloaded.
            guard logical >= minSize, allocated > 0 else { return }
            bySize[logical, default: []].append(Candidate(url: url.standardizedFileURL, allocated: allocated, date: rv.contentModificationDate))
        })
        let sameSize = bySize.filter { $0.value.count > 1 }
        let totalFiles = sameSize.values.reduce(0) { $0 + $1.count }
        var checked = 0
        var groups: [DuplicateGroup] = []
        let quickLimit = 64 * 1024

        for (size, files) in sameSize {
            if ctl.isCancelled { return [] }
            var byQuick: [String: [Candidate]] = [:]
            for f in files {
                checked += 1
                ctl.report("Comparing file \(checked) of \(totalFiles): \(f.url.lastPathComponent)")
                if let h = sha256(f.url, limit: quickLimit, ctl: ctl) { byQuick[h, default: []].append(f) }
            }
            for (quick, same) in byQuick where same.count > 1 {
                var byFull: [String: [Candidate]] = [:]
                if size <= Int64(quickLimit) {
                    byFull[quick] = same
                } else {
                    for f in same {
                        ctl.report("Verifying \(f.url.lastPathComponent)")
                        if let h = sha256(f.url, limit: nil, ctl: ctl) { byFull[h, default: []].append(f) }
                    }
                }
                for (hash, dup) in byFull where dup.count > 1 {
                    let items = dup
                        .sorted { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
                        .map { c in
                            ScanItem(url: c.url, name: c.url.lastPathComponent,
                                     detail: displayPath(c.url.deletingLastPathComponent()),
                                     size: c.allocated, safety: .review, date: c.date)
                        }
                    groups.append(DuplicateGroup(id: hash, size: dup[0].allocated, files: items))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    // MARK: - Applications

    private static func appDataFolders(bundleID: String, appName: String) -> [URL] {
        let lib = home.appendingPathComponent("Library")
        let paths = [
            "Application Support/\(bundleID)", "Application Support/\(appName)",
            "Caches/\(bundleID)", "Caches/\(appName)",
            "Containers/\(bundleID)",
            "HTTPStorages/\(bundleID)", "WebKit/\(bundleID)",
            "Logs/\(appName)", "Logs/\(bundleID)",
            "Preferences/\(bundleID).plist",
            "Saved Application State/\(bundleID).savedState",
            "Cookies/\(bundleID).binarycookies",
        ]
        var seen = Set<String>()
        return paths.compactMap { rel in
            let url = lib.appendingPathComponent(rel).standardizedFileURL
            guard !seen.contains(url.path), fm.fileExists(atPath: url.path), !SafetyGuard.isProtected(url) else { return nil }
            seen.insert(url.path)
            return url
        }
    }

    static func applications(ctl: ScanControl) -> [ScanItem] {
        var apps: [URL] = []
        for dir in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            for child in children(dir) {
                if child.pathExtension == "app" {
                    apps.append(child.standardizedFileURL)
                } else if child.lastPathComponent != "Utilities", isDirectory(child) {
                    apps += children(child).filter { $0.pathExtension == "app" }.map { $0.standardizedFileURL }
                }
            }
        }
        return measure(apps, ctl: ctl) { url, size in
            let bundleID = Bundle(url: url)?.bundleIdentifier ?? ""
            let name = url.deletingPathExtension().lastPathComponent
            let isApple = bundleID.hasPrefix("com.apple.")
            let lastUsed = NSMetadataItem(url: url)?.value(forAttribute: "kMDItemLastUsedDate") as? Date
            var detail = displayPath(url.deletingLastPathComponent())
            var extras: [URL] = []
            var extrasSize: Int64 = 0
            if isApple {
                detail += " · Comes with macOS"
            } else if !bundleID.isEmpty {
                extras = appDataFolders(bundleID: bundleID, appName: name)
                extrasSize = extras.reduce(0) { $0 + allocatedSize($1, ctl: ctl) }
                if extrasSize > 0 { detail += " · App \(formatBytes(size)) + data \(formatBytes(extrasSize))" }
            }
            if lastUsed == nil && !isApple { detail += " · No record of being opened" }
            return ScanItem(url: url, name: name, detail: detail, group: "", size: size,
                            safety: isApple ? .keep : .review, isFolder: false,
                            date: lastUsed, dateLabel: "Last opened", extras: extras, extrasSize: extrasSize)
        }
    }

    // MARK: - Space explorer

    static func folderContents(_ dir: URL, ctl: ScanControl) -> [ScanItem] {
        let kids = children(dir).map { $0.standardizedFileURL }
        return measure(kids, ctl: ctl) { url, size in
            let folder = isDirectory(url) && !isPackage(url)
            let kind = folder ? "Folder" : (url.pathExtension == "app" ? "App" : "File")
            return ScanItem(url: url, name: url.lastPathComponent, detail: kind, size: size,
                            safety: .review, isFolder: folder, date: modificationDate(url))
        }
    }

    // MARK: - Trash

    /// Size of ~/.Trash, or nil if macOS won't let the app look inside.
    static func trashSize() -> Int64? {
        let trash = home.appendingPathComponent(".Trash")
        guard (try? fm.contentsOfDirectory(atPath: trash.path)) != nil else { return nil }
        return allocatedSize(trash)
    }
}
