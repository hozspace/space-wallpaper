import Foundation
import SpaceCore
import simd

/// The ship on its tour, and the camera following it. Positions are art pixels in the world.
@MainActor
final class Flight {
    /// The camera catches up at this rate, so the ship swings about the frame as it turns.
    private static let cameraCatchUp = 0.4
    /// A slight, slow wander around the middle of the screen, so the ship doesn't look pinned there.
    private static let wander = SIMD2<Double>(24, 14)
    private static let startClearance = 150.0
    private static let wanderRates = SIMD2<Double>(0.012, 0.017)

    let tour: Tour
    private let startedOn: Journey
    private(set) var leg: Int
    private(set) var elapsed = 0.0
    private(set) var ship: FlyingShip
    private(set) var camera: SIMD2<Double>
    /// From 0 to 1.
    private(set) var turning = 0.0

    init(journey: Journey, viewWidth: Double) {
        startedOn = journey
        leg = journey.leg
        tour = journey.makeTour()
        let first = tour.place(journey.leg - 1)
        // Just clear of the last planet reached, so the journey opens beside it.
        let start = SIMD2(first.position.x - max(first.radius + Self.startClearance, viewWidth * 0.42), first.cruiseHeight)
        ship = FlyingShip(position: start, heading: 0, speed: FlyingShip.topSpeed)
        camera = start
    }

    var journey: Journey { startedOn.reaching(leg: leg) }

    var nebulasNearby: [Nebula] {
        (max(leg - 3, 0)...(leg + 1)).compactMap { tour.nebula(afterPlace: $0) }
    }

    func advance(by delta: Double) {
        elapsed += delta
        let before = ship.heading
        let place = tour.place(leg)
        // Straight over any meteors: the ship only changes height for the planets.
        ship = ship.steppedLevel(towardHeight: place.cruiseHeight, remaining: place.position.x - ship.position.x, delta: delta)
        if delta > 0 {
            turning = min(abs(ship.heading - before) / (FlyingShip.turnRate * delta), 1)
        }
        if ship.position.x >= place.position.x {
            leg += 1
        }
        let drift = SIMD2(sin(elapsed * Self.wanderRates.x), sin(elapsed * Self.wanderRates.y)) * Self.wander
        let wanted = ship.position + drift
        camera += (wanted - camera) * (1 - exp(-Self.cameraCatchUp * delta))
    }
}
