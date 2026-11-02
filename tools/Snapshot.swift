import AppKit
import ImageIO
import MetalKit
import UniformTypeIdentifiers

/// Renders one frame of the wallpaper to a PNG, without a window.
/// Usage: snapshot --seed 5 --seconds 60 --width 3360 --height 2100 --out frame.png
@main struct Snapshot {
    enum Failure: Error { case unavailable(String) }

    @MainActor static func main() throws {
        let args = CommandLine.arguments
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        let seed = value("--seed").flatMap(UInt64.init) ?? 1
        let seconds = value("--seconds").flatMap(Double.init) ?? 0
        let width = value("--width").flatMap(Int.init) ?? 3360
        let height = value("--height").flatMap(Int.init) ?? 2100
        let out = URL(fileURLWithPath: value("--out") ?? "snapshot.png")
        let resources = URL(fileURLWithPath: value("--resources") ?? "build/Build/Products/Release/SpaceWallpaper.app/Contents/Resources")

        guard let device = MTLCreateSystemDefaultDevice() else { throw Failure.unavailable("Metal") }
        let view = MTKView(frame: NSRect(x: 0, y: 0, width: width, height: height), device: device)
        view.isPaused = true
        view.drawableSize = CGSize(width: width, height: height)
        guard let renderer = Renderer(view: view, seed: seed, resourceDirectory: resources),
              let target = PlanetTexture.make(device: device, width: width, height: height) else { throw Failure.unavailable("Renderer") }
        renderer.seek(to: seconds)
        guard let frame = renderer.renderOffscreen(into: target, delta: 0) else { throw Failure.unavailable("Frame") }
        frame.waitUntilCompleted()
        try save(target, device: device, to: out)
        print(out.path)
    }

    @MainActor private static func save(_ texture: MTLTexture, device: MTLDevice, to url: URL) throws {
        let rowBytes = texture.width * 4
        guard let queue = device.makeCommandQueue(), let command = queue.makeCommandBuffer(),
              let pixels = device.makeBuffer(length: rowBytes * texture.height, options: .storageModeShared),
              let blit = command.makeBlitCommandEncoder() else { throw Failure.unavailable("Readback") }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                  sourceSize: MTLSize(width: texture.width, height: texture.height, depth: 1),
                  to: pixels, destinationOffset: 0, destinationBytesPerRow: rowBytes, destinationBytesPerImage: pixels.length)
        blit.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        let info = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let provider = CGDataProvider(data: Data(bytes: pixels.contents(), count: pixels.length) as CFData),
              let colours = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: texture.width, height: texture.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: rowBytes, space: colours, bitmapInfo: CGBitmapInfo(rawValue: info),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.unavailable("PNG") }
        CGImageDestinationAddImage(output, image, nil)
        guard CGImageDestinationFinalize(output) else { throw Failure.unavailable("PNG") }
    }
}
