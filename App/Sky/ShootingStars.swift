import Metal
import SpaceCore
import simd

private struct ShootingStarParams {
    var centre: SIMD2<Float>
    var size: SIMD2<Float>
    var screen: SIMD2<Float>
    var angle: Float
    var head: SIMD2<Float>
    var direction: SIMD2<Float>
    var length: Float
    var pixel: Float
    var fade: Float
}

/// Now and then a star streaks across the sky. Worked out from the seed and the clock, so nothing is kept.
@MainActor
final class ShootingStars {
    /// Each stretch of this many seconds may hold one.
    private static let slotSeconds: Float = 14
    private static let chance = 0.6
    private static let lifetimes: ClosedRange<Double> = 0.6...1.1
    /// Screens a second, so it crosses the same share of any display.
    private static let speeds: ClosedRange<Double> = 0.35...0.6
    /// Below the horizontal, so they fall rather than climb.
    private static let slopes: ClosedRange<Double> = 0.25...0.8
    private static let tailLengths: ClosedRange<Double> = 0.05...0.09
    /// The last share of its life spent fading out.
    private static let fadeShare: Float = 0.35
    /// Art pixels per streak pixel, matching the nearer stars.
    private static let pixelScale: Float = 2

    private let pipeline: MTLRenderPipelineState
    private let seed: UInt64

    init?(device: MTLDevice, library: MTLLibrary, seed: UInt64) {
        guard let pipeline = Pipelines.make(device: device, library: library, vertex: "rotated_sprite_vertex", fragment: "shooting_star_fragment") else { return nil }
        self.pipeline = pipeline
        self.seed = seed
    }

    func draw(with encoder: MTLRenderCommandEncoder, screen: SIMD2<Float>, artPixel: Float, time: Float) {
        let slot = (time / Self.slotSeconds).rounded(.down)
        var random = SeededRandom(seed: seed &+ 0x5353 &+ UInt64(bitPattern: Int64(slot)) &* 0x9E37_79B9)
        guard Double.random(in: 0..<1, using: &random) < Self.chance else { return }
        let lifetime = Float(Double.random(in: Self.lifetimes, using: &random))
        let start = Float.random(in: 0...(Self.slotSeconds - lifetime), using: &random)
        let age = time - slot * Self.slotSeconds - start
        guard age >= 0, age < lifetime else { return }

        let from = SIMD2(Float.random(in: 0.1...0.9, using: &random), Float.random(in: 0.05...0.5, using: &random)) * screen
        let goesRight = Bool.random(using: &random)
        let slope = Float(Double.random(in: Self.slopes, using: &random))
        let direction = SIMD2(goesRight ? cos(slope) : -cos(slope), sin(slope))
        let speed = Float(Double.random(in: Self.speeds, using: &random)) * screen.x
        let tail = Float(Double.random(in: Self.tailLengths, using: &random)) * screen.x
        let head = from + direction * speed * age
        let length = min(tail, speed * age)
        let left = 1 - age / lifetime
        let pixel = artPixel * Self.pixelScale
        var params = ShootingStarParams(
            centre: head - direction * length / 2, size: SIMD2(length + pixel * 2, pixel * 2), screen: screen,
            angle: atan2(direction.y, direction.x), head: head, direction: direction, length: length, pixel: pixel,
            fade: min(left / Self.fadeShare, 1)
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&params, length: MemoryLayout<ShootingStarParams>.stride, index: 0)
        encoder.setFragmentBytes(&params, length: MemoryLayout<ShootingStarParams>.stride, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
    }
}
