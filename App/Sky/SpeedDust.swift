import Metal
import SpaceCore
import simd

private struct Speck {
    var at: SIMD2<Float>
    var brightness: Float
}

private struct SpeedLayer {
    var view: SIMD2<Float>
    var offset: SIMD2<Float>
    var direction: SIMD2<Float>
    var length: Float
    var thickness: Float
    var opacity: Float
}

/// Fine dust close to the ship, passing faster than anything else, so it reads as speed.
@MainActor
final class SpeedDust {
    private struct Layer {
        let buffer: MTLBuffer
        let count: Int
        let parallax: Double
        let opacity: Float
    }

    private static let specs: [(count: Int, parallax: Double, opacity: Float)] = [
        (40, 1.4, 0.2),
        (14, 2.2, 0.3),
    ]
    /// A streak's length, as the seconds of movement it shows.
    private static let streakSeconds = 0.3
    private static let thickness: Float = 1

    private let pipeline: MTLRenderPipelineState
    private let layers: [Layer]

    init?(device: MTLDevice, library: MTLLibrary, seed: UInt64) {
        var random = SeededRandom(seed: seed &+ 0x7370656564)
        guard let pipeline = Pipelines.make(device: device, library: library, vertex: "speed_dust_vertex", fragment: "speed_dust_fragment") else { return nil }
        self.pipeline = pipeline
        var built: [Layer] = []
        for spec in Self.specs {
            let specks = (0..<spec.count).map { _ in
                Speck(at: SIMD2(Float.random(in: 0..<1, using: &random), Float.random(in: 0..<1, using: &random)), brightness: Float.random(in: 0.4...1, using: &random))
            }
            guard let buffer = device.makeBuffer(bytes: specks, length: MemoryLayout<Speck>.stride * specks.count) else { return nil }
            built.append(Layer(buffer: buffer, count: spec.count, parallax: spec.parallax, opacity: spec.opacity))
        }
        layers = built
    }

    func draw(with encoder: MTLRenderCommandEncoder, view: SIMD2<Float>, camera: SIMD2<Double>, heading: Double, speed: Double) {
        encoder.setRenderPipelineState(pipeline)
        let size = SIMD2<Double>(view)
        let direction = SIMD2<Float>(Float(cos(heading)), Float(sin(heading)))
        // Dust slides the opposite way to travel, so its tail trails ahead of its head on screen.
        let tail = -direction
        for layer in layers {
            let moved = camera * layer.parallax
            let wrapped = moved - size * (moved / size).rounded(.down)
            var params = SpeedLayer(
                view: view, offset: SIMD2<Float>(wrapped), direction: tail,
                length: Float(speed * layer.parallax * Self.streakSeconds), thickness: Self.thickness, opacity: layer.opacity
            )
            encoder.setVertexBuffer(layer.buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&params, length: MemoryLayout<SpeedLayer>.stride, index: 1)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: layer.count)
        }
    }
}
