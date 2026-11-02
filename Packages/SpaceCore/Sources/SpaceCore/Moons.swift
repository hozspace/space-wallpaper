import Foundation
import simd

/// A small world on a tilted ellipse round a planet. The far half of the ellipse is behind the planet.
public struct Moon: Sendable, Equatable {
    public let index: Int
    public let kind: PlaceKind
    public let radius: Double
    public let seed: Double
    public let colourSet: Int
    public let paint: PlanetPaint
    /// Half the ellipse's width, and its height as a share of that.
    public let orbit: Double
    public let flatness: Double
    public let tilt: Double
    /// Seconds for one lap. Negative goes the other way round.
    public let period: Double
    public let phase: Double

    /// From its planet's centre, `seconds` into the journey.
    public func offset(at seconds: Double) -> (position: SIMD2<Double>, isBehind: Bool) {
        let angle = phase + 2 * .pi * seconds / period
        let flat = SIMD2(cos(angle) * orbit, sin(angle) * orbit * flatness)
        let turned = SIMD2(flat.x * cos(tilt) - flat.y * sin(tilt), flat.x * sin(tilt) + flat.y * cos(tilt))
        return (turned, sin(angle) < 0)
    }

    /// The furthest the moon's edge ever gets above or below its planet's centre.
    public var verticalReach: Double {
        let wide = orbit * sin(tilt)
        let tall = orbit * flatness * cos(tilt)
        return (wide * wide + tall * tall).squareRoot() + radius
    }

    public var reach: Double { orbit + radius }

    /// The moon as a world to paint. Its position is left to `offset(at:)`.
    public var world: Place {
        Place(index: index, kind: kind, position: .zero, radius: radius, seed: seed, rotation: phase, colourSet: colourSet, paint: paint)
    }
}

/// Roughly how a world's colours read, so its moons can sit well beside it.
enum Tone {
    case warm
    case cool
    case grey
    case pink

    /// Follows the colour sets in the app's planet recipes.
    init(kind: PlaceKind, colourSet: Int) {
        switch (kind, colourSet) {
        case (.rocky, 0): self = .grey
        case (.rocky, 3), (.desert, 3), (.lava, 4), (.gasGiant, 2), (.gasGiant, 3), (.ringed, 2): self = .pink
        case (.rocky, 2), (.gasGiant, 1), (.ringed, 1), (.ocean, _), (.earthLike, _), (.ice, _): self = .cool
        default: self = .warm
        }
    }

    /// Kinds and colour sets of moon that suit a world of this tone; repeats make a look likelier.
    var moonLooks: [(kind: PlaceKind, colourSet: Int)] {
        switch self {
        case .warm: [(.rocky, 1), (.rocky, 1), (.rocky, 0), (.desert, 0), (.desert, 2)]
        case .cool: [(.rocky, 0), (.rocky, 2), (.rocky, 2), (.ice, 1)]
        case .grey: [(.rocky, 0), (.rocky, 1), (.rocky, 2)]
        case .pink: [(.rocky, 0), (.rocky, 3), (.rocky, 3), (.desert, 3)]
        }
    }
}

extension Tour {
    private static let chanceOfMoons = [0.45, 0.4, 0.15]
    private static let moonSizes: ClosedRange<Double> = 0.12...0.22
    private static let moonRadii: ClosedRange<Double> = 14...40
    private static let orbitScales: ClosedRange<Double> = 1.5...2.2
    private static let flatnesses: ClosedRange<Double> = 0.25...0.42
    private static let tilts: ClosedRange<Double> = -0.3...0.3
    /// Art pixels a second along the orbit, so big orbits take longer.
    private static let orbitSpeeds: ClosedRange<Double> = 12...20
    /// Kept between a moon and the ship's path, which is about the rocket's height.
    static let moonClearance = 60.0
    /// How far into the space beside a planet its moons may go, leaving the middle for meteors.
    private static let shareOfGapForMoons = 0.2

    /// Rock whose colour leans the way the planet's own palette does.
    private static func moonLooks(for planet: Place) -> [(kind: PlaceKind, colourSet: Int)] {
        guard planet.paint != .preset else { return Tone(kind: planet.kind, colourSet: planet.colourSet).moonLooks }
        guard let hue = planet.paint.mainHue(for: planet.kind) else { return [(.rocky, 0)] }
        let leaning = switch hue {
        case 0.13..<0.45: 0
        case 0.45..<0.72: 2
        case 0.72..<0.9: 3
        default: 1
        }
        return [(.rocky, 0), (.rocky, leaning), (.rocky, leaning)]
    }

    /// None for ringed worlds, whose rings already fill the space round them.
    public func moons(of index: Int) -> [Moon] {
        let planet = place(index)
        guard planet.kind != .ringed else { return [] }
        var moonRandom = SeededRandom(seed: seed &+ UInt64(index) &* 0x3000_0005 &+ 0x6D)
        let roll = Double.random(in: 0..<1, using: &moonRandom)
        let count = roll < Self.chanceOfMoons[0] ? 0 : roll < Self.chanceOfMoons[0] + Self.chanceOfMoons[1] ? 1 : 2
        // Over a planet the ship flies above its moons too, so they only need keep clear when it passes beside.
        let gap = abs(planet.position.y - planet.cruiseHeight)
        let room = gap < planet.radius ? .infinity : gap - Self.moonClearance
        let sideRoom = planet.radius + Self.shareOfGapForMoons * min(
            index > 0 ? planet.position.x - planet.radius - place(index - 1).position.x - place(index - 1).reach : .infinity,
            place(index + 1).position.x - place(index + 1).reach - planet.position.x - planet.radius
        )
        let looks = Self.moonLooks(for: planet)
        // Moons are plain rock leaning towards their planet's colour, whatever that ended up being.
        let moonPaint = PlanetPaint.preset
        var innerEdge = planet.radius
        var moons: [Moon] = []
        for number in 0..<count {
            let look = looks.randomElement(using: &moonRandom) ?? (.rocky, 0)
            let radius = min(max(planet.radius * Double.random(in: Self.moonSizes, using: &moonRandom), Self.moonRadii.lowerBound), Self.moonRadii.upperBound)
            let orbit = max(planet.radius * Double.random(in: Self.orbitScales, using: &moonRandom), innerEdge + radius * 3)
            let moon = Moon(
                index: number, kind: look.kind, radius: radius,
                seed: Double.random(in: 1...9.99, using: &moonRandom),
                colourSet: look.colourSet,
                paint: moonPaint,
                orbit: orbit,
                flatness: Double.random(in: Self.flatnesses, using: &moonRandom),
                tilt: Double.random(in: Self.tilts, using: &moonRandom),
                period: 2 * .pi * orbit / Double.random(in: Self.orbitSpeeds, using: &moonRandom) * (Bool.random(using: &moonRandom) ? 1 : -1),
                phase: Double.random(in: 0..<(2 * .pi), using: &moonRandom)
            )
            guard moon.verticalReach < room, moon.reach < sideRoom else { break }
            moons.append(moon)
            innerEdge = orbit + radius
        }
        return moons
    }
}
