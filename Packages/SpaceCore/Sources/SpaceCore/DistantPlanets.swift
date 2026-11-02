import simd

/// Planets far behind the ship, scattered over a grid made from a seed. Positions are
/// in each depth's own slowly-moving space, so they never need storing.
public struct DistantPlanets: Sendable {
    public struct Depth: Sendable {
        public let parallax: Double
        public let radii: ClosedRange<Double>
        public let brightness: Double
    }

    public static let cellSize = 900.0
    public static let depths = [
        Depth(parallax: 0.16, radii: 12...24, brightness: 0.62),
    ]
    private static let chanceOfPlanet = 0.12

    private let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    public func planet(depth: Int, cellX: Int, cellY: Int) -> Place? {
        let mixed = seed &+ UInt64(bitPattern: Int64(depth)) &* 0x1F1F_1F1F
            &+ UInt64(bitPattern: Int64(cellX)) &* 0x9E37_79B1
            &+ UInt64(bitPattern: Int64(cellY)) &* 0x85EB_CA77
        var random = SeededRandom(seed: mixed)
        guard Double.random(in: 0..<1, using: &random) < Self.chanceOfPlanet else { return nil }
        let inCell = SIMD2(Double.random(in: 0..<1, using: &random), Double.random(in: 0..<1, using: &random))
        let kind = PlaceKind.planets.randomElement(using: &random) ?? .rocky
        return Place(
            index: 0,
            kind: kind,
            position: (SIMD2(Double(cellX), Double(cellY)) + inCell) * Self.cellSize,
            radius: Double.random(in: Self.depths[depth].radii, using: &random),
            seed: Double.random(in: 1...9.99, using: &random),
            rotation: Double.random(in: 0..<(2 * .pi), using: &random),
            colourSet: Int.random(in: 0..<kind.colourSets, using: &random)
        )
    }
}
