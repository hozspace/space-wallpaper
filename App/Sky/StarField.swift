import Metal
import SpaceCore
import simd

private struct Star {
    var at: SIMD2<Float>
    var colour: SIMD4<Float>
    var phase: Float
}

private struct StarLayerParams {
    var view: SIMD2<Float>
    var offset: SIMD2<Float>
    var scale: Float
    /// Star pixels across a star's sprite: 1 for a dot, 3 for a cross, 7 for a sparkle.
    var span: Float
    /// Art pixels per star pixel.
    var pixel: Float
    var time: Float
}

/// Layers of stars far behind the ship, on a pixel grid: fine dots, then coarser dots, crosses and twinkling sparkles nearer.
@MainActor
final class StarField {
    private struct Layer {
        let buffer: MTLBuffer
        let count: Int
        let parallax: Double
        let span: Float
        let pixel: Float
    }

    /// Some of the fainter stars gather in loose clumps, so empty space has some shape to it.
    private static let clumpsPerLayer = 4
    private static let shareInClumps: Float = 0.45
    private static let clumpSpread: ClosedRange<Float> = 0.03...0.08
    private static let clumpedLayers = 2

    private static let specs: [(count: Int, parallax: Double, span: Float, pixel: Float, brightness: ClosedRange<Float>)] = [
        (1100, 0.06, 1, 1, 0.25...0.55),
        (300, 0.14, 1, 2, 0.35...0.75),
        (130, 0.26, 3, 2, 0.6...0.95),
        (26, 0.42, 7, 2, 0.85...1),
    ]
    private static let tints: [SIMD3<Float>] = [
        SIMD3(1, 1, 1), SIMD3(1, 1, 1), SIMD3(0.78, 0.86, 1), SIMD3(1, 0.9, 0.78),
    ]
    /// Now and then a star is properly coloured: pink, orange, green or cyan.
    private static let rareTints: [SIMD3<Float>] = [
        SIMD3(0.95, 0.54, 0.96), SIMD3(1, 0.64, 0.08), SIMD3(0.6, 0.9, 0.37), SIMD3(0.3, 0.9, 1),
    ]
    private static let chanceOfRareTint: Float = 0.08

    private let pipeline: MTLRenderPipelineState
    private let layers: [Layer]

    init?(device: MTLDevice, library: MTLLibrary, seed: UInt64) {
        var random = SeededRandom(seed: seed &+ 0x73746172)
        guard let pipeline = Pipelines.make(device: device, library: library, vertex: "star_vertex", fragment: "star_fragment") else { return nil }
        self.pipeline = pipeline
        var built: [Layer] = []
        for (index, spec) in Self.specs.enumerated() {
            let clumps = index < Self.clumpedLayers ? (0..<Self.clumpsPerLayer).map { _ in
                (centre: SIMD2(Float.random(in: 0..<1, using: &random), Float.random(in: 0..<1, using: &random)),
                 spread: Float.random(in: Self.clumpSpread, using: &random))
            } : []
            let stars = (0..<spec.count).map { _ -> Star in
                let palette = Float.random(in: 0..<1, using: &random) < Self.chanceOfRareTint ? Self.rareTints : Self.tints
                let tint = (palette.randomElement(using: &random) ?? Self.tints[0]) * Float.random(in: spec.brightness, using: &random)
                var at = SIMD2(Float.random(in: 0..<1, using: &random), Float.random(in: 0..<1, using: &random))
                if let clump = clumps.randomElement(using: &random), Float.random(in: 0..<1, using: &random) < Self.shareInClumps {
                    // Two rolls added together bunch stars towards the middle of a clump.
                    let nudge = SIMD2(Float.random(in: -1...1, using: &random) + Float.random(in: -1...1, using: &random),
                                      Float.random(in: -1...1, using: &random) + Float.random(in: -1...1, using: &random))
                    let placed = clump.centre + nudge * clump.spread
                    at = placed - placed.rounded(.down)
                }
                return Star(at: at, colour: SIMD4(tint, 1), phase: Float.random(in: 0..<100, using: &random))
            }
            guard let buffer = device.makeBuffer(bytes: stars, length: MemoryLayout<Star>.stride * stars.count) else { return nil }
            built.append(Layer(buffer: buffer, count: stars.count, parallax: spec.parallax, span: spec.span, pixel: spec.pixel))
        }
        layers = built
    }

    func draw(with encoder: MTLRenderCommandEncoder, view: SIMD2<Float>, camera: SIMD2<Double>, artPixel: Float, time: Float) {
        encoder.setRenderPipelineState(pipeline)
        let size = SIMD2<Double>(view)
        for layer in layers {
            let moved = camera * layer.parallax
            let wrapped = moved - size * (moved / size).rounded(.down)
            var params = StarLayerParams(view: view, offset: SIMD2<Float>(wrapped), scale: artPixel, span: layer.span, pixel: layer.pixel, time: time)
            encoder.setVertexBuffer(layer.buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&params, length: MemoryLayout<StarLayerParams>.stride, index: 1)
            encoder.setFragmentBytes(&params, length: MemoryLayout<StarLayerParams>.stride, index: 0)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: layer.count)
        }
    }
}
