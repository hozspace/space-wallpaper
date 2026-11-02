import Foundation
import simd

public enum PlaceKind: Sendable, Hashable, CaseIterable {
    case rocky
    case desert
    case lava
    case ocean
    case earthLike
    case ice
    case gasGiant
    case ringed
    case asteroid

    public static let planets = allCases.filter { $0 != .asteroid }

    public var colourSets: Int {
        switch self {
        case .lava: 4
        default: 3
        }
    }

    /// In multiples of the body's radius.
    public var reachScale: Double {
        self == .ringed ? 3 : 1
    }
}

/// Somewhere the ship passes. `radius` is the body itself; rings reach further.
public struct Place: Sendable, Equatable {
    public let index: Int
    public let kind: PlaceKind
    public let position: SIMD2<Double>
    public let radius: Double
    public let seed: Double
    public let rotation: Double
    public let colourSet: Int
    public var cruiseHeight = 0.0

    public var reach: Double { radius * kind.reachScale }
}

/// One meteor. A rock's shape only fills the middle of its radius.
public typealias Rock = Place

/// A band of meteors between two places, with a gap for the ship.
public struct RockField: Sendable, Equatable {
    public let centre: SIMD2<Double>
    public let radius: Double
    public let rocks: [Rock]
}

public struct Nebula: Sendable, Equatable {
    public let centre: SIMD2<Double>
    public let radius: Double
    public let tint: Int
}

/// An endless line of hero planets made from a seed, far enough apart that one leaves as the next arrives.
public final class Tour {
    public static let nebulaTints = 6
    private static let chanceOfNebula = 0.45
    private static let nebulaRadii: ClosedRange<Double> = 1300...2600
    private static let gaps: ClosedRange<Double> = 1700...2100
    public static let smallestClearance = 40.0
    /// How far from its path a planet's edge sits, and how much the path's height changes per planet.
    private static let clearances: ClosedRange<Double> = 110...340
    private static let heightChanges: ClosedRange<Double> = -60...60
    private static let highestCruise = 150.0
    private static let mediumRadii: ClosedRange<Double> = 70...130
    private static let largeRadii: ClosedRange<Double> = 150...250
    private static let hugeRadii: ClosedRange<Double> = 320...480
    private static let chanceOfMedium = 0.45
    private static let chanceOfLarge = 0.4
    /// A ring reaches three times its planet's width, so ringed worlds stay smaller.
    private static let ringedLargestRadius = 130.0
    private static let chanceOfRocks = 0.3
    private static let rockCounts: ClosedRange<Int> = 40...60
    private static let smallestRock = 12.0
    private static let rockSizeSpread = 40.0
    private static let beltHalfLength = 520.0
    private static let beltHalfWidth = 60.0
    private static let beltLean = 0.5
    /// The clear stretch in the middle that the ship flies through.
    private static let gapHalfLength = 80.0
    private static let fieldDrift = 100.0
    private static let gapHeightDrift = 120.0
    private static let dodgeStart = 1000.0

    private let minimumGap: Double
    private let seed: UInt64
    private var random: SeededRandom
    private var known: [Place] = []

    public init(seed: UInt64, minimumGap: Double = 1700) {
        self.minimumGap = max(Self.gaps.lowerBound, minimumGap)
        self.seed = seed
        random = SeededRandom(seed: seed)
    }

    public func place(_ index: Int) -> Place {
        while known.count <= index {
            known.append(makeNext())
        }
        return known[index]
    }

    public func rockField(afterPlace index: Int) -> RockField? {
        var fieldRandom = SeededRandom(seed: seed &+ UInt64(index) &* 0x1000_0001)
        guard Double.random(in: 0..<1, using: &fieldRandom) < Self.chanceOfRocks else { return nil }
        let from = place(index)
        let to = place(index + 1)
        let middle = (from.position.x + from.reach + to.position.x - to.reach) / 2
        let centre = SIMD2(
            middle + Double.random(in: -Self.fieldDrift...Self.fieldDrift, using: &fieldRandom),
            from.cruiseHeight + Double.random(in: -Self.gapHeightDrift...Self.gapHeightDrift, using: &fieldRandom)
        )
        let angle = .pi / 2 + Double.random(in: -Self.beltLean...Self.beltLean, using: &fieldRandom)
        let along = SIMD2(cos(angle), sin(angle))
        let across = SIMD2(-along.y, along.x)
        let colourSet = Int.random(in: 0..<PlaceKind.asteroid.colourSets, using: &fieldRandom)
        let count = Int.random(in: Self.rockCounts, using: &fieldRandom)
        let rocks = (0..<count).map { number -> Rock in
            // Squaring makes most rocks small and a few big.
            let size = Double.random(in: 0...1, using: &fieldRandom)
            let radius = Self.smallestRock + Self.rockSizeSpread * size * size
            let side: Double = Bool.random(using: &fieldRandom) ? 1 : -1
            let distance = Double.random(in: (Self.gapHalfLength + radius)...(Self.beltHalfLength - radius), using: &fieldRandom)
            let sideways = Double.random(in: -Self.beltHalfWidth...Self.beltHalfWidth, using: &fieldRandom)
            return Place(
                index: number, kind: .asteroid, position: centre + along * side * distance + across * sideways, radius: radius,
                seed: Double.random(in: 1...9.99, using: &fieldRandom),
                rotation: Double.random(in: 0..<(2 * .pi), using: &fieldRandom),
                colourSet: colourSet
            )
        }
        return RockField(centre: centre, radius: Self.beltHalfLength + Self.beltHalfWidth, rocks: rocks)
    }

    /// The height the ship wants on the way to place `leg`, and whether it needs to get there now.
    public func flightGoal(shipX: Double, leg: Int) -> (height: Double, isUrgent: Bool) {
        let cruise = place(leg).cruiseHeight
        guard let field = rockField(afterPlace: leg - 1), shipX > field.centre.x - Self.dodgeStart else { return (cruise, false) }
        let farEdge = field.rocks.map { $0.position.x + $0.radius }.max() ?? field.centre.x
        // Through the gap, then straight back to the route.
        return (shipX < farEdge ? field.centre.y : cruise, true)
    }

    public func nebula(afterPlace index: Int) -> Nebula? {
        var cloudRandom = SeededRandom(seed: seed &+ UInt64(index) &* 0x2000_0003 &+ 0x55)
        guard Double.random(in: 0..<1, using: &cloudRandom) < Self.chanceOfNebula else { return nil }
        let from = place(index).position
        let to = place(index + 1).position
        let direction = simd_normalize(to - from)
        let radius = Double.random(in: Self.nebulaRadii, using: &cloudRandom)
        let sideways = SIMD2(-direction.y, direction.x) * Double.random(in: -0.4...0.4, using: &cloudRandom) * radius
        let centre = from + (to - from) * Double.random(in: 0.3...0.7, using: &cloudRandom) + sideways
        return Nebula(centre: centre, radius: radius, tint: Int.random(in: 0..<Self.nebulaTints, using: &cloudRandom))
    }

    private func makeNext() -> Place {
        let index = known.count
        let (kind, colourSet) = nextLook()
        let radius = nextRadius(for: kind)
        let cruise = min(max((known.last?.cruiseHeight ?? 0) + Double.random(in: Self.heightChanges, using: &random), -Self.highestCruise), Self.highestCruise)
        let side: Double = Bool.random(using: &random) ? 1 : -1
        let height = cruise + side * (radius + Double.random(in: Self.clearances, using: &random))
        var across = 0.0
        if let last = known.last {
            let nextReach = radius * kind.reachScale
            let gap = Double.random(in: minimumGap...(minimumGap + Self.gaps.upperBound - Self.gaps.lowerBound), using: &random)
            across = last.position.x + last.reach + nextReach + gap
        }
        let position = SIMD2(across, height)
        return Place(
            index: index, kind: kind, position: position, radius: radius,
            seed: Double.random(in: 1...9.99, using: &random),
            rotation: Double.random(in: 0..<(2 * .pi), using: &random),
            colourSet: colourSet,
            cruiseHeight: cruise
        )
    }

    /// Never the same type and colour as the planet before.
    private func nextLook() -> (PlaceKind, Int) {
        while true {
            let kind = PlaceKind.planets.randomElement(using: &random) ?? .rocky
            let colourSet = Int.random(in: 0..<kind.colourSets, using: &random)
            if known.last?.kind != kind || known.last?.colourSet != colourSet {
                return (kind, colourSet)
            }
        }
    }

    private func nextRadius(for kind: PlaceKind) -> Double {
        let roll = Double.random(in: 0..<1, using: &random)
        let radius: Double
        if roll < Self.chanceOfMedium {
            radius = Double.random(in: Self.mediumRadii, using: &random)
        } else if roll < Self.chanceOfMedium + Self.chanceOfLarge {
            radius = Double.random(in: Self.largeRadii, using: &random)
        } else {
            radius = Double.random(in: Self.hugeRadii, using: &random)
        }
        return kind == .ringed ? min(radius, Self.ringedLargestRadius) : radius
    }
}
