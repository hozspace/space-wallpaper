import simd

/// Suns and galaxies further back than the distant planets, scattered over a grid made from a seed.
public struct DistantSights: Sendable {
    public enum Kind: Sendable, Equatable {
        case sun
        case galaxy
    }

    public struct Sight: Sendable, Equatable {
        public let kind: Kind
        public let position: SIMD2<Double>
        /// The sun's body or the galaxy's disc, in art pixels. A sun's glow reaches further.
        public let radius: Double
        public let seed: Double
        public let colourSet: Int
        public let tilt: Double
        /// How squashed a galaxy is by being seen at an angle; 1 is face on.
        public let flatness: Double
    }

    public struct Depth: Sendable {
        public let kind: Kind
        public let parallax: Double
        public let cellSize: Double
        public let chance: Double
        public let radii: ClosedRange<Double>
        public let colourSets: Int
    }

    /// Farthest first, in draw order.
    public static let depths = [
        Depth(kind: .galaxy, parallax: 0.03, cellSize: 650, chance: 0.55, radii: 16...30, colourSets: 6),
        Depth(kind: .galaxy, parallax: 0.06, cellSize: 900, chance: 0.4, radii: 28...55, colourSets: 6),
        Depth(kind: .galaxy, parallax: 0.1, cellSize: 1100, chance: 0.5, radii: 50...100, colourSets: 6),
        Depth(kind: .sun, parallax: 0.13, cellSize: 1400, chance: 0.3, radii: 14...26, colourSets: 3),
    ]
    private static let flatnesses: ClosedRange<Double> = 0.25...0.8

    private let seed: UInt64

    public init(seed: UInt64) {
        self.seed = seed
    }

    public func sight(depth: Int, cellX: Int, cellY: Int) -> Sight? {
        let mixed = seed &+ 0x5167_4854 &+ UInt64(bitPattern: Int64(depth)) &* 0x2F2F_2F2F
            &+ UInt64(bitPattern: Int64(cellX)) &* 0x9E37_79B1
            &+ UInt64(bitPattern: Int64(cellY)) &* 0x85EB_CA77
        var random = SeededRandom(seed: mixed)
        let spec = Self.depths[depth]
        guard Double.random(in: 0..<1, using: &random) < spec.chance else { return nil }
        let inCell = SIMD2(Double.random(in: 0..<1, using: &random), Double.random(in: 0..<1, using: &random))
        return Sight(
            kind: spec.kind,
            position: (SIMD2(Double(cellX), Double(cellY)) + inCell) * spec.cellSize,
            radius: Double.random(in: spec.radii, using: &random),
            seed: Double.random(in: 1...9.99, using: &random),
            colourSet: Int.random(in: 0..<spec.colourSets, using: &random),
            tilt: Double.random(in: 0..<Double.pi, using: &random),
            flatness: Double.random(in: Self.flatnesses, using: &random)
        )
    }
}
