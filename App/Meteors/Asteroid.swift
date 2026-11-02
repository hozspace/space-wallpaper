import Metal
import simd

/// One meteor, painted once and turned whole so its edge stays still.
@MainActor
final class Asteroid: Planet {
    private static let shapeSize: Float = 5.294
    private static let octaves: Int32 = 2
    private static let smallestSurface = 8
    private static let colourSets = [[10, 11, 13], [21, 19, 18], [7, 5, 3]]
    private static let spins: ClosedRange<Float> = 0.05...0.2

    let displaySize: Float
    let texture: MTLTexture
    private let painted: MTLTexture
    let pace: Float
    let isTumbling = true
    private let pipelines: PlanetPipelines
    private let seed: Float
    private let startAngle: Float
    private let colours: [SIMD4<Float>]

    init?(device: MTLDevice, pipelines: PlanetPipelines, size: Int, seed: Float, rotation: Float, colourSet: Int) {
        // Finer pixels than the planets: at theirs a rock is a chunky blob.
        let surface = max(Self.smallestSurface, size)
        guard let texture = PlanetTexture.make(device: device, size: surface),
              let painted = PlanetTexture.make(device: device, size: surface) else { return nil }
        self.texture = texture
        self.painted = painted
        self.pipelines = pipelines
        displaySize = Float(surface)
        self.seed = seed
        startAngle = rotation
        let spread = (seed * 7.31).truncatingRemainder(dividingBy: 1)
        let spin = Self.spins.lowerBound + (Self.spins.upperBound - Self.spins.lowerBound) * spread
        pace = seed.truncatingRemainder(dividingBy: 2) < 1 ? spin : -spin
        colours = Palette.colours(Self.colourSets[colourSet % Self.colourSets.count])
    }

    func draw(into buffer: MTLCommandBuffer, time: Float) {
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: PlanetTexture.clearPass(painted)) else { return }
        let all = colours + Array(repeating: SIMD4<Float>.zero, count: 3)
        var layer = PlanetLayerParams(
            pixels: Float(texture.width), rotation: startAngle, light: .zero, time: 0, seed: seed,
            size: Self.shapeSize, border1: 0, border2: 0, cutoff: 0, stretch: 1, ditherSize: 0, octaves: Self.octaves,
            colours: (all[0], all[1], all[2], all[3], all[4], all[5])
        )
        encoder.setRenderPipelineState(pipelines.asteroid)
        encoder.setFragmentBytes(&layer, length: MemoryLayout<PlanetLayerParams>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        PlanetTexture.tidy(painted, into: texture, buffer: buffer, pipelines: pipelines)
    }
}
