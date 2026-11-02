import simd

/// Planets behind the ship's route, some far and some nearer, scattered over a grid made from a seed. Positions are
/// in each depth's own slowly-moving space, so they never need storing.
public struct DistantPlanets: Sendable {
    public struct Depth: Sendable {
        public let parallax: Double
        public let radii: ClosedRange<Double>
        public let brightness: Double
        public let cellSize: Double
        public let chance: Double
    }

    /// Farthest first, in draw order.
    public static let depths = [
        Depth(parallax: 0.16, radii: 12...24, brightness: 0.62, cellSize: 900, chance: 0.18),
        Depth(parallax: 0.4, radii: 40...85, brightness: 0.85, cellSize: 1400, chance: 0.6),
    ]

    private let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    public func planet(depth: Int, cellX: Int, cellY: Int) -> Place? {
        let mixed = seed &+ UInt64(bitPattern: Int64(depth)) &* 0x1F1F_1F1F
            &+ UInt64(bitPattern: Int64(cellX)) &* 0x9E37_79B1
            &+ UInt64(bitPattern: Int64(cellY)) &* 0x85EB_CA77
        var random = SeededRandom(seed: mixed)
        let spec = Self.depths[depth]
        guard Double.random(in: 0..<1, using: &random) < spec.chance else { return nil }
        let inCell = SIMD2(Double.random(in: 0..<1, using: &random), Double.random(in: 0..<1, using: &random))
        let kind = PlaceKind.randomPlanet(using: &random)
        return Place(
            index: 0,
            kind: kind,
            position: (SIMD2(Double(cellX), Double(cellY)) + inCell) * spec.cellSize,
            radius: Double.random(in: spec.radii, using: &random),
            seed: Double.random(in: 1...9.99, using: &random),
            rotation: Double.random(in: 0..<(2 * .pi), using: &random),
            colourSet: Int.random(in: 0..<kind.colourSets, using: &random),
            paint: PlanetPaint.random(using: &random)
        )
    }
}
