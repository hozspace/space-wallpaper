import Metal
import SpaceCore
import simd

private struct DustBake {
    var cells: SIMD2<Float>
    var seed: Float
    var cover: Float
}

private struct Cloud {
    var centre: SIMD2<Float>
    var radius: Float
    var fade: Float
    var tintA: SIMD4<Float>
    var tintB: SIMD4<Float>
}

private struct DustScroll {
    var viewOverTexture: SIMD2<Float>
    var offset: SIMD2<Float>
    var view: SIMD2<Float>
    var opacity: Float
    var cloudCount: Int32
    var churn: SIMD2<Float>
    var clouds: (Cloud, Cloud, Cloud)
}

/// Clouds the ship flies through. The texture is baked once and slid along.
@MainActor
final class DustClouds {
    enum Layer: Int {
        /// Behind the planets, moving a little slower than the ship.
        case behind
        /// In front of everything, moving a little faster, so the ship is seen to pass through it.
        case inFront
    }

    private struct Spec {
        let cells: SIMD2<Float>
        let cover: Float
        let parallax: Double
        let opacity: Float
        let seed: Float
        var texture: MTLTexture?
    }

    /// How many screens wide a texture is before it repeats.
    private static let screensAcross: Float = 2
    /// Art pixels per texel. Soft clouds need little detail.
    private static let texelSize: Float = 4
    /// How much of a cloud's radius it takes to thicken.
    private static let fadeShare = 0.55
    private static let mostClouds = 3
    /// Art pixels a second the shapes churn by, whatever the ship is doing.
    private static let churnSpeed = SIMD2<Double>(5, 3)

    private let device: MTLDevice
    private let bake: MTLRenderPipelineState
    private let scroll: MTLRenderPipelineState
    private var specs: [Spec]
    private var bakedFor: SIMD2<Float> = .zero

    init?(device: MTLDevice, library: MTLLibrary, seed: UInt64) {
        var random = SeededRandom(seed: seed &+ 0x64757374)
        guard
            let bake = Pipelines.make(device: device, library: library, vertex: "fullscreen_vertex", fragment: "dust_bake_fragment"),
            let scroll = Pipelines.make(device: device, library: library, vertex: "fullscreen_vertex", fragment: "dust_scroll_fragment")
        else { return nil }
        self.device = device
        self.bake = bake
        self.scroll = scroll
        specs = [
            Spec(cells: SIMD2(6, 4), cover: 0.38, parallax: 0.7, opacity: 0.23, seed: Float.random(in: 0...100, using: &random), texture: nil),
            Spec(cells: SIMD2(9, 6), cover: 0.5, parallax: 1.2, opacity: 0.035, seed: Float.random(in: 0...100, using: &random), texture: nil),
        ]
    }

    func bakeIfNeeded(into buffer: MTLCommandBuffer, view: SIMD2<Float>) {
        guard bakedFor != view, view.x > 0, view.y > 0 else { return }
        bakedFor = view
        let width = Int(view.x * Self.screensAcross / Self.texelSize)
        let height = Int(view.y * Self.screensAcross / Self.texelSize)
        specs = specs.map { spec in
            var next = spec
            next.texture = PlanetTexture.make(device: device, width: width, height: height)
            if next.texture == nil {
                NSLog("SpaceWallpaper: could not make a dust texture")
            }
            return next
        }
        for spec in specs {
            guard
                let texture = spec.texture,
                let encoder = buffer.makeRenderCommandEncoder(descriptor: PlanetTexture.clearPass(texture))
            else { continue }
            var params = DustBake(cells: spec.cells, seed: spec.seed, cover: spec.cover)
            encoder.setRenderPipelineState(bake)
            encoder.setFragmentBytes(&params, length: MemoryLayout<DustBake>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
    }

    func draw(_ layer: Layer, flight: Flight, with encoder: MTLRenderCommandEncoder, view: SIMD2<Float>, time: Double) {
        let spec = specs[layer.rawValue]
        guard let texture = spec.texture else { return }
        let halfView = SIMD2<Double>(view) / 2
        let clouds = flight.nebulasNearby.compactMap { nebula -> Cloud? in
            // Placed by this layer's depth, so both layers line up as the ship arrives.
            let centre = (nebula.centre - flight.camera) * spec.parallax + halfView
            let reach = nebula.radius * spec.parallax
            let isInView = abs(centre.x - halfView.x) < reach + halfView.x && abs(centre.y - halfView.y) < reach + halfView.y
            guard isInView else { return nil }
            let tints = SpaceColours.nebulaTints[nebula.tint]
            return Cloud(centre: SIMD2<Float>(centre), radius: Float(reach), fade: Float(reach * Self.fadeShare), tintA: tints.0, tintB: tints.1)
        }.prefix(Self.mostClouds)
        guard !clouds.isEmpty else { return }
        let blank = Cloud(centre: .zero, radius: 0, fade: 1, tintA: .zero, tintB: .zero)
        let slots = (0..<Self.mostClouds).map { $0 < clouds.count ? clouds[clouds.startIndex + $0] : blank }
        let across = SIMD2<Double>(view) * Double(Self.screensAcross)
        let moved = (flight.camera * spec.parallax) / across
        let wrapped = moved - moved.rounded(.down)
        let churned = Self.churnSpeed * time / across
        var params = DustScroll(
            viewOverTexture: SIMD2(repeating: 1 / Self.screensAcross), offset: SIMD2<Float>(wrapped), view: view,
            opacity: spec.opacity, cloudCount: Int32(clouds.count),
            churn: SIMD2<Float>(churned - churned.rounded(.down)), clouds: (slots[0], slots[1], slots[2])
        )
        encoder.setRenderPipelineState(scroll)
        encoder.setFragmentBytes(&params, length: MemoryLayout<DustScroll>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
