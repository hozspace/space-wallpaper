import Foundation
import simd

/// The shortest signed turn from one heading to another.
func angleBetween(_ from: Double, _ to: Double) -> Double {
    atan2(sin(to - from), cos(to - from))
}

/// A ship that turns and accelerates gradually. Distances are art pixels, angles radians.
public struct FlyingShip: Sendable, Equatable {
    public static let topSpeed = 16.0
    public static let acceleration = 4.0
    public static let turnRate = 0.28
    public static let steepestClimb = 0.16
    public static let steepestDodge = 0.45
    public static let climbDistance = 700.0
    private static let levelLookAhead = 500.0
    // A far aim point only ever eases towards a height; a dodge has to get there.
    private static let dodgeLookAhead = 150.0

    public let position: SIMD2<Double>
    public let heading: Double
    public let speed: Double

    public init(position: SIMD2<Double>, heading: Double, speed: Double) {
        self.position = position
        self.heading = heading
        self.speed = speed
    }

    /// Holds its height and only eases up or down near the next place.
    public func steppedLevel(towardHeight height: Double, remaining: Double, delta: Double) -> FlyingShip {
        let wanted = remaining < Self.climbDistance ? height : position.y
        return stepped(towardHeight: wanted, steepest: Self.steepestClimb, lookAhead: Self.levelLookAhead, delta: delta)
    }

    public func steppedOnRoute(_ tour: Tour, leg: Int, delta: Double) -> FlyingShip {
        let goal = tour.flightGoal(shipX: position.x, leg: leg)
        if goal.isUrgent {
            return stepped(towardHeight: goal.height, steepest: Self.steepestDodge, lookAhead: Self.dodgeLookAhead, delta: delta)
        }
        return steppedLevel(towardHeight: goal.height, remaining: tour.place(leg).position.x - position.x, delta: delta)
    }

    public func stepped(toward target: SIMD2<Double>, delta: Double) -> FlyingShip {
        let toTarget = target - position
        let wanted = simd_length(toTarget) > 0 ? atan2(toTarget.y, toTarget.x) : heading
        let limit = Self.turnRate * delta
        let newHeading = heading + min(max(angleBetween(heading, wanted), -limit), limit)
        let change = Self.acceleration * delta
        let newSpeed = speed + min(max(Self.topSpeed - speed, -change), change)
        let direction = SIMD2(cos(newHeading), sin(newHeading))
        return FlyingShip(position: position + direction * newSpeed * delta, heading: newHeading, speed: newSpeed)
    }

    private func stepped(towardHeight height: Double, steepest: Double, lookAhead: Double, delta: Double) -> FlyingShip {
        let limit = lookAhead * tan(steepest)
        let rise = min(max(height - position.y, -limit), limit)
        return stepped(toward: position + SIMD2(lookAhead, rise), delta: delta)
    }
}
