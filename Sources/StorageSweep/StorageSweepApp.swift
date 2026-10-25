import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSWindow.allowsAutomaticWindowTabbing = false
        NSApp.activate(ignoringOtherApps: true)
        // Make sure the window opens at a comfortable size on any screen.
        DispatchQueue.main.async {
            for window in NSApp.windows where window.isVisible {
                window.contentMinSize = NSSize(width: 860, height: 540)
                let visible = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
                let width = min(max(window.frame.width, 1100), visible.width - 40)
                let height = min(max(window.frame.height, 720), visible.height - 40)
                if width > 0, height > 0 {
                    window.setFrame(NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2,
                                           width: width, height: height), display: true)
                }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct StorageSweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup("Storage Sweep") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 860, maxWidth: .infinity, minHeight: 540, maxHeight: .infinity)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Scan") {
                Button("Scan Everything") { state.scanEverything() }
                    .keyboardShortcut("r", modifiers: [.command])
                Button("Find Duplicates") { state.scanDuplicates() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Divider()
                Button("Full Disk Access…") { state.showAccessGuide = true }
            }
        }
    }
}
