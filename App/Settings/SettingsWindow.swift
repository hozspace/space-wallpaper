import AppKit
import SwiftUI

/// Opened from the menu bar and thrown away on closing, so the wallpaper stays light.
@MainActor
final class SettingsWindow: NSWindow {
    private static let size = NSSize(width: 760, height: 310)

    init(content: SettingsView) {
        Retro.registerFont()
        super.init(contentRect: NSRect(origin: .zero, size: Self.size),
                   styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        title = "Settings"
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        backgroundColor = NSColor(Retro.screen)
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: content)
        center()
    }
}
