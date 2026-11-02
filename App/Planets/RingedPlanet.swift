import Metal
import SpaceCore
import simd

private struct RingedLayer {
    var pixels: Float
    var rotation: Float
    var light: SIMD2<Float>
    var time: Float
    var seed: Float
    var colours: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
    var darkColours: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
}

/// A gas giant in the middle third of its texture, with a ring filling the rest.
@MainActor
final class RingedPlanet: Planet {
    private static let ringScale = 3
    private static let ringTilt: Float = 0.7
    private static let turnSeconds: Float = 30
    /// Matches `gasSize` in the shader.
    private static let gasSize: Float = 10.107
    /// The ring moves a pixel for every this many the planet turns.
    private static let ringLag: Float = 2
    /// Roughly where the ring's pixels sit, as a share of its texture.
    private static let ringRadius: Float = 0.45

    /// Three light, three dark.
    static let colourSets: [[Int]] = [
        [22, 24, 20, 19, 18, 17],
        [9, 10, 11, 12, 13, 14],
        [46, 56, 55, 54, 53, 15],
    ]

    let displaySize: Float
    let texture: MTLTexture
    private let painted: MTLTexture
    let pace: Float
    private let pipelines: PlanetPipelines
    private let size: Int
    private let rotation: Float
    private let seed: Float
    private let colours: [SIMD4<Float>]
    private let light = SIMD2<Float>(0.39, 0.39)

    /// `size` is the planet's width in art pixels; the ring makes it three times that overall.
    init?(device: MTLDevice, pipelines: PlanetPipelines, size: Int, seed: Float, rotation: Float, colourSet: Int, paint: PlanetPaint) {
        let surface = PlanetTexture.surfaceSize(for: size)
        guard let texture = PlanetTexture.make(device: device, size: surface * Self.ringScale),
              let painted = PlanetTexture.make(device: device, size: texture.width) else { return nil }
        self.texture = texture
        self.painted = painted
        self.pipelines = pipelines
        self.size = surface
        pace = Float(surface) / 2 / Self.turnSeconds
        displaySize = Float(size * Self.ringScale)
        self.seed = seed
        self.rotation = rotation
        colours = PlanetColours.resolve(Self.colourSets[colourSet % Self.colourSets.count], kind: .ringed, paint: paint)
    }

    func draw(into buffer: MTLCommandBuffer, time: Float) {
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: PlanetTexture.clearPass(painted)) else { return }
        let side = Double(size)
        encoder.setViewport(MTLViewport(originX: side, originY: side, width: side, height: side, znear: 0, zfar: 1))
        let gasTime = time.rounded(.down) * Self.gasSize * 0.5 / Float(size)
        let ringTime = (time / Self.ringLag).rounded(.down) / (Float(size * Self.ringScale) * Self.ringRadius)
        drawLayer(pipelines.ringedGas, encoder: encoder, pixels: Float(size), rotation: rotation, time: gasTime)
        encoder.setViewport(MTLViewport(originX: 0, originY: 0, width: side * 3, height: side * 3, znear: 0, zfar: 1))
        drawLayer(pipelines.ringedRing, encoder: encoder, pixels: Float(size * Self.ringScale), rotation: rotation + Self.ringTilt, time: ringTime)
        encoder.endEncoding()
        PlanetTexture.tidy(painted, into: texture, buffer: buffer, pipelines: pipelines)
    }

    private func drawLayer(_ pipeline: MTLRenderPipelineState, encoder: MTLRenderCommandEncoder, pixels: Float, rotation: Float, time: Float) {
        var layer = RingedLayer(pixels: pixels, rotation: rotation, light: light, time: time, seed: seed, colours: (colours[0], colours[1], colours[2]), darkColours: (colours[3], colours[4], colours[5]))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&layer, length: MemoryLayout<RingedLayer>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}
