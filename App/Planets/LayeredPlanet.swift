import Metal
import SpaceCore
import simd

enum LayerShader: String, CaseIterable {
    case ground = "ground_fragment"
    case craters = "craters_fragment"
    case under = "under_fragment"
    case dry = "dry_fragment"
    case land = "land_fragment"
    case riverLand = "river_land_fragment"
    case lavaRivers = "lava_rivers_fragment"
    case lakes = "lakes_fragment"
    case clouds = "clouds_fragment"
}

struct PlanetLayerParams {
    var pixels: Float
    var rotation: Float
    var light: SIMD2<Float>
    var time: Float
    var seed: Float
    var size: Float
    var border1: Float
    var border2: Float
    var cutoff: Float
    var stretch: Float
    var ditherSize: Float
    var octaves: Int32
    var colours: (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>, SIMD4<Float>)
}

/// One layer as PixelPlanets sets it up. `speed` is its script's update_time multiplier.
private struct LayerRecipe {
    let shader: LayerShader
    let size: Float
    let octaves: Int32
    let speed: Float
    var border1: Float = 0
    var border2: Float = 0
    /// A range lets cloud cover vary from planet to planet.
    var cutoff: ClosedRange<Float> = 0...0
    var stretch: Float = 1
    var ditherSize: Float = 0
    let colours: Range<Int>
}

private struct PlanetRecipe {
    let pace: Float
    let colourSets: [[Int]]
    let layers: [LayerRecipe]
}

/// Every planet type but the ringed one: a stack of layers from a recipe.
@MainActor
final class LayeredPlanet: Planet {
    private static func recipe(for kind: PlaceKind) -> PlanetRecipe? {
        switch kind {
        case .rocky:
            return PlanetRecipe(
                pace: 0.005,
                colourSets: [[7, 5, 4, 5, 4], [19, 18, 17, 18, 17], [10, 11, 12, 11, 12]],
                layers: [
                    LayerRecipe(shader: .ground, size: 8, octaves: 4, speed: 0.02, border1: 0.615, border2: 0.729, ditherSize: 1, colours: 0..<3),
                    LayerRecipe(shader: .craters, size: 5, octaves: 0, speed: 0.02, border1: 0.465, colours: 3..<5),
                ]
            )
        case .desert:
            return PlanetRecipe(
                pace: 0.01,
                colourSets: [[22, 21, 20, 19, 18], [25, 26, 27, 62, 63], [24, 21, 20, 19, 17]],
                layers: [LayerRecipe(shader: .dry, size: 8, octaves: 3, speed: 0.02, border1: 0.362, border2: 0.525, colours: 0..<5)]
            )
        case .lava:
            return PlanetRecipe(
                pace: 0.08,
                colourSets: [
                    [19, 18, 17, 18, 17, 31, 29, 26],
                    [62, 63, 16, 63, 16, 28, 60, 61],
                    [20, 19, 18, 19, 18, 30, 25, 27],
                    [4, 3, 2, 3, 2, 29, 26, 62],
                ],
                layers: [
                    LayerRecipe(shader: .ground, size: 10, octaves: 3, speed: 0.02, border1: 0.4, border2: 0.6, ditherSize: 1, colours: 0..<3),
                    LayerRecipe(shader: .craters, size: 3.5, octaves: 0, speed: 0.02, border1: 0.4, colours: 3..<5),
                    // Wide pools: thin rivers break into flickering specks at this pixel size.
                    LayerRecipe(shader: .lavaRivers, size: 10, octaves: 2, speed: 0.02, border1: 0.019, border2: 0.036, cutoff: 0.5...0.5, colours: 5..<8),
                ]
            )
        case .ocean:
            return PlanetRecipe(
                pace: 0.017,
                colourSets: [
                    [42, 41, 40, 22, 35, 36, 37, 8, 9, 10, 12],
                    [43, 42, 39, 24, 34, 36, 38, 8, 9, 10, 12],
                    [41, 40, 52, 21, 35, 37, 38, 9, 10, 11, 12],
                ],
                layers: [
                    LayerRecipe(shader: .under, size: 5.228, octaves: 3, speed: 0.02, border1: 0.4, border2: 0.6, ditherSize: 1, colours: 0..<3),
                    // Mostly sea: only the highest ground breaks the surface.
                    LayerRecipe(shader: .land, size: 4.292, octaves: 6, speed: 0.02, border1: 0.32, border2: 0.534, cutoff: 0.62...0.62, colours: 3..<7),
                    LayerRecipe(shader: .clouds, size: 7.745, octaves: 2, speed: 0.01, border1: 0.52, border2: 0.62, cutoff: 0.35...0.6, stretch: 2, colours: 7..<11),
                ]
            )
        case .earthLike:
            return PlanetRecipe(
                pace: 0.017,
                colourSets: [
                    [34, 35, 36, 37, 42, 40, 8, 9, 10, 12],
                    [35, 36, 37, 38, 41, 39, 8, 9, 10, 12],
                    [34, 35, 37, 38, 43, 41, 8, 9, 11, 12],
                ],
                layers: [
                    LayerRecipe(shader: .riverLand, size: 4.6, octaves: 6, speed: 0.02, border1: 0.287, border2: 0.476, cutoff: 0.368...0.368, ditherSize: 1, colours: 0..<6),
                    LayerRecipe(shader: .clouds, size: 7.315, octaves: 2, speed: 0.01, border1: 0.52, border2: 0.62, cutoff: 0.35...0.6, stretch: 2, colours: 6..<10),
                ]
            )
        case .ice:
            return PlanetRecipe(
                pace: 0.008,
                colourSets: [
                    [8, 9, 10, 45, 43, 41, 8, 9, 10, 11],
                    [9, 10, 11, 42, 41, 40, 9, 10, 11, 12],
                    [45, 9, 10, 43, 42, 41, 8, 9, 10, 11],
                ],
                layers: [
                    LayerRecipe(shader: .under, size: 8, octaves: 2, speed: 0.02, border1: 0.48, border2: 0.632, ditherSize: 1, colours: 0..<3),
                    LayerRecipe(shader: .lakes, size: 10, octaves: 3, speed: 0.02, border1: 0.024, border2: 0.047, cutoff: 0.55...0.55, colours: 3..<6),
                    LayerRecipe(shader: .clouds, size: 4, octaves: 4, speed: 0.01, border1: 0.566, border2: 0.781, cutoff: 0.546...0.546, stretch: 2.5, colours: 6..<10),
                ]
            )
        case .gasGiant:
            return PlanetRecipe(
                pace: 0.04,
                colourSets: [
                    [17, 17, 16, 16, 24, 20, 19, 18],
                    [13, 13, 14, 14, 9, 10, 11, 12],
                    [53, 53, 15, 15, 56, 55, 54, 53],
                ],
                layers: [
                    LayerRecipe(shader: .clouds, size: 9, octaves: 5, speed: 0.005, border1: 0.692, border2: 0.666, colours: 0..<4),
                    LayerRecipe(shader: .clouds, size: 9, octaves: 5, speed: 0.005, border1: 0.439, border2: 0.746, cutoff: 0.28...0.5, colours: 4..<8),
                ]
            )
        case .ringed, .asteroid:
            return nil
        }
    }

    let displaySize: Float
    let texture: MTLTexture
    private let painted: MTLTexture
    let pace: Float
    private let pipelines: PlanetPipelines
    private let layers: [LayerRecipe]
    private let colours: [SIMD4<Float>]
    private let pixels: Float
    private let rotation: Float
    private let seed: Float
    private let light = SIMD2<Float>(0.39, 0.39)

    init?(kind: PlaceKind, device: MTLDevice, pipelines: PlanetPipelines, size: Int, seed: Float, rotation: Float, colourSet: Int) {
        guard let recipe = Self.recipe(for: kind), let texture = PlanetTexture.make(device: device, size: PlanetTexture.surfaceSize(for: size)),
              let painted = PlanetTexture.make(device: device, size: texture.width) else { return nil }
        self.texture = texture
        self.painted = painted
        displaySize = Float(size)
        self.pipelines = pipelines
        pace = recipe.pace
        layers = recipe.layers
        colours = Palette.colours(recipe.colourSets[colourSet % recipe.colourSets.count])
        pixels = Float(texture.width)
        self.seed = seed
        self.rotation = rotation
    }

    func draw(into buffer: MTLCommandBuffer, time: Float) {
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: PlanetTexture.clearPass(painted)) else { return }
        for layer in layers {
            guard let pipeline = pipelines.layers[layer.shader] else { continue }
            var params = parameters(for: layer, time: time)
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBytes(&params, length: MemoryLayout<PlanetLayerParams>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        encoder.endEncoding()
        PlanetTexture.tidy(painted, into: texture, buffer: buffer, pipelines: pipelines)
    }

    private func parameters(for layer: LayerRecipe, time: Float) -> PlanetLayerParams {
        let own = Array(colours[layer.colours]) + Array(repeating: SIMD4<Float>.zero, count: 6 - layer.colours.count)
        // Stands in for PixelPlanets' random cloud cover, so a planet always looks the same.
        let pick = (seed * Self.coverSpread).truncatingRemainder(dividingBy: 1)
        return PlanetLayerParams(
            pixels: pixels, rotation: rotation, light: light,
            time: time * layer.size.rounded() * 2 * layer.speed,
            seed: seed, size: layer.size, border1: layer.border1, border2: layer.border2,
            cutoff: layer.cutoff.lowerBound + (layer.cutoff.upperBound - layer.cutoff.lowerBound) * pick,
            stretch: layer.stretch, ditherSize: layer.ditherSize, octaves: layer.octaves,
            colours: (own[0], own[1], own[2], own[3], own[4], own[5])
        )
    }

    private static let coverSpread: Float = 7.31
}
