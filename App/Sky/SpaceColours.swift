import simd

enum SpaceColours {
    static let space = Palette.colour(64)

    /// Pairs of tints a cloud blends between. Matches `Tour.nebulaTints`.
    static let nebulaTints: [(SIMD4<Float>, SIMD4<Float>)] = [
        [41, 38], [54, 53], [26, 62], [37, 38], [56, 54], [24, 26],
    ].map { (Palette.colour($0[0]), Palette.colour($0[1])) }
}
