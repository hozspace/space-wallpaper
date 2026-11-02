import AppKit
import MetalKit

/// A borderless window on the desktop layer: above the picture, below the icons.
@MainActor
final class WallpaperWindow: NSWindow {
    private let renderer: Renderer?
    private let metalView: MTKView

    init(screen: NSScreen, framesPerSecond: Int, flightSpeed: Double, preview: Bool = false, seed: UInt64? = nil, seconds: Double = 0) {
        let frame = preview ? NSRect(x: 0, y: 0, width: 1280, height: 800) : screen.frame
        let view = MTKView(frame: frame, device: MTLCreateSystemDefaultDevice())
        metalView = view
        renderer = Renderer(view: view, seed: seed, remembersJourney: !preview)
        renderer?.flightSpeed = flightSpeed
        renderer?.seek(to: seconds)
        super.init(contentRect: frame, styleMask: preview ? [.titled, .closable, .resizable] : .borderless, backing: .buffered, defer: false)
        if renderer == nil {
            NSLog("SpaceWallpaper: could not start drawing")
        }
        view.preferredFramesPerSecond = framesPerSecond
        contentView = view
        isOpaque = true
        backgroundColor = .black
        isReleasedWhenClosed = false
        if preview {
            title = "Space Wallpaper — Journey Preview"
            center()
            makeKeyAndOrderFront(nil)
        } else {
            level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopWindow)))
            collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            ignoresMouseEvents = true
            setFrame(screen.frame, display: false)
            orderFrontRegardless()
        }
    }

    func setPaused(_ paused: Bool) {
        metalView.isPaused = paused
        renderer?.resetFrameClock()
    }

    func setFlightSpeed(_ flightSpeed: Double) {
        renderer?.flightSpeed = flightSpeed
    }

    func setFramesPerSecond(_ framesPerSecond: Int) {
        metalView.preferredFramesPerSecond = framesPerSecond
    }
}
