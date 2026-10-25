import AppKit
import SwiftUI

/// All app state. Mutated only on the main thread; scans run on background queues.
final class AppState: ObservableObject {
    @Published var section: SidebarSection? = .overview
    @Published var disk = DiskInfo.current()
    @Published var hasFullDiskAccess: Bool = Permissions.hasFullDiskAccess()
    @Published var showAccessGuide = false
    @Published var trashSize: Int64? = nil
    @Published var isEmptyingTrash = false

    @Published var cleanup = ScanResult()
    @Published var projects = ScanResult()
    @Published var largeFiles = ScanResult()
    @Published var installers = ScanResult()
    @Published var applications = ScanResult()
    @Published var explorer = ScanResult()
    @Published var duplicateScan = ScanResult()
    @Published var duplicates: [DuplicateGroup] = []

    @Published var explorerPath: URL = DiskScanner.home
    @Published var projectsRoot: URL = DiskScanner.home
    @Published var largeThresholdMB: Int = 250

    @Published var selected: Set<URL> = []
    @Published var showConfirm = false
    @Published var isTrashing = false
    @Published var lastOutcome: TrashOutcome? = nil

    private(set) var sizeIndex: [URL: Int64] = [:]
    private(set) var names: [URL: String] = [:]
    private(set) var extrasIndex: [URL: [URL]] = [:]
    private var controls: [SidebarSection: ScanControl] = [:]
    private var explorerCache: [URL: [ScanItem]] = [:]

    init() {
        refreshTrashSize()
        // On launch, explain how to grant Full Disk Access if it's missing.
        if !hasFullDiskAccess && !UserDefaults.standard.bool(forKey: "hideAccessGuide") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, !self.hasFullDiskAccess else { return }
                self.showAccessGuide = true
            }
        }
    }

    // MARK: - Environment

    func refreshEnvironment() {
        disk = DiskInfo.current()
        let access = Permissions.hasFullDiskAccess()
        if access != hasFullDiskAccess { hasFullDiskAccess = access }
        if access && showAccessGuide { showAccessGuide = false }
        refreshTrashSize()
    }

    func refreshTrashSize() {
        DispatchQueue.global(qos: .utility).async {
            let size = DiskScanner.trashSize()
            DispatchQueue.main.async { [weak self] in self?.trashSize = size }
        }
    }

    var anyScanning: Bool {
        cleanup.isScanning || projects.isScanning || largeFiles.isScanning || installers.isScanning
            || applications.isScanning || duplicateScan.isScanning
    }

    func badgeText(for section: SidebarSection) -> Text? {
        let result: ScanResult
        switch section {
        case .cleanup: result = cleanup
        case .projects: result = projects
        case .largeFiles: result = largeFiles
        case .installers: result = installers
        case .applications: result = applications
        case .duplicates:
            guard duplicateScan.scannedAt != nil else { return nil }
            return Text(formatBytes(duplicateWasted))
        default: return nil
        }
        guard result.scannedAt != nil else { return nil }
        return Text(formatBytes(result.totalSize))
    }

    var duplicateWasted: Int64 { duplicates.reduce(0) { $0 + $1.wasted } }

    // MARK: - Scanning

    private func start(_ section: SidebarSection,
                       _ keyPath: ReferenceWritableKeyPath<AppState, ScanResult>,
                       onDone: (([ScanItem]) -> Void)? = nil,
                       work: @escaping (ScanControl) -> [ScanItem]) {
        controls[section]?.cancel()
        let ctl = ScanControl { [weak self] message in
            DispatchQueue.main.async { self?[keyPath: keyPath].status = message }
        }
        controls[section] = ctl
        self[keyPath: keyPath].isScanning = true
        self[keyPath: keyPath].status = "Starting…"

        DispatchQueue.global(qos: .userInitiated).async {
            let items = work(ctl)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.controls[section] === ctl else { return }
                var result = self[keyPath: keyPath]
                if !ctl.isCancelled {
                    result.items = items
                    result.scannedAt = Date()
                    onDone?(items)
                }
                result.isScanning = false
                result.status = ""
                self[keyPath: keyPath] = result
                self.controls[section] = nil
                self.disk = DiskInfo.current()
            }
        }
    }

    func cancel(_ section: SidebarSection) {
        controls[section]?.cancel()
        controls[section] = nil
        switch section {
        case .cleanup: cleanup.isScanning = false
        case .projects: projects.isScanning = false
        case .largeFiles: largeFiles.isScanning = false
        case .installers: installers.isScanning = false
        case .applications: applications.isScanning = false
        case .explorer: explorer.isScanning = false
        case .duplicates: duplicateScan.isScanning = false
        case .overview: break
        }
    }

    func scanEverything() {
        scanCleanup()
        scanProjects()
        scanLargeFiles()
        scanInstallers()
        scanApplications()
        refreshTrashSize()
    }

    func scanCleanup() {
        start(.cleanup, \.cleanup) { DiskScanner.cleanupItems(ctl: $0) }
    }

    func scanProjects() {
        let root = projectsRoot
        start(.projects, \.projects) { DiskScanner.dependencyFolders(root: root, ctl: $0) }
    }

    func scanLargeFiles() {
        let minSize = Int64(largeThresholdMB) * 1_000_000
        start(.largeFiles, \.largeFiles) { DiskScanner.largeFiles(minSize: minSize, ctl: $0) }
    }

    func scanInstallers() {
        start(.installers, \.installers) { DiskScanner.installers(ctl: $0) }
    }

    func scanApplications() {
        start(.applications, \.applications) { DiskScanner.applications(ctl: $0) }
    }

    func scanDuplicates() {
        controls[.duplicates]?.cancel()
        let ctl = ScanControl { [weak self] message in
            DispatchQueue.main.async { self?.duplicateScan.status = message }
        }
        controls[.duplicates] = ctl
        duplicateScan.isScanning = true
        duplicateScan.status = "Starting…"
        DispatchQueue.global(qos: .userInitiated).async {
            let groups = DiskScanner.duplicates(ctl: ctl)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.controls[.duplicates] === ctl else { return }
                if !ctl.isCancelled {
                    self.duplicates = groups
                    self.duplicateScan.scannedAt = Date()
                }
                self.duplicateScan.isScanning = false
                self.duplicateScan.status = ""
                self.controls[.duplicates] = nil
            }
        }
    }

    func openExplorer(_ url: URL, force: Bool = false) {
        let url = url.standardizedFileURL
        explorerPath = url
        if !force, let cached = explorerCache[url] {
            cancel(.explorer)
            explorer.items = cached
            explorer.scannedAt = Date()
            return
        }
        explorer.items = []
        start(.explorer, \.explorer, onDone: { [weak self] items in
            self?.explorerCache[url] = items
        }) { DiskScanner.folderContents(url, ctl: $0) }
    }

    func explorerUp() {
        let parent = explorerPath.deletingLastPathComponent()
        if parent.path != explorerPath.path { openExplorer(parent) }
    }

    // MARK: - Selection

    func isSelected(_ item: ScanItem) -> Bool { selected.contains(item.url) }

    func setSelected(_ item: ScanItem, _ on: Bool) {
        if on {
            guard item.selectable else { return }
            sizeIndex[item.url] = item.totalSize
            names[item.url] = item.name
            if !item.extras.isEmpty { extrasIndex[item.url] = item.extras }
            selected.insert(item.url)
        } else {
            selected.remove(item.url)
        }
    }

    func select(_ items: [ScanItem]) {
        var copy = selected
        for item in items where item.selectable {
            sizeIndex[item.url] = item.totalSize
            names[item.url] = item.name
            if !item.extras.isEmpty { extrasIndex[item.url] = item.extras }
            copy.insert(item.url)
        }
        selected = copy
    }

    func deselect(_ items: [ScanItem]) {
        selected.subtract(items.map { $0.url })
    }

    func clearSelection() { selected.removeAll() }

    /// Selected items, minus anything inside another selected folder (so nothing is counted twice).
    var effectiveSelection: [URL] {
        let sorted = selected.sorted { $0.path.count < $1.path.count }
        var keep: [URL] = []
        for url in sorted where !keep.contains(where: { url.path.hasPrefix($0.path + "/") }) {
            keep.append(url)
        }
        return keep.sorted { (sizeIndex[$0] ?? 0) > (sizeIndex[$1] ?? 0) }
    }

    var selectedSize: Int64 {
        effectiveSelection.reduce(0) { $0 + (sizeIndex[$1] ?? 0) }
    }

    func autoSelectDuplicates() {
        // Keep the oldest copy in each group, select the rest.
        select(duplicates.flatMap { Array($0.files.dropFirst()) })
    }

    // MARK: - Trash

    func moveSelectionToTrash() {
        let roots = effectiveSelection.filter { !SafetyGuard.isProtected($0) }
        guard !roots.isEmpty else { return }
        var urls = roots
        for root in roots {
            urls += (extrasIndex[root] ?? []).filter {
                FileManager.default.fileExists(atPath: $0.path) && !SafetyGuard.isProtected($0)
            }
        }
        isTrashing = true
        NSWorkspace.shared.recycle(urls) { [weak self] _, error in
            DispatchQueue.main.async {
                self?.finishTrash(requested: urls, roots: roots, error: error)
            }
        }
    }

    private func finishTrash(requested: [URL], roots: [URL], error: Error?) {
        let fm = FileManager.default
        let gone = requested.filter { !fm.fileExists(atPath: $0.path) }
        let gonePaths = gone.map { $0.standardizedFileURL.path }
        let goneRoots = roots.filter { !fm.fileExists(atPath: $0.path) }
        let freed = goneRoots.reduce(Int64(0)) { $0 + (sizeIndex[$1] ?? 0) }

        func isGone(_ url: URL) -> Bool {
            let p = url.standardizedFileURL.path
            return gonePaths.contains { p == $0 || p.hasPrefix($0 + "/") }
        }
        func prune(_ result: inout ScanResult) { result.items.removeAll { isGone($0.url) } }

        prune(&cleanup)
        prune(&projects)
        prune(&largeFiles)
        prune(&installers)
        prune(&applications)
        prune(&explorer)
        duplicates = duplicates.compactMap { group in
            var g = group
            g.files.removeAll { isGone($0.url) }
            return g.files.count > 1 ? g : nil
        }
        explorerCache.removeAll()

        selected.subtract(goneRoots)
        var failures = roots.filter { fm.fileExists(atPath: $0.path) }.map { names[$0] ?? $0.lastPathComponent }
        if let error, !failures.isEmpty {
            failures.append(error.localizedDescription)
        }
        isTrashing = false
        lastOutcome = TrashOutcome(moved: goneRoots.count, freed: freed, failures: failures)
        refreshEnvironment()
    }

    func emptyTrash() {
        isEmptyingTrash = true
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            let trash = DiskScanner.home.appendingPathComponent(".Trash")
            var needsFinder = false
            if let items = try? fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil, options: []) {
                for item in items {
                    do { try fm.removeItem(at: item) } catch { needsFinder = true }
                }
            } else {
                needsFinder = true
            }
            DispatchQueue.main.async { [weak self] in
                if needsFinder { Permissions.finderEmptyTrash() }
                self?.isEmptyingTrash = false
                self?.refreshEnvironment()
            }
        }
    }
}
