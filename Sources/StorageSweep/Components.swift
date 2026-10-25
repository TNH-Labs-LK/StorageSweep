import AppKit
import SwiftUI

struct SafetyBadge: View {
    let safety: Safety

    var body: some View {
        Text(safety.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
            .help(safety.help)
    }

    private var color: Color {
        switch safety {
        case .safe: return .green
        case .review: return .orange
        case .keep: return .secondary
        }
    }
}

struct ItemRow: View {
    @EnvironmentObject var state: AppState
    let item: ScanItem
    var total: Int64? = nil
    var onOpen: ((ScanItem) -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { state.isSelected(item) },
                set: { state.setSelected(item, $0) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .disabled(!item.selectable)
            .help(item.selectable ? "Select to move to the Trash" : "This item is protected")

            Image(nsImage: IconCache.icon(for: item.url))
                .resizable()
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let date = item.date {
                Text("\(item.dateLabel) \(relativeDate(date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 170, alignment: .trailing)
            }

            SafetyBadge(safety: item.safety)

            if let total, total > 0 {
                SizeBar(fraction: Double(item.totalSize) / Double(total))
                    .frame(width: 60, height: 6)
            }

            Text(formatBytes(item.totalSize))
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")

            if let onOpen {
                Button {
                    onOpen(item)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.borderless)
                .disabled(!item.isFolder)
                .opacity(item.isFolder ? 1 : 0)
                .help("Open folder")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if item.isFolder, let onOpen { onOpen(item) }
        }
    }
}

struct SizeBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: max(2, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
    }
}

struct SectionHeader<Extra: View>: View {
    let section: SidebarSection
    let isScanning: Bool
    let status: String
    let summary: String?
    let scanTitle: String
    let onScan: () -> Void
    let onCancel: () -> Void
    @ViewBuilder let extra: () -> Extra

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Label(section.title, systemImage: section.icon)
                    .font(.title2.bold())
                Spacer()
                extra()
                if isScanning {
                    Button("Stop", action: onCancel)
                } else {
                    Button(scanTitle, action: onScan)
                        .buttonStyle(.borderedProminent)
                }
            }
            Text(section.blurb)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if isScanning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } else if let summary {
                Text(summary).font(.callout.weight(.medium))
            }
        }
        .padding([.horizontal, .top])
        .padding(.bottom, 10)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(title).font(.headline)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

/// A filterable, optionally grouped list of scan results with selection controls.
struct ItemListView: View {
    @EnvironmentObject var state: AppState
    let items: [ScanItem]
    var grouped = false
    var showSizeBars = false
    var emptyTitle = "Nothing to show yet"
    var emptyMessage = "Click the scan button above to start."
    var onOpen: ((ScanItem) -> Void)? = nil

    @State var filter = ""

    private var shown: [ScanItem] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.detail.localizedCaseInsensitiveContains(q) }
    }

    private struct ItemGroup: Identifiable {
        let name: String
        let items: [ScanItem]
        var id: String { name }
        var total: Int64 { items.reduce(0) { $0 + $1.totalSize } }
    }

    private var groups: [ItemGroup] {
        Dictionary(grouping: shown, by: { $0.group })
            .map { ItemGroup(name: $0.key.isEmpty ? "Other" : $0.key, items: $0.value.sorted { $0.totalSize > $1.totalSize }) }
            .sorted { $0.total > $1.total }
    }

    var body: some View {
        if items.isEmpty {
            EmptyStateView(icon: "tray", title: emptyTitle, message: emptyMessage)
        } else {
            let visible = shown
            let total = items.reduce(Int64(0)) { $0 + $1.totalSize }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("Filter", text: $filter)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    Text("\(visible.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Select All Safe") {
                        state.select(visible.filter { $0.safety == .safe })
                    }
                    .disabled(!visible.contains { $0.safety == .safe && $0.selectable })
                    Button("Select All") { state.select(visible) }
                    Button("Deselect") { state.deselect(visible) }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)

                List {
                    if grouped {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.items) { item in
                                    ItemRow(item: item, total: showSizeBars ? total : nil, onOpen: onOpen)
                                }
                            } header: {
                                HStack {
                                    Text(group.name)
                                    Spacer()
                                    Text(formatBytes(group.total)).monospacedDigit()
                                }
                            }
                        }
                    } else {
                        ForEach(visible) { item in
                            ItemRow(item: item, total: showSizeBars ? total : nil, onOpen: onOpen)
                        }
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}

struct PermissionBanner: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.title2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Give Storage Sweep Full Disk Access to see everything")
                    .font(.callout.weight(.semibold))
                Text("Without it, macOS hides some folders (Trash, Mail, some app data), so totals will be lower than what's really there. After turning it on, quit and reopen the app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("How to Turn On…") { state.showAccessGuide = true }
            Button("Open Settings") { Permissions.openFullDiskAccessSettings() }
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
    }
}

/// Step-by-step guide for granting Full Disk Access.
struct AccessGuideSheet: View {
    @EnvironmentObject var state: AppState
    @State var dontShowAgain = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow Full Disk Access").font(.title2.bold())
                    Text("So Storage Sweep can measure everything on your Mac.")
                        .foregroundStyle(.secondary)
                }
            }

            Text("Without it, macOS hides some folders (Trash, Mail, Messages, some app data), so the totals will be lower than what's really there. Storage Sweep only reads sizes. It never removes anything without asking you first.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                GuideStep(number: 1, text: "Click **Open Settings** below. Privacy & Security → Full Disk Access opens.")
                GuideStep(number: 2, text: "Turn on **Storage Sweep**. If it isn't in the list, click **+** (or drag the app in from the Finder window that opens) and choose Storage Sweep.")
                GuideStep(number: 3, text: "Enter your Mac password if asked, then come back here and click **Restart App**.")
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

            Toggle("Don't show this again when the app opens", isOn: $dontShowAgain)
                .toggleStyle(.checkbox)
                .font(.callout)

            HStack {
                Button("Not Now") {
                    UserDefaults.standard.set(dontShowAgain, forKey: "hideAccessGuide")
                    state.showAccessGuide = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Restart App") { Permissions.relaunch() }
                Button("Open Settings") {
                    Permissions.openFullDiskAccessSettings()
                    if Permissions.isRunningAsApp { Permissions.revealAppInFinder() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 540)
    }
}

private struct GuideStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.callout.bold())
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))
            Text(LocalizedStringKey(text))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SelectionBar: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
            Text("\(state.effectiveSelection.count) selected · \(formatBytes(state.selectedSize))")
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            Spacer()
            Button("Clear Selection") { state.clearSelection() }
            Button(role: .destructive) {
                state.showConfirm = true
            } label: {
                Label("Move to Trash…", systemImage: "trash")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(state.isTrashing)
        }
        .padding(12)
        .background(.bar)
    }
}

struct ConfirmTrashSheet: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        let urls = state.effectiveSelection
        let appCount = urls.filter { !(state.extrasIndex[$0] ?? []).isEmpty }.count
        VStack(alignment: .leading, spacing: 12) {
            Text("Move \(urls.count) item\(urls.count == 1 ? "" : "s") to the Trash?")
                .font(.title3.bold())
            Text("You can put them back from the Trash until you empty it. The space is freed when the Trash is emptied.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List(urls, id: \.self) { url in
                HStack(spacing: 8) {
                    Image(nsImage: IconCache.icon(for: url))
                        .resizable()
                        .frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.names[url] ?? url.lastPathComponent).lineLimit(1)
                        Text(DiskScanner.displayPath(url))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text(formatBytes(state.sizeIndex[url] ?? 0)).monospacedDigit()
                }
            }
            .frame(minHeight: 220)

            if appCount > 0 {
                Text("Apps are removed together with their data in your Library folder (settings, caches, saved state). Quit them first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text("Total: \(formatBytes(state.selectedSize))")
                    .font(.headline)
                    .monospacedDigit()
                Spacer()
                Button("Cancel") { state.showConfirm = false }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    state.showConfirm = false
                    state.moveSelectionToTrash()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding(20)
        .frame(width: 580, height: 480)
    }
}
