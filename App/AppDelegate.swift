import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let frameRates = [30, 60]
    private static let defaultFrameRate = 30
    private static let frameRateKey = "frameRate"
    private static let speeds: [(name: String, scale: Double)] = [("Crawl", 0.5), ("Slow", 0.8), ("Medium", 1), ("Fast", 1.5)]
    private static let defaultSpeed = "Slow"
    private static let speedKey = "speed"
    private var isPreview = false
    private var systemSleeping = false
    private var displaySleeping = false
    private var sessionInactive = false

    private var window: WallpaperWindow?
    private var settingsWindow: SettingsWindow?
    private var statusItem: NSStatusItem?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private var savedFrameRate: Int {
        let saved = UserDefaults.standard.integer(forKey: Self.frameRateKey)
        return Self.frameRates.contains(saved) ? saved : Self.defaultFrameRate
    }

    private var savedSpeed: (name: String, scale: Double) {
        let saved = UserDefaults.standard.string(forKey: Self.speedKey) ?? Self.defaultSpeed
        return Self.speeds.first { $0.name == saved } ?? Self.speeds[1]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else {
            NSLog("SpaceWallpaper: no screen to draw on")
            NSApp.terminate(nil)
            return
        }
        let args = ProcessInfo.processInfo.arguments
        isPreview = args.contains("--preview")
        func value(after flag: String) -> String? {
            guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
            return args[index + 1]
        }
        let seed = isPreview ? value(after: "--seed").flatMap(UInt64.init) : nil
        let seconds = isPreview ? max(0, value(after: "--seconds").flatMap(Double.init) ?? 0) : 0
        if isPreview {
            NSApp.setActivationPolicy(.regular)
            let menu = NSMenu(), item = NSMenuItem(), appMenu = NSMenu()
            appMenu.addItem(NSMenuItem(title: "Quit Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
            item.submenu = appMenu
            menu.addItem(item)
            NSApp.mainMenu = menu
        }
        window = WallpaperWindow(screen: screen, framesPerSecond: savedFrameRate,
            flightSpeed: savedSpeed.scale, preview: isPreview, seed: seed, seconds: seconds)
        statusItem = makeStatusItem()
        let centre = NSWorkspace.shared.notificationCenter
        centre.addObserver(self, selector: #selector(displayDidSleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        centre.addObserver(self, selector: #selector(displayDidWake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        centre.addObserver(self, selector: #selector(systemWillSleep), name: NSWorkspace.willSleepNotification, object: nil)
        centre.addObserver(self, selector: #selector(systemDidWake), name: NSWorkspace.didWakeNotification, object: nil)
        centre.addObserver(self, selector: #selector(sessionDidResign), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        centre.addObserver(self, selector: #selector(sessionDidBecomeActive), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        if isPreview { NSApp.activate(ignoringOtherApps: true) }
        if isPreview, args.contains("--settings") { openSettings() }
    }

    /// The wallpaper ignores clicks and has no Dock icon, so this is the only way to reach it.
    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Space Wallpaper")
        let menu = NSMenu()
        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Space Wallpaper", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        item.menu = menu
        return item
    }

    @objc private func openSettings() {
        let settings = settingsWindow ?? SettingsWindow(content: SettingsView(
            speeds: Self.speeds.map(\.name), frameRates: Self.frameRates,
            speed: savedSpeed.name, frameRate: savedFrameRate,
            onSpeed: { [weak self] in self?.chooseSpeed($0) },
            onFrameRate: { [weak self] in self?.chooseFrameRate($0) }))
        settings.delegate = self
        settingsWindow = settings
        settings.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? SettingsWindow === settingsWindow { settingsWindow = nil }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { isPreview }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func systemWillSleep(_ notification: Notification) { systemSleeping = true; updatePause() }
    @objc private func systemDidWake(_ notification: Notification) { systemSleeping = false; updatePause() }
    @objc private func displayDidSleep(_ notification: Notification) { displaySleeping = true; updatePause() }
    @objc private func displayDidWake(_ notification: Notification) { displaySleeping = false; updatePause() }
    @objc private func sessionDidResign(_ notification: Notification) { sessionInactive = true; updatePause() }
    @objc private func sessionDidBecomeActive(_ notification: Notification) { sessionInactive = false; updatePause() }
    private func updatePause() { window?.setPaused(systemSleeping || displaySleeping || sessionInactive) }

    private func chooseSpeed(_ name: String) {
        UserDefaults.standard.set(name, forKey: Self.speedKey)
        window?.setFlightSpeed(savedSpeed.scale)
    }

    private func chooseFrameRate(_ rate: Int) {
        UserDefaults.standard.set(rate, forKey: Self.frameRateKey)
        window?.setFramesPerSecond(rate)
    }
}
