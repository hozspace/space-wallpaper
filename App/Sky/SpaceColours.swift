import simd

enum SpaceColours {
    static let space = Palette.colour(64)

    /// Pairs of dark, muted tints a cloud blends between. Matches `Tour.nebulaTints`.
    static let nebulaTints: [(SIMD4<Float>, SIMD4<Float>)] = [
        [40, 39], [12, 13], [27, 63], [38, 39], [18, 17], [53, 15],
    ].map { (Palette.colour($0[0]), Palette.colour($0[1])) }
}
