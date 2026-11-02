import Metal
import SpaceCore
import simd

/// Every planet near the view: close ones on the ship's route, distant ones far behind.
@MainActor
final class PlanetField {
    struct Visible {
        let planet: Planet
        let centre: SIMD2<Float>
        let brightness: Float
        var angle: Float = 0
    }

    private struct Key: Hashable {
        /// -1 for the route; otherwise an index into the distant depths.
        let depth: Int
        let a: Int
        let b: Int
    }

    private struct Entry {
        let planet: Planet
        let timeOffset: Float
        var hasDrawn = false
    }

    private static let longestTimeOffset: Float = 1000
    /// Room around the view, so planets exist before they drift into sight.
    private static let margin = 500.0
    private static let rockDepth = -2
    private static let moonDepth = -3
    /// Moons keep their planets' chunky pixels, however small they are.
    private static let smallestMoonSurface = 8

    private let device: MTLDevice
    private let pipelines: PlanetPipelines
    private let distant: DistantPlanets
    private var entries: [Key: Entry] = [:]
    private var clock: Float = 0

    init(device: MTLDevice, pipelines: PlanetPipelines, seed: UInt64) {
        self.device = device
        self.pipelines = pipelines
        distant = DistantPlanets(seed: seed)
    }

    func setClock(_ time: Float) { clock = time }

    static func timeOffset(for place: Place) -> Float { Float(place.seed) / 10 * longestTimeOffset }

    /// Farthest first, in draw order. Planets are built on arrival and let go on leaving.
    func visible(flight: Flight, view: SIMD2<Float>, delta: Float) -> [Visible] {
        clock += delta
        let camera = flight.camera
        let halfView = SIMD2<Double>(view) / 2
        var kept: [Key: Entry] = [:]
        var shown: [Visible] = []

        for (depthIndex, depth) in DistantPlanets.depths.enumerated() {
            let middle = camera * depth.parallax
            let reach = halfView + Self.margin
            let low = ((middle - reach) / depth.cellSize).rounded(.down)
            let high = ((middle + reach) / depth.cellSize).rounded(.down)
            for x in Int(low.x)...Int(high.x) {
                for y in Int(low.y)...Int(high.y) {
                    guard let place = distant.planet(depth: depthIndex, cellX: x, cellY: y) else { continue }
                    let key = Key(depth: depthIndex, a: x, b: y)
                    guard let entry = entry(for: key, place: place) else { continue }
                    kept[key] = entry
                    let centre = SIMD2<Float>(place.position - middle + halfView)
                    shown.append(Visible(planet: entry.planet, centre: centre, brightness: Float(depth.brightness)))
                }
            }
        }

        for fieldIndex in max(flight.leg - 2, 0)...flight.leg {
            guard let field = flight.tour.rockField(afterPlace: fieldIndex) else { continue }
            let centre = field.centre - camera + halfView
            guard abs(centre.x - halfView.x) < halfView.x + field.radius + Self.margin else { continue }
            for rock in field.rocks {
                let key = Key(depth: Self.rockDepth, a: fieldIndex, b: rock.index)
                guard let entry = entry(for: key, place: rock) else { continue }
                kept[key] = entry
                shown.append(Visible(planet: entry.planet, centre: SIMD2<Float>(rock.position - camera + halfView), brightness: 1, angle: entry.timeOffset + clock * entry.planet.pace))
            }
        }

        for index in max(flight.leg - 2, 0)...(flight.leg + 1) {
            let place = flight.tour.place(index)
            let moons = flight.tour.moons(of: index)
            let centre = place.position - camera + halfView
            let reach = moons.map(\.reach).reduce(place.reach, max) + Self.margin
            guard abs(centre.x - halfView.x) < halfView.x + reach,
                  abs(centre.y - halfView.y) < halfView.y + reach else { continue }
            let key = Key(depth: -1, a: index, b: 0)
            guard let planetEntry = entry(for: key, place: place) else { continue }
            kept[key] = planetEntry
            var inFront: [Visible] = []
            for moon in moons {
                let moonKey = Key(depth: Self.moonDepth, a: index, b: moon.index)
                guard let moonEntry = entry(for: moonKey, place: moon.world, smallestSurface: Self.smallestMoonSurface) else { continue }
                kept[moonKey] = moonEntry
                let (offset, isBehind) = moon.offset(at: Double(clock))
                let visible = Visible(planet: moonEntry.planet, centre: SIMD2<Float>(centre + offset), brightness: 1)
                if isBehind { shown.append(visible) } else { inFront.append(visible) }
            }
            shown.append(Visible(planet: planetEntry.planet, centre: SIMD2<Float>(centre), brightness: 1))
            shown += inFront
        }
        entries = kept
        return shown
    }

    func redraw(_ shown: [Visible], view: SIMD2<Float>, into buffer: MTLCommandBuffer, animate: Bool) {
        for item in shown {
            let half = item.planet.displaySize / 2
            let isOnScreen = item.centre.x + half > 0 && item.centre.x - half < view.x && item.centre.y + half > 0 && item.centre.y - half < view.y
            guard let key = entries.first(where: { $0.value.planet === item.planet })?.key,
                  var entry = entries[key], !entry.hasDrawn || (animate && isOnScreen && !item.planet.isTumbling) else { continue }
            item.planet.draw(into: buffer, time: entry.timeOffset + clock * item.planet.pace)
            entry.hasDrawn = true
            entries[key] = entry
        }
    }

    private func entry(for key: Key, place: Place, smallestSurface: Int = PlanetTexture.smallestSurface) -> Entry? {
        if let existing = entries[key] {
            return existing
        }
        guard let planet = PlanetMaker.make(place, size: Int(place.radius * 2), smallestSurface: smallestSurface, device: device, pipelines: pipelines) else {
            NSLog("SpaceWallpaper: could not make a planet texture")
            return nil
        }
        return Entry(planet: planet, timeOffset: Self.timeOffset(for: place))
    }
}

enum PlanetMaker {
    @MainActor
    static func make(_ place: Place, size: Int, smallestSurface: Int, device: MTLDevice, pipelines: PlanetPipelines) -> Planet? {
        let seed = Float(place.seed)
        if place.kind == .asteroid {
            return Asteroid(device: device, pipelines: pipelines, size: size, seed: seed, rotation: Float(place.rotation), colourSet: place.colourSet)
        }
        if place.kind == .ringed {
            // Rings read best close to level.
            let tilt = -0.25 - Float(place.rotation / (2 * .pi)) * 0.2
            return RingedPlanet(device: device, pipelines: pipelines, size: size, seed: seed, rotation: tilt, colourSet: place.colourSet, paint: place.paint)
        }
        // Turning about a nearly upright axis, the way a planet spins, rather than any old way.
        let tilt = (Float(place.rotation / (2 * .pi)) - 0.5) * 0.7
        return LayeredPlanet(kind: place.kind, device: device, pipelines: pipelines, size: size, smallestSurface: smallestSurface, seed: seed, rotation: tilt, colourSet: place.colourSet, paint: place.paint)
    }
}
