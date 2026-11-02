import Testing
import simd
@testable import SpaceCore

private let frame = 1.0 / 30.0

@Suite struct SteeringTests {
    @Test func reachesItsTarget() {
        var ship = FlyingShip(position: .zero, heading: 0, speed: 0)
        let target = SIMD2<Double>(0, 1000)
        var seconds = 0.0
        while simd_distance(ship.position, target) > 80, seconds < 120 {
            ship = ship.stepped(toward: target, delta: frame)
            seconds += frame
        }
        #expect(seconds < 120)
    }

    @Test func neverTurnsFasterThanItsLimit() {
        var ship = FlyingShip(position: .zero, heading: 0, speed: 50)
        for _ in 0..<300 {
            let next = ship.stepped(toward: SIMD2(-500, -500), delta: frame)
            #expect(abs(angleBetween(ship.heading, next.heading)) <= FlyingShip.turnRate * frame + 0.0001)
            ship = next
        }
    }

    @Test func staysAtASteadyPaceBetweenPlaces() {
        var ship = FlyingShip(position: .zero, heading: 0, speed: 0)
        for _ in 0..<600 {
            ship = ship.stepped(toward: SIMD2(100_000, 0), delta: frame)
        }
        #expect(abs(ship.speed - FlyingShip.topSpeed) < 0.01)
    }
}

@Suite struct TourTests {
    @Test func sameSeedGivesSamePlaces() {
        let first = Tour(seed: 4)
        let second = Tour(seed: 4)
        for i in 0..<40 {
            #expect(first.place(i) == second.place(i))
        }
    }

    @Test func differentSeedsDiffer() {
        #expect(Tour(seed: 1).place(3) != Tour(seed: 2).place(3))
    }

    @Test func placesNeverOverlap() {
        let tour = Tour(seed: 6)
        for i in 0..<60 {
            let a = tour.place(i)
            let b = tour.place(i + 1)
            #expect(simd_distance(a.position, b.position) > a.radius + b.radius)
        }
    }

    @Test func hasAMixOfKindsAndSomeHugeWorlds() {
        let tour = Tour(seed: 10)
        let places = (0..<200).map(tour.place)
        #expect(Set(places.map(\.kind)) == Set(PlaceKind.planets))
        #expect(PlaceKind.planets.count == 8)
        #expect(places.contains { $0.radius >= 320 })
        #expect(places.contains { $0.radius < 150 })
    }

    @Test func planetsSometimesShareTheScreen() {
        let screenWidth = 1680.0
        let tour = Tour(seed: 18, screenWidth: screenWidth)
        let gaps = (0..<200).map { i -> Double in
            let a = tour.place(i), b = tour.place(i + 1)
            return b.position.x - a.position.x - a.reach - b.reach
        }
        #expect(gaps.allSatisfy { $0 >= screenWidth * 0.45 - 0.00001 })
        #expect(gaps.contains { $0 < screenWidth * 0.8 })
        #expect(gaps.contains { $0 > screenWidth })
    }

    @Test func someOnTheRouteAndTheRestOnBothSides() {
        let tour = Tour(seed: 26)
        let offsets = (1..<300).map { tour.place($0) }.map { ($0.position.y - $0.cruiseHeight) / $0.radius }
        let under = offsets.filter { abs($0) < 1 }.count
        #expect(under > 60 && under < 130)
        #expect(offsets.filter { $0 >= 1 }.count > 60)
        #expect(offsets.filter { $0 <= -1 }.count > 60)
    }

    @Test func rocksOnlyWhereThereIsRoomForThem() {
        let tour = Tour(seed: 31)
        for i in 1..<200 {
            guard let field = tour.rockField(afterPlace: i) else { continue }
            let a = tour.place(i), b = tour.place(i + 1)
            #expect(field.rocks.allSatisfy { $0.position.x - $0.radius > a.position.x + a.reach && $0.position.x + $0.radius < b.position.x - b.reach })
        }
    }

    @Test func moonsKeepToTheirOwnPlanet() {
        let tour = Tour(seed: 44)
        for i in 1..<200 {
            let planet = tour.place(i)
            let before = tour.place(i - 1), after = tour.place(i + 1)
            for moon in tour.moons(of: i) {
                #expect(planet.position.x - moon.reach > before.position.x + before.reach)
                #expect(planet.position.x + moon.reach < after.position.x - after.reach)
            }
        }
    }

    @Test func colourSetsAlwaysFitTheirKind() {
        let tour = Tour(seed: 24)
        for i in 0..<500 {
            let place = tour.place(i)
            #expect(place.colourSet < place.kind.colourSets)
        }
    }

    @Test func neverTheSameTypeAndColourTwiceInARow() {
        let tour = Tour(seed: 22)
        for i in 0..<300 {
            let a = tour.place(i)
            let b = tour.place(i + 1)
            #expect(a.kind != b.kind || a.colourSet != b.colourSet)
        }
    }

    @Test func someLegsHaveARockFieldAndItIsRepeatable() {
        let tour = Tour(seed: 31), again = Tour(seed: 31)
        let fields = (0..<60).compactMap { tour.rockField(afterPlace: $0) }
        #expect(fields.count > 5)
        #expect(fields.count < 40)
        #expect(fields == (0..<60).compactMap { again.rockField(afterPlace: $0) })
    }

}

@Suite struct DistantPlanetTests {
    @Test func sameCellAlwaysGivesTheSameAnswer() {
        let sky = DistantPlanets(seed: 3)
        for x in -20...20 {
            #expect(sky.planet(depth: 0, cellX: x, cellY: 4) == DistantPlanets(seed: 3).planet(depth: 0, cellX: x, cellY: 4))
        }
    }

    @Test func distantPlanetsAreRare() {
        let sky = DistantPlanets(seed: 5)
        let found = (0..<400).compactMap { sky.planet(depth: 0, cellX: $0, cellY: -$0 / 2) }.count
        #expect(found > 25)
        #expect(found < 120)
    }

    @Test func distantWorldsStaySmallAndMoveSlowerThanTheRoute() {
        let sky = DistantPlanets(seed: 9)
        let far = (0..<400).compactMap { sky.planet(depth: 0, cellX: $0, cellY: 1) }
        #expect(!far.isEmpty)
        #expect(far.allSatisfy { $0.radius <= 24 })
        #expect(DistantPlanets.depths.allSatisfy { $0.parallax > 0 && $0.parallax < 1 })
        #expect(DistantPlanets.depths.map(\.parallax) == DistantPlanets.depths.map(\.parallax).sorted())
    }

    @Test func aPlanetStaysInsideItsCell() {
        let sky = DistantPlanets(seed: 2)
        for (depth, spec) in DistantPlanets.depths.enumerated() {
            let size = spec.cellSize
            for x in 0..<100 {
                guard let planet = sky.planet(depth: depth, cellX: x, cellY: 7) else { continue }
                #expect(planet.position.x >= Double(x) * size && planet.position.x < Double(x + 1) * size)
                #expect(planet.position.y >= 7 * size && planet.position.y < 8 * size)
            }
        }
    }
}

@Suite struct NebulaTests {
    @Test func sameSeedGivesTheSameClouds() {
        let first = Tour(seed: 31)
        let second = Tour(seed: 31)
        for i in 0..<60 {
            #expect(first.nebula(afterPlace: i) == second.nebula(afterPlace: i))
        }
    }

    @Test func someStretchesAreCloudyAndSomeAreDeepBlack() {
        let tour = Tour(seed: 33)
        let found = (0..<300).compactMap { tour.nebula(afterPlace: $0) }.count
        #expect(found > 80)
        #expect(found < 220)
    }

    @Test func aCloudSitsOnTheShipsPath() {
        let tour = Tour(seed: 35)
        for i in 0..<100 {
            guard let nebula = tour.nebula(afterPlace: i) else { continue }
            let from = tour.place(i).position
            let to = tour.place(i + 1).position
            let along = simd_dot(nebula.centre - from, simd_normalize(to - from))
            let line = from + simd_normalize(to - from) * along
            #expect(simd_distance(line, nebula.centre) < nebula.radius / 2)
        }
    }

    @Test func cloudsComeInEveryColour() {
        let tour = Tour(seed: 37)
        let tints = Set((0..<300).compactMap { tour.nebula(afterPlace: $0)?.tint })
        #expect(tints.count == Tour.nebulaTints)
    }
}

@Suite struct FlatRouteTests {
    @Test func theShipNeverTurnsBack() {
        let tour = Tour(seed: 53)
        for i in 0..<300 {
            #expect(tour.place(i + 1).position.x > tour.place(i).position.x)
        }
    }
}

@Suite struct LevelFlightTests {
    private let frame = 1.0 / 30.0

    @Test func staysLevelUntilItNearsThePlace() {
        var ship = FlyingShip(position: .zero, heading: 0, speed: FlyingShip.topSpeed)
        for _ in 0..<300 {
            ship = ship.steppedLevel(towardHeight: 300, remaining: 5000, delta: frame)
            #expect(abs(ship.heading) < 0.001)
        }
    }

    @Test func climbsGentlyWhenClose() {
        var ship = FlyingShip(position: .zero, heading: 0, speed: FlyingShip.topSpeed)
        var moved = false
        for _ in 0..<3000 {
            ship = ship.steppedLevel(towardHeight: 300, remaining: 200, delta: frame)
            moved = moved || ship.position.y > 50
            #expect(abs(ship.heading) <= FlyingShip.steepestClimb + 0.01)
        }
        #expect(moved)
    }

    @Test func levelsOutOnceAtItsHeight() {
        var ship = FlyingShip(position: .zero, heading: 0, speed: FlyingShip.topSpeed)
        for _ in 0..<9000 {
            ship = ship.steppedLevel(towardHeight: 100, remaining: 200, delta: frame)
        }
        #expect(abs(ship.heading) < 0.02)
    }

    @Test func spendsMostOfALongFlightLevel() {
        let tour = Tour(seed: 61)
        var ship = FlyingShip(position: tour.place(0).position, heading: 0, speed: FlyingShip.topSpeed)
        var frames = 0
        var level = 0
        for leg in 1...20 {
            let place = tour.place(leg)
            while ship.position.x < place.position.x {
                ship = ship.steppedLevel(towardHeight: place.cruiseHeight, remaining: place.position.x - ship.position.x, delta: frame)
                frames += 1
                if abs(ship.heading) < 0.03 { level += 1 }
            }
        }
        #expect(Double(level) / Double(frames) > 0.6)
    }
}

@Suite struct PassingPlanetsTests {
    @Test func theShipPassesBesideEveryPlanetNotUnderItWithoutCrossingIt() {
        for seed in [UInt64(71), 72, 73] {
            let tour = Tour(seed: seed)
            var ship = FlyingShip(position: SIMD2(tour.place(0).position.x, tour.place(0).cruiseHeight), heading: 0, speed: FlyingShip.topSpeed)
            for leg in 1...40 {
                let place = tour.place(leg)
                while ship.position.x < place.position.x {
                    ship = ship.steppedLevel(towardHeight: place.cruiseHeight, remaining: place.position.x - ship.position.x, delta: 1.0 / 30.0)
                    for near in [tour.place(leg - 1), place] where abs(near.position.y - near.cruiseHeight) >= near.radius {
                        #expect(simd_distance(ship.position, near.position) > near.radius + Tour.smallestClearance)
                    }
                }
            }
        }
    }

    @Test func planetsPassBothAboveAndBelow() {
        let tour = Tour(seed: 75)
        let sides = (1..<100).map { tour.place($0).position.y > tour.place($0).cruiseHeight }
        #expect(sides.contains(true))
        #expect(sides.contains(false))
    }
}

@Suite struct MeteorTests {
    @Test func aBeltIsALongBandAcrossTheRoute() throws {
        let tour = Tour(seed: 87)
        let belt = try #require((0..<60).lazy.compactMap { tour.rockField(afterPlace: $0) }.first)
        #expect(belt.rocks.count >= 25)
        #expect(Set(belt.rocks.map(\.seed)).count == belt.rocks.count)
        #expect(belt.rocks.allSatisfy { simd_distance($0.position, belt.centre) + $0.radius <= belt.radius + 0.001 })
        #expect(belt.rocks.contains { $0.position.y < belt.centre.y - 150 })
        #expect(belt.rocks.contains { $0.position.y > belt.centre.y + 150 })
    }

    @Test func mostRocksAreSmall() {
        let tour = Tour(seed: 89)
        let rocks = (0..<80).compactMap { tour.rockField(afterPlace: $0) }.flatMap(\.rocks)
        let small = rocks.filter { $0.radius < 30 }.count
        #expect(small * 2 > rocks.count)
        #expect(rocks.contains { $0.radius > 40 })
    }

    @Test func theGapIsClearOfRocks() {
        let tour = Tour(seed: 90)
        for index in 0..<80 {
            guard let belt = tour.rockField(afterPlace: index) else { continue }
            for rock in belt.rocks where abs(rock.position.x - belt.centre.x) < 60 {
                #expect(abs(rock.position.y - belt.centre.y) > rock.radius + 20)
            }
        }
    }

    @Test func beltsAndPlanetsDoNotTouch() {
        let tour = Tour(seed: 88)
        for index in 0..<100 {
            guard let belt = tour.rockField(afterPlace: index) else { continue }
            #expect(simd_distance(belt.centre, tour.place(index).position) > belt.radius + tour.place(index).reach)
            #expect(simd_distance(belt.centre, tour.place(index + 1).position) > belt.radius + tour.place(index + 1).reach)
        }
    }
}

@Suite struct MoonTests {
    @Test func someWorldsHaveMoonsAndRingedOnesNever() {
        let tour = Tour(seed: 12)
        let counts = (1..<80).map { tour.moons(of: $0).count }
        #expect(counts.contains { $0 > 0 })
        #expect(counts.contains(0))
        for i in 1..<80 where tour.place(i).kind == .ringed {
            #expect(tour.moons(of: i).isEmpty)
        }
    }

    @Test func moonsStayClearOfTheShipsPath() {
        let tour = Tour(seed: 3)
        for i in 1..<80 {
            let planet = tour.place(i)
            guard abs(planet.position.y - planet.cruiseHeight) >= planet.radius else { continue }
            for moon in tour.moons(of: i) {
                for second in stride(from: 0.0, to: abs(moon.period), by: 1) {
                    let centre = planet.position + moon.offset(at: second).position
                    #expect(abs(centre.y - planet.cruiseHeight) - moon.radius >= Tour.moonClearance)
                }
            }
        }
    }

    @Test func moonsGoBehindOnTheFarSide() {
        let moon = Moon(index: 0, kind: .rocky, radius: 10, seed: 1, colourSet: 0, paint: .preset, orbit: 100, flatness: 0.3, tilt: 0, period: 40, phase: 0)
        let far = moon.offset(at: 30)
        let near = moon.offset(at: 10)
        #expect(far.isBehind && far.position.y < 0)
        #expect(!near.isBehind && near.position.y > 0)
    }

    @Test func secondMoonOrbitsOutsideTheFirst() {
        let tour = Tour(seed: 21)
        for i in 1..<120 {
            let moons = tour.moons(of: i)
            guard moons.count == 2 else { continue }
            #expect(moons[1].orbit - moons[1].radius > moons[0].orbit + moons[0].radius)
        }
    }
}

@Suite struct MoonLookTests {
    @Test func warmWorldsNeverGetIcyMoons() {
        let tour = Tour(seed: 5)
        for i in 1..<150 where Tone(kind: tour.place(i).kind, colourSet: tour.place(i).colourSet) == .warm {
            #expect(tour.moons(of: i).allSatisfy { $0.kind != .ice && $0.kind != .lava })
        }
    }

    @Test func blueAndWhiteWorldsAreTheMinority() {
        let tour = Tour(seed: 9)
        let cool = (0..<300).filter { [.ocean, .earthLike, .ice].contains(tour.place($0).kind) }.count
        #expect(cool < 90)
    }
}

@Suite struct PaintTests {
    private static let layout: [PlaceKind: Int] = [
        .rocky: 5, .desert: 5, .lava: 8, .ocean: 11, .earthLike: 10, .ice: 10, .gasGiant: 8, .ringed: 6,
    ]

    @Test func madeUpPalettesFitEachKindsShaders() {
        for (kind, count) in Self.layout {
            for seed in UInt64(0)..<50 {
                let colours = PlanetPaint.generated(seed: seed).colours(for: kind) ?? []
                #expect(colours.count == count)
                #expect(colours.allSatisfy { all($0 .>= 0) && all($0 .<= 1) && HSV($0).saturation <= 0.72 + 0.0001 })
            }
        }
    }

    @Test func aWorldsColoursStayCloseInHue() {
        for kind in Self.layout.keys {
            for seed in UInt64(0)..<50 {
                let colours = PlanetPaint.generated(seed: seed).colours(for: kind) ?? []
                let main = HSV(colours[0]).hue
                #expect(colours.allSatisfy { HSV($0).saturation < 0.02 || abs(PlanetPaint.hueOffset(from: main, to: HSV($0).hue)) <= PlanetPaint.widestHueSpread + 0.001 })
            }
        }
    }

    @Test func eachKindKeepsToItsColourRange() {
        for kind in Self.layout.keys {
            for seed in UInt64(0)..<50 {
                let main = PlanetPaint.generated(seed: seed).colours(for: kind)![0]
                #expect(HSV(main).saturation < 0.02 || kind.hueRange.contains(HSV(main).hue))
            }
        }
    }

    @Test func sameSeedSamePalette() {
        #expect(PlanetPaint.generated(seed: 7).colours(for: .desert) == PlanetPaint.generated(seed: 7).colours(for: .desert))
        #expect(PlanetPaint.generated(seed: 7).colours(for: .desert) != PlanetPaint.generated(seed: 8).colours(for: .desert))
    }

    @Test func mostWorldsGetTheirOwnColours() {
        let tour = Tour(seed: 3)
        let paints = (0..<300).map { tour.place($0).paint }
        let generated = paints.filter { if case .generated = $0 { true } else { false } }.count
        let preset = paints.filter { $0 == .preset }.count
        #expect(generated > 140 && generated < 220)
        #expect(preset > 20 && preset < 110)
    }

    @Test func hueSurvivesTheRoundTrip() {
        let colour = SIMD3<Double>(0.8, 0.3, 0.6)
        #expect(simd_distance(HSV(colour).rgb, colour) < 0.0001)
    }
}
