import Foundation

/// Everything needed to carry on the same route after a restart.
public struct Journey: Codable, Sendable, Equatable {
    public let seed: UInt64
    /// Planet spacing depends on this, so a different screen can't change a saved route.
    public let spacing: Double
    public let leg: Int

    public init(seed: UInt64, spacing: Double, leg: Int = 1) {
        self.seed = seed
        self.spacing = spacing
        self.leg = leg
    }

    public func makeTour() -> Tour {
        Tour(seed: seed, minimumGap: spacing)
    }

    public func reaching(leg newLeg: Int) -> Journey {
        Journey(seed: seed, spacing: spacing, leg: max(leg, newLeg))
    }

    public static func restored(from data: Data?) -> Journey? {
        guard let data, let journey = try? JSONDecoder().decode(Journey.self, from: data),
              journey.spacing > 0, journey.leg >= 1 else { return nil }
        return journey
    }
}
