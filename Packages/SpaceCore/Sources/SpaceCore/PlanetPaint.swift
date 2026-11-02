import Foundation
import simd

/// How a world is coloured: one of its kind's hand-picked sets, that set turned round the colour
/// wheel, or a palette made from scratch the way PixelPlanets' own "randomise colours" does.
public enum PlanetPaint: Sendable, Equatable {
    case preset
    case shifted(hue: Double)
    case generated(seed: UInt64)

    static let chanceOfGenerated = 0.6
    static let chanceOfShifted = 0.5
    /// Fully saturated palettes look like sweets, so they're held back a little.
    static let mostSaturation = 0.62
    /// PixelPlanets will put pink ground beside green rivers; held this close to the main hue, a world hangs together.
    static let widestHueSpread = 0.08

    static func hueOffset(from: Double, to: Double) -> Double {
        let raw = to - from
        return raw - raw.rounded()
    }

    static func random(using random: inout SeededRandom) -> PlanetPaint {
        if Double.random(in: 0..<1, using: &random) < chanceOfGenerated {
            return .generated(seed: random.next())
        }
        if Double.random(in: 0..<1, using: &random) < chanceOfShifted {
            return .shifted(hue: Double.random(in: -0.5...0.5, using: &random))
        }
        return .preset
    }

    /// Worlds of land, sea and cloud keep their preset's balance of colours, only turned:
    /// made up from scratch, their parts clash.
    private func effective(for kind: PlaceKind) -> PlanetPaint {
        guard case .generated(let seed) = self, kind.mixesMaterials else { return self }
        return .shifted(hue: Double(seed % 1000) / 1000 - 0.5)
    }

    /// Colours in the order the kind's shaders take them, or nil to use a preset.
    public func colours(for kind: PlaceKind) -> [SIMD3<Double>]? {
        guard case .generated(let seed) = effective(for: kind) else { return nil }
        var random = SeededRandom(seed: seed)
        guard let made = PaletteMaker.colours(for: kind, using: &random), let main = made.first else { return nil }
        let mainHue = HSV(main).hue
        let target = kind.hueRange.pick(Double.random(in: 0..<1, using: &random))
        return made.map { colour in
            var hsv = HSV(colour.withSaturation(atMost: Self.mostSaturation))
            hsv.hue = target + min(max(Self.hueOffset(from: mainHue, to: hsv.hue), -Self.widestHueSpread), Self.widestHueSpread)
            return hsv.turned(by: 0).rgb
        }
    }

    /// A preset turned so its main colour lands somewhere in the kind's range; unchanged unless shifted.
    public func turned(_ preset: [SIMD3<Double>], for kind: PlaceKind) -> [SIMD3<Double>] {
        guard case .shifted(let roll) = effective(for: kind), let main = preset.first else { return preset }
        let turn = kind.hueRange.pick(roll + 0.5) - HSV(main).hue
        return preset.map { HSV($0).turned(by: turn).rgb }
    }

    /// The hue of the colour that covers most of the world, if it has much colour at all.
    public func mainHue(for kind: PlaceKind) -> Double? {
        switch effective(for: kind) {
        case .preset:
            return nil
        case .shifted(let roll):
            return kind.hueRange.pick(roll + 0.5)
        case .generated:
            guard let main = colours(for: kind)?.first, HSV(main).saturation > 0.2 else { return nil }
            return HSV(main).hue
        }
    }
}

/// Stretches of the colour wheel, any of which a hue may land in.
public struct HueRange: Sendable {
    let stretches: [ClosedRange<Double>]

    static let any = HueRange(stretches: [0...1])

    /// `share` from 0 to 1 walks along the stretches end to end.
    func pick(_ share: Double) -> Double {
        let total = stretches.reduce(0) { $0 + $1.upperBound - $1.lowerBound }
        var left = min(max(share, 0), 1) * total
        for stretch in stretches {
            let length = stretch.upperBound - stretch.lowerBound
            if left <= length { return (stretch.lowerBound + left).truncatingRemainder(dividingBy: 1) }
            left -= length
        }
        return stretches.last?.upperBound ?? 0
    }

    func contains(_ hue: Double) -> Bool {
        stretches.contains { $0.contains(hue) || $0.contains(hue + 1) }
    }
}

extension PlaceKind {
    var mixesMaterials: Bool {
        switch self {
        case .lava, .ocean, .earthLike, .ice: true
        default: false
        }
    }

    /// Where on the colour wheel each kind's main colour may sit, so a world still looks like its kind.
    public var hueRange: HueRange {
        switch self {
        case .rocky: HueRange(stretches: [0.55...1.12])
        case .desert: HueRange(stretches: [0.9...1.16])
        case .lava: HueRange(stretches: [0.85...1.1])
        case .ocean: HueRange(stretches: [0.45...0.72])
        case .earthLike: HueRange(stretches: [0.22...0.5])
        case .ice: HueRange(stretches: [0.45...0.75])
        case .gasGiant, .ringed, .asteroid: .any
        }
    }
}

/// PixelPlanets' palette generator (after Inigo Quilez's cosine palettes) and each planet's
/// `randomize_colors`, ported as they are.
enum PaletteMaker {
    static func colours(for kind: PlaceKind, using random: inout SeededRandom) -> [SIMD3<Double>]? {
        switch kind {
        case .rocky:
            let seeds = scheme(3 + Int.random(in: 0..<2, using: &random), hueSpread: Double.random(in: 0.3...0.6, using: &random), saturation: 0.7, using: &random)
            let ground = (0..<3).map { i in seeds[i].darkened(Double(i) / 3).lightened((1 - Double(i) / 3) * 0.2) }
            return ground + [ground[1], ground[2]]
        case .desert:
            let seeds = scheme(5 + Int.random(in: 0..<3, using: &random), hueSpread: Double.random(in: 0.3...0.65, using: &random), saturation: 1, using: &random)
            return (0..<5).map { i in seeds[i].darkened(Double(i) / 5).lightened((1 - Double(i) / 5) * 0.2) }
        case .lava:
            let seeds = scheme(2 + Int.random(in: 0..<3, using: &random), hueSpread: Double.random(in: 0.6...1, using: &random), saturation: Double.random(in: 0.7...0.8, using: &random), using: &random)
            let land = ramp(seeds[0], steps: 3, darkenOver: 3, hueStep: 0.2 / 4)
            let lava = ramp(seeds[1], steps: 3, darkenOver: 3, hueStep: 0.2 / 3)
            return land + [land[1], land[2]] + lava
        case .ocean, .earthLike, .ice:
            let seeds = scheme(3 + Int.random(in: 0..<2, using: &random), hueSpread: Double.random(in: 0.7...1, using: &random), saturation: Double.random(in: 0.45...0.55, using: &random), using: &random)
            let clouds = (0..<4).map { i -> SIMD3<Double> in
                let light = seeds[2].lightened((1 - Double(i) / 4) * 0.8)
                return HSV(light).turned(by: 0.2 * Double(i) / 4).rgb
            }
            switch kind {
            case .ocean:
                return ramp(seeds[1], steps: 3, darkenOver: 5, hueStep: 0.1 / 2) + ramp(seeds[0], steps: 4, darkenOver: 4, hueStep: 0.2 / 4) + clouds
            case .earthLike:
                return ramp(seeds[0], steps: 4, darkenOver: 4, hueStep: 0.2 / 4) + ramp(seeds[1], steps: 2, darkenOver: 2, hueStep: 0.2 / 2) + clouds
            default:
                return ramp(seeds[0], steps: 3, darkenOver: 3, hueStep: 0.2 / 4) + ramp(seeds[1], steps: 3, darkenOver: 3, hueStep: 0.2 / 3) + clouds
            }
        case .gasGiant:
            let seeds = scheme(8 + Int.random(in: 0..<4, using: &random), hueSpread: Double.random(in: 0.3...0.8, using: &random), saturation: 1, using: &random)
            let dark = (0..<4).map { i in seeds[i].darkened(Double(i) / 6).darkened(0.7) }
            let light = (0..<4).map { i in seeds[i + 4].darkened(Double(i) / 4).lightened((1 - Double(i) / 4) * 0.5) }
            return dark + light
        case .ringed:
            let seeds = scheme(6 + Int.random(in: 0..<4, using: &random), hueSpread: Double.random(in: 0.3...0.55, using: &random), saturation: 1.4, using: &random)
            return (0..<6).map { i in seeds[i].darkened(Double(i) / 7).lightened((1 - Double(i) / 6) * 0.3) }
        case .asteroid:
            return nil
        }
    }

    static func scheme(_ count: Int, hueSpread: Double, saturation: Double, using random: inout SeededRandom) -> [SIMD3<Double>] {
        let a = SIMD3<Double>(repeating: 0.5)
        let b = SIMD3<Double>(repeating: 0.5 * saturation)
        let c = SIMD3(Double.random(in: 0.5...1.5, using: &random), Double.random(in: 0.5...1.5, using: &random), Double.random(in: 0.5...1.5, using: &random)) * hueSpread
        let d = SIMD3(Double.random(in: 0...1, using: &random), Double.random(in: 0...1, using: &random), Double.random(in: 0...1, using: &random)) * Double.random(in: 1...3, using: &random)
        let last = Double(max(count - 1, 1))
        return (0..<count).map { i in
            let t = c * (Double(i) / last) + d
            let wave = SIMD3(cos(2 * .pi * t.x), cos(2 * .pi * t.y), cos(2 * .pi * t.z))
            return simd_clamp(a + b * wave, .zero, .one)
        }
    }

    /// A colour darkening step by step, its hue drifting a little as it goes.
    private static func ramp(_ colour: SIMD3<Double>, steps: Int, darkenOver: Double, hueStep: Double) -> [SIMD3<Double>] {
        (0..<steps).map { i in HSV(colour.darkened(Double(i) / darkenOver)).turned(by: hueStep * Double(i)).rgb }
    }
}

/// Godot's colour helpers, which PixelPlanets' generators are written with.
extension SIMD3 where Scalar == Double {
    func darkened(_ amount: Double) -> SIMD3<Double> { self * (1 - amount) }
    func lightened(_ amount: Double) -> SIMD3<Double> { self + (SIMD3(repeating: 1) - self) * amount }

    func withSaturation(atMost most: Double) -> SIMD3<Double> {
        var hsv = HSV(self)
        hsv.saturation = min(hsv.saturation, most)
        return hsv.rgb
    }
}

public struct HSV: Sendable {
    public var hue: Double
    public var saturation: Double
    public var value: Double

    public init(_ rgb: SIMD3<Double>) {
        let high = rgb.max()
        let low = rgb.min()
        let range = high - low
        value = high
        saturation = high > 0 ? range / high : 0
        guard range > 0 else {
            hue = 0
            return
        }
        let raw: Double
        if high == rgb.x {
            raw = (rgb.y - rgb.z) / range
        } else if high == rgb.y {
            raw = 2 + (rgb.z - rgb.x) / range
        } else {
            raw = 4 + (rgb.x - rgb.y) / range
        }
        let turned = raw / 6
        hue = turned - turned.rounded(.down)
    }

    public func turned(by amount: Double) -> HSV {
        var next = self
        let moved = hue + amount
        next.hue = moved - moved.rounded(.down)
        return next
    }

    public var rgb: SIMD3<Double> {
        let sector = hue * 6
        let whole = sector.rounded(.down)
        let part = sector - whole
        let p = value * (1 - saturation)
        let q = value * (1 - saturation * part)
        let t = value * (1 - saturation * (1 - part))
        switch Int(whole) % 6 {
        case 0: return SIMD3(value, t, p)
        case 1: return SIMD3(q, value, p)
        case 2: return SIMD3(p, value, t)
        case 3: return SIMD3(p, q, value)
        case 4: return SIMD3(t, p, value)
        default: return SIMD3(value, p, q)
        }
    }
}
