import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        // A plain two-column layout (instead of NavigationSplitView) so the sidebar
        // and content always stay below the title bar.
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 230)
            Divider()
            VStack(spacing: 0) {
                if !state.hasFullDiskAccess {
                    PermissionBanner()
                    Divider()
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                if !state.selected.isEmpty {
                    Divider()
                    SelectionBar()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Storage Sweep — \((state.section ?? .overview).title)")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !state.hasFullDiskAccess {
                    Button {
                        state.showAccessGuide = true
                    } label: {
                        Label("Full Disk Access", systemImage: "lock.shield")
                    }
                    .help("Allow Full Disk Access to see everything")
                }
            }
        }
        .sheet(isPresented: $state.showConfirm) {
            ConfirmTrashSheet().environmentObject(state)
        }
        .sheet(isPresented: $state.showAccessGuide) {
            AccessGuideSheet().environmentObject(state)
        }
        .alert(item: $state.lastOutcome) { outcome in
            var message = "\(formatBytes(outcome.freed)) will be freed when you empty the Trash."
            if !outcome.failures.isEmpty {
                message += "\n\nCouldn't move: " + outcome.failures.joined(separator: ", ")
                    + ". Make sure the app is quit, or remove it in Finder."
            }
            return Alert(
                title: Text("Moved \(outcome.moved) item\(outcome.moved == 1 ? "" : "s") to the Trash"),
                message: Text(message),
                primaryButton: .destructive(Text("Empty Trash Now")) { state.emptyTrash() },
                secondaryButton: .cancel(Text("Later"))
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshEnvironment()
        }
    }

    @ViewBuilder private var detail: some View {
        switch state.section ?? .overview {
        case .overview: OverviewView()
        case .cleanup: CleanupView()
        case .projects: ProjectsView()
        case .largeFiles: LargeFilesView()
        case .installers: InstallersView()
        case .duplicates: DuplicatesView()
        case .applications: ApplicationsView()
        case .explorer: ExplorerView()
        }
    }
}

// MARK: - Overview

struct OverviewView: View {
    @EnvironmentObject var state: AppState

    private let cardSections: [SidebarSection] = [.cleanup, .projects, .largeFiles, .installers, .applications, .duplicates]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Label("Overview", systemImage: "internaldrive").font(.title2.bold())
                    Spacer()
                    Button {
                        state.scanEverything()
                    } label: {
                        Label("Scan Everything", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.anyScanning)
                }

                DiskCard(disk: state.disk)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 14)], spacing: 14) {
                    ForEach(cardSections) { section in
                        SummaryCard(section: section)
                    }
                    TrashCard()
                }

                Text("Scan Everything checks caches, project folders, large files, installers and apps. Duplicates take longer, so they're scanned separately. Nothing is removed until you select items and confirm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
    }
}

struct DiskCard: View {
    let disk: DiskInfo

    private var color: Color {
        if disk.fraction > 0.9 { return .red }
        if disk.fraction > 0.75 { return .orange }
        return .accentColor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "internaldrive.fill").foregroundStyle(color)
                Text(disk.name).font(.headline)
                Spacer()
                Text("\(Int((disk.fraction * 100).rounded()))% full")
                    .font(.headline)
                    .foregroundStyle(color)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(color).frame(width: geo.size.width * disk.fraction)
                }
            }
            .frame(height: 14)
            HStack {
                Text("\(formatBytes(disk.used)) used of \(formatBytes(disk.total))")
                Spacer()
                Text("\(formatBytes(disk.available)) available").bold()
            }
            .font(.callout)
            .monospacedDigit()
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15)))
    }
}

struct SummaryCard: View {
    @EnvironmentObject var state: AppState
    let section: SidebarSection

    private var result: ScanResult {
        switch section {
        case .cleanup: return state.cleanup
        case .projects: return state.projects
        case .largeFiles: return state.largeFiles
        case .installers: return state.installers
        case .applications: return state.applications
        case .duplicates: return state.duplicateScan
        default: return ScanResult()
        }
    }

    private var headline: String {
        if result.isScanning { return "Scanning…" }
        guard result.scannedAt != nil else { return "Not scanned" }
        if section == .duplicates { return formatBytes(state.duplicateWasted) }
        return formatBytes(result.totalSize)
    }

    private var subline: String {
        if result.isScanning { return result.status }
        guard result.scannedAt != nil else { return "Click to open and scan" }
        switch section {
        case .duplicates:
            return "\(state.duplicates.count) groups of identical files"
        case .applications:
            return "\(result.items.count) apps installed"
        default:
            let safe = result.safeSize
            return safe > 0 ? "\(formatBytes(safe)) safe to remove · \(result.items.count) items" : "\(result.items.count) items"
        }
    }

    var body: some View {
        Button {
            state.section = section
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: section.icon).foregroundStyle(Color.accentColor)
                    Text(section.title).font(.headline)
                    Spacer()
                    if result.isScanning { ProgressView().controlSize(.small) }
                }
                Text(headline)
                    .font(.title2.bold())
                    .monospacedDigit()
                Text(subline)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct TrashCard: View {
    @EnvironmentObject var state: AppState
    @State var confirmEmpty = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "trash").foregroundStyle(Color.accentColor)
                Text("Trash").font(.headline)
                Spacer()
                if state.isEmptyingTrash { ProgressView().controlSize(.small) }
            }
            Text(state.trashSize.map { formatBytes($0) } ?? "Unknown")
                .font(.title2.bold())
                .monospacedDigit()
            HStack {
                Text(state.trashSize == nil ? "Needs Full Disk Access to measure" : "Freed when you empty the Trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                if state.trashSize == nil {
                    Button("Grant Access…") { state.showAccessGuide = true }
                        .controlSize(.small)
                }
                Button("Empty…") { confirmEmpty = true }
                    .controlSize(.small)
                    .disabled(state.isEmptyingTrash || state.trashSize == 0)
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.15)))
        .alert("Empty the Trash?", isPresented: $confirmEmpty) {
            Button("Empty Trash", role: .destructive) { state.emptyTrash() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Everything in the Trash will be permanently deleted. This can't be undone.")
        }
    }
}

// MARK: - Result screens

private func summaryText(_ result: ScanResult, noun: String = "items") -> String? {
    guard result.scannedAt != nil else { return nil }
    let safe = result.safeSize
    var text = "Found \(result.items.count) \(noun) using \(formatBytes(result.totalSize))"
    if safe > 0 && safe != result.totalSize { text += " (\(formatBytes(safe)) marked safe)" }
    return text
}

struct CleanupView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(section: .cleanup, isScanning: state.cleanup.isScanning, status: state.cleanup.status,
                          summary: summaryText(state.cleanup), scanTitle: "Scan",
                          onScan: { state.scanCleanup() }, onCancel: { state.cancel(.cleanup) }) { EmptyView() }
            ItemListView(items: state.cleanup.items, grouped: true,
                         emptyMessage: "Click Scan to look for caches, logs and other files that can be rebuilt.")
        }
    }
}

struct ProjectsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(section: .projects, isScanning: state.projects.isScanning, status: state.projects.status,
                          summary: summaryText(state.projects, noun: "folders"), scanTitle: "Scan",
                          onScan: { state.scanProjects() }, onCancel: { state.cancel(.projects) }) {
                Text(DiskScanner.displayPath(state.projectsRoot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Change Folder…") {
                    if let url = chooseFolder(startingAt: state.projectsRoot) {
                        state.projectsRoot = url
                        state.scanProjects()
                    }
                }
            }
            ItemListView(items: state.projects.items, grouped: true,
                         emptyMessage: "Click Scan to find node_modules, Python environments and build folders in your projects.")
        }
    }
}

struct LargeFilesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(section: .largeFiles, isScanning: state.largeFiles.isScanning, status: state.largeFiles.status,
                          summary: summaryText(state.largeFiles, noun: "files"), scanTitle: "Scan",
                          onScan: { state.scanLargeFiles() }, onCancel: { state.cancel(.largeFiles) }) {
                Picker("Bigger than", selection: $state.largeThresholdMB) {
                    Text("100 MB").tag(100)
                    Text("250 MB").tag(250)
                    Text("500 MB").tag(500)
                    Text("1 GB").tag(1000)
                    Text("5 GB").tag(5000)
                }
                .frame(width: 190)
            }
            ItemListView(items: state.largeFiles.items, grouped: true,
                         emptyMessage: "Click Scan to find big files in your home folder.")
        }
    }
}

struct InstallersView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(section: .installers, isScanning: state.installers.isScanning, status: state.installers.status,
                          summary: summaryText(state.installers, noun: "installers"), scanTitle: "Scan",
                          onScan: { state.scanInstallers() }, onCancel: { state.cancel(.installers) }) { EmptyView() }
            ItemListView(items: state.installers.items, grouped: true,
                         emptyMessage: "Click Scan to look for installer files in Downloads, Desktop and Documents.")
        }
    }
}

struct ApplicationsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(section: .applications, isScanning: state.applications.isScanning, status: state.applications.status,
                          summary: summaryText(state.applications, noun: "apps"), scanTitle: "Scan",
                          onScan: { state.scanApplications() }, onCancel: { state.cancel(.applications) }) { EmptyView() }
            ItemListView(items: state.applications.items,
                         emptyMessage: "Click Scan to list your apps by size and when you last opened them.")
        }
    }
}

struct DuplicatesView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(section: .duplicates, isScanning: state.duplicateScan.isScanning, status: state.duplicateScan.status,
                          summary: state.duplicateScan.scannedAt == nil ? nil
                              : "\(state.duplicates.count) groups · \(formatBytes(state.duplicateWasted)) taken by extra copies",
                          scanTitle: "Find Duplicates",
                          onScan: { state.scanDuplicates() }, onCancel: { state.cancel(.duplicates) }) {
                Button("Select Extra Copies") { state.autoSelectDuplicates() }
                    .disabled(state.duplicates.isEmpty)
                    .help("Keeps the oldest copy in each group and selects the others")
            }
            if state.duplicates.isEmpty {
                EmptyStateView(icon: "doc.on.doc",
                               title: state.duplicateScan.scannedAt == nil ? "Nothing to show yet" : "No duplicates found",
                               message: state.duplicateScan.scannedAt == nil
                                   ? "Click Find Duplicates to compare files in your home folder. This can take a few minutes."
                                   : "No identical files of 1 MB or more were found.")
            } else {
                List {
                    ForEach(state.duplicates) { group in
                        Section {
                            ForEach(group.files) { item in
                                ItemRow(item: item)
                            }
                        } header: {
                            HStack {
                                Text("\(group.files.count) copies · \(formatBytes(group.size)) each")
                                Spacer()
                                Text("\(formatBytes(group.wasted)) extra").monospacedDigit()
                            }
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}

struct ExplorerView: View {
    @EnvironmentObject var state: AppState

    private var crumbs: [URL] {
        var list: [URL] = []
        var url = state.explorerPath
        while true {
            list.insert(url, at: 0)
            let parent = url.deletingLastPathComponent()
            if parent.path == url.path || list.count > 40 { break }
            url = parent
        }
        return list
    }

    var body: some View {
        VStack(spacing: 0) {
            SectionHeader(section: .explorer, isScanning: state.explorer.isScanning, status: state.explorer.status,
                          summary: state.explorer.scannedAt == nil ? nil
                              : "\(formatBytes(state.explorer.totalSize)) in \(DiskScanner.displayPath(state.explorerPath))",
                          scanTitle: "Refresh",
                          onScan: { state.openExplorer(state.explorerPath, force: true) },
                          onCancel: { state.cancel(.explorer) }) {
                Button {
                    state.explorerUp()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .help("Go up one folder")
                .disabled(state.explorerPath.path == "/")
                Button("Home") { state.openExplorer(DiskScanner.home) }
                Button("Choose Folder…") {
                    if let url = chooseFolder(startingAt: state.explorerPath) { state.openExplorer(url) }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(crumbs, id: \.self) { url in
                        Button(url.path == "/" ? "/" : url.lastPathComponent) { state.openExplorer(url) }
                            .buttonStyle(.link)
                        if url != crumbs.last {
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 8)

            ItemListView(items: state.explorer.items, showSizeBars: true,
                         emptyTitle: state.explorer.isScanning ? "Measuring…" : "Empty folder",
                         emptyMessage: state.explorer.isScanning ? "Adding up folder sizes. Big folders take a moment."
                             : "Nothing here, or macOS didn't allow access.",
                         onOpen: { state.openExplorer($0.url) })
        }
        .onAppear {
            if state.explorer.scannedAt == nil && !state.explorer.isScanning {
                state.openExplorer(state.explorerPath)
            }
        }
    }
}

func chooseFolder(startingAt url: URL) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.directoryURL = url
    panel.prompt = "Choose"
    return panel.runModal() == .OK ? panel.url : nil
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SidebarSection.allCases) { section in
                    SidebarRow(section: section, isSelected: (state.section ?? .overview) == section)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
    }
}

private struct SidebarRow: View {
    @EnvironmentObject var state: AppState
    let section: SidebarSection
    let isSelected: Bool
    @State var hovering = false

    var body: some View {
        Button {
            state.section = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .frame(width: 20)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                Text(section.title)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let badge = state.badgeText(for: section) {
                    badge
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor : (hovering ? Color.secondary.opacity(0.15) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
