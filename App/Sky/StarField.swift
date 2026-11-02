import Metal
import SpaceCore
import simd

private struct Star {
    var at: SIMD2<Float>
    var colour: SIMD4<Float>
    var size: Float
}

private struct StarLayerParams {
    var view: SIMD2<Float>
    var offset: SIMD2<Float>
    var scale: Float
}

/// Layers of stars far behind the ship: mostly tiny and dim, with a few brighter ones nearer.
@MainActor
final class StarField {
    private struct Layer {
        let buffer: MTLBuffer
        let count: Int
        let parallax: Double
    }

    private static let specs: [(count: Int, parallax: Double, size: Float, brightness: ClosedRange<Float>)] = [
        (1400, 0.06, 1, 0.18...0.5),
        (600, 0.14, 2, 0.15...0.45),
        (180, 0.26, 2, 0.4...0.85),
        (30, 0.42, 3, 0.75...1),
    ]
    private static let tints: [SIMD3<Float>] = [
        SIMD3(1, 1, 1), SIMD3(1, 1, 1), SIMD3(0.78, 0.86, 1), SIMD3(1, 0.9, 0.78),
    ]

    private let pipeline: MTLRenderPipelineState
    private let layers: [Layer]

    init?(device: MTLDevice, library: MTLLibrary, seed: UInt64) {
        var random = SeededRandom(seed: seed &+ 0x73746172)
        guard let pipeline = Pipelines.make(device: device, library: library, vertex: "star_vertex", fragment: "star_fragment") else { return nil }
        self.pipeline = pipeline
        var built: [Layer] = []
        for spec in Self.specs {
            let stars = (0..<spec.count).map { _ -> Star in
                let tint = (Self.tints.randomElement(using: &random) ?? Self.tints[0]) * Float.random(in: spec.brightness, using: &random)
                return Star(at: SIMD2(Float.random(in: 0..<1, using: &random), Float.random(in: 0..<1, using: &random)), colour: SIMD4(tint, 1), size: spec.size)
            }
            guard let buffer = device.makeBuffer(bytes: stars, length: MemoryLayout<Star>.stride * stars.count) else { return nil }
            built.append(Layer(buffer: buffer, count: stars.count, parallax: spec.parallax))
        }
        layers = built
    }

    func draw(with encoder: MTLRenderCommandEncoder, view: SIMD2<Float>, camera: SIMD2<Double>, artPixel: Float) {
        encoder.setRenderPipelineState(pipeline)
        let size = SIMD2<Double>(view)
        for layer in layers {
            let moved = camera * layer.parallax
            let wrapped = moved - size * (moved / size).rounded(.down)
            var params = StarLayerParams(view: view, offset: SIMD2<Float>(wrapped), scale: artPixel)
            encoder.setVertexBuffer(layer.buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&params, length: MemoryLayout<StarLayerParams>.stride, index: 1)
            encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: layer.count)
        }
    }
}
