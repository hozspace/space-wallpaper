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

    @Test func onlyOneHeroFitsOnScreenAtATime() {
        let tour = Tour(seed: 18)
        let screenWidth = 1680.0
        for i in 0..<200 {
            let a = tour.place(i)
            let b = tour.place(i + 1)
            #expect(simd_distance(a.position, b.position) - a.radius - b.radius >= screenWidth)
        }
    }

    @Test func evenRingedWorldsHaveAFullDisplayOfSpaceBetweenThem() {
        for width in [1280.0, 1680, 2560] {
            let tour = Tour(seed: 81, minimumGap: width)
            for i in 0..<100 {
                let a = tour.place(i), b = tour.place(i + 1)
                #expect(b.position.x - a.position.x - a.reach - b.reach >= width - 0.00001)
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
        #expect(DistantPlanets.depths.allSatisfy { $0.parallax > 0 && $0.parallax < 0.25 })
    }

    @Test func aPlanetStaysInsideItsCell() {
        let sky = DistantPlanets(seed: 2)
        let size = DistantPlanets.cellSize
        for x in 0..<100 {
            guard let planet = sky.planet(depth: 0, cellX: x, cellY: 7) else { continue }
            #expect(planet.position.x >= Double(x) * size && planet.position.x < Double(x + 1) * size)
            #expect(planet.position.y >= 7 * size && planet.position.y < 8 * size)
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
    @Test func theShipPassesEveryPlanetWithoutCrossingIt() {
        for seed in [UInt64(71), 72, 73] {
            let tour = Tour(seed: seed)
            var ship = FlyingShip(position: SIMD2(tour.place(0).position.x, tour.place(0).cruiseHeight), heading: 0, speed: FlyingShip.topSpeed)
            for leg in 1...40 {
                let place = tour.place(leg)
                while ship.position.x < place.position.x {
                    ship = ship.steppedLevel(towardHeight: place.cruiseHeight, remaining: place.position.x - ship.position.x, delta: 1.0 / 30.0)
                    for near in [tour.place(leg - 1), place] {
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

private func flyLeg(_ leg: Int, on tour: Tour, from start: FlyingShip, each: (FlyingShip) -> Void) -> FlyingShip {
    var ship = start
    let place = tour.place(leg)
    while ship.position.x < place.position.x {
        ship = ship.steppedOnRoute(tour, leg: leg, delta: 1.0 / 30.0)
        each(ship)
    }
    return ship
}

@Suite struct MeteorTests {
    @Test func theShipFliesRoundEveryBelt() {
        for seed in [UInt64(81), 82, 83] {
            let tour = Tour(seed: seed)
            var ship = FlyingShip(position: SIMD2(tour.place(0).position.x, tour.place(0).cruiseHeight), heading: 0, speed: FlyingShip.topSpeed)
            for leg in 1...60 {
                let belt = tour.rockField(afterPlace: leg - 1)
                ship = flyLeg(leg, on: tour, from: ship) { ship in
                    guard let belt else { return }
                    for rock in belt.rocks {
                        #expect(simd_distance(ship.position, rock.position) > rock.radius)
                    }
                }
            }
        }
    }

    @Test func dodgingDoesNotPutTheShipIntoPlanets() {
        for seed in [UInt64(84), 85] {
            let tour = Tour(seed: seed)
            var ship = FlyingShip(position: SIMD2(tour.place(0).position.x, tour.place(0).cruiseHeight), heading: 0, speed: FlyingShip.topSpeed)
            for leg in 1...60 {
                let place = tour.place(leg)
                ship = flyLeg(leg, on: tour, from: ship) { ship in
                    #expect(simd_distance(ship.position, place.position) > place.radius + Tour.smallestClearance)
                }
            }
        }
    }

    @Test func theShipActuallyMovesAsideForABelt() throws {
        let tour = Tour(seed: 86)
        var ship = FlyingShip(position: SIMD2(tour.place(0).position.x, tour.place(0).cruiseHeight), heading: 0, speed: FlyingShip.topSpeed)
        var dodges = 0
        for leg in 1...40 {
            var steepest = 0.0
            ship = flyLeg(leg, on: tour, from: ship) { steepest = max(steepest, abs($0.heading)) }
            if tour.rockField(afterPlace: leg - 1) != nil, steepest > FlyingShip.steepestClimb { dodges += 1 }
        }
        #expect(dodges > 0)
    }

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
