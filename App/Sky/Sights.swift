import Metal
import SpaceCore
import simd

private struct SightParams {
    var pixels: Float
    var radius: Float
    var seed: Float
    var tilt: Float
    var flatness: Float
    var time: Float
    var colours: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
}

/// Suns and galaxies far behind everything, painted straight to the screen in coarse pixels.
@MainActor
final class Sights {
    /// Art pixels per sight pixel: between the stars' fine dots and the planets' chunky ones.
    private static let pixelScale: Float = 2
    /// How far a sight's sprite reaches, as a share of its radius.
    private static let sunSpan: Float = 1.45
    private static let galaxySpan: Float = 1.15
    private static let sunColours = [[8, 32, 30, 25], [23, 58, 59, 61], [8, 45, 43, 41]].map(Palette.colours)
    private static let galaxyColours = [
        [23, 9, 11, 13], [23, 22, 19, 17], [9, 10, 12, 13], [23, 24, 19, 17], [23, 58, 63, 16], [9, 45, 38, 39],
    ].map(Palette.colours)

    private let sun: MTLRenderPipelineState
    private let galaxy: MTLRenderPipelineState
    private let sights: DistantSights

    init?(device: MTLDevice, library: MTLLibrary, seed: UInt64) {
        guard let sun = Pipelines.make(device: device, library: library, vertex: "sprite_vertex", fragment: "sun_fragment"),
              let galaxy = Pipelines.make(device: device, library: library, vertex: "sprite_vertex", fragment: "galaxy_fragment") else { return nil }
        self.sun = sun
        self.galaxy = galaxy
        sights = DistantSights(seed: seed)
    }

    func draw(with encoder: MTLRenderCommandEncoder, view: SIMD2<Float>, camera: SIMD2<Double>, artPixel: Float, time: Float) {
        let halfView = SIMD2<Double>(view) / 2
        for (index, depth) in DistantSights.depths.enumerated() {
            let middle = camera * depth.parallax
            let reach = halfView + depth.radii.upperBound * Double(Self.sunSpan)
            let low = ((middle - reach) / depth.cellSize).rounded(.down)
            let high = ((middle + reach) / depth.cellSize).rounded(.down)
            encoder.setRenderPipelineState(depth.kind == .sun ? sun : galaxy)
            for x in Int(low.x)...Int(high.x) {
                for y in Int(low.y)...Int(high.y) {
                    guard let sight = sights.sight(depth: index, cellX: x, cellY: y) else { continue }
                    draw(sight, at: SIMD2<Float>(sight.position - middle + halfView), with: encoder, view: view, artPixel: artPixel, time: time)
                }
            }
        }
    }

    private func draw(_ sight: DistantSights.Sight, at centre: SIMD2<Float>, with encoder: MTLRenderCommandEncoder, view: SIMD2<Float>, artPixel: Float, time: Float) {
        let isSun = sight.kind == .sun
        let radius = Float(sight.radius) / Self.pixelScale
        // Odd, so a pixel sits right in the middle.
        let pixels = (radius * (isSun ? Self.sunSpan : Self.galaxySpan)).rounded(.up) * 2 + 1
        let screen = view * artPixel
        let side = pixels * Self.pixelScale * artPixel
        let topLeft = (centre * artPixel - side / 2).rounded(.toNearestOrAwayFromZero)
        guard topLeft.x < screen.x, topLeft.y < screen.y, topLeft.x + side > 0, topLeft.y + side > 0 else { return }
        var rect = SIMD4(topLeft.x / screen.x * 2 - 1, 1 - topLeft.y / screen.y * 2, side / screen.x * 2, side / screen.y * 2)
        let sets = isSun ? Self.sunColours : Self.galaxyColours
        let colours = sets[sight.colourSet % sets.count]
        var params = SightParams(
            pixels: pixels, radius: radius, seed: Float(sight.seed), tilt: Float(sight.tilt), flatness: Float(sight.flatness), time: time,
            colours: (colours[0], colours[1], colours[2], colours[3])
        )
        encoder.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.stride, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<SightParams>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}
