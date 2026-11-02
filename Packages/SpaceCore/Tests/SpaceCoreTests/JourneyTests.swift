import Foundation
import Testing
@testable import SpaceCore

@Suite struct JourneyTests {
    @Test func aNewJourneyHeadsForTheSecondPlanet() {
        let journey = Journey(seed: 7, spacing: 1680)
        #expect(journey.leg == 1)
    }

    @Test func survivesBeingSavedWithAnySeed() throws {
        let journey = Journey(seed: .max, spacing: 1680, leg: 42)
        let restored = Journey.restored(from: try JSONEncoder().encode(journey))
        #expect(restored == journey)
    }

    @Test func aResumedRouteHasTheSamePlaces() throws {
        let journey = Journey(seed: 11, spacing: 1680, leg: 30)
        let restored = try #require(Journey.restored(from: try JSONEncoder().encode(journey)))
        let before = journey.makeTour(), after = restored.makeTour()
        for index in 0..<40 {
            #expect(before.place(index) == after.place(index))
        }
    }

    @Test func reachingAPlaceNeverMovesItBackwards() {
        let journey = Journey(seed: 1, spacing: 1680, leg: 5)
        #expect(journey.reaching(leg: 6).leg == 6)
        #expect(journey.reaching(leg: 3).leg == 5)
        #expect(journey.leg == 5)
    }

    @Test(arguments: [
        #"{"seed":1,"spacing":1680,"leg":0}"#,
        #"{"seed":1,"spacing":0,"leg":3}"#,
        #"{"seed":1,"spacing":1680,"leg":-2}"#,
        #"{"spacing":1680,"leg":3}"#,
        "not json",
    ])
    func refusesASaveItCannotUse(saved: String) {
        #expect(Journey.restored(from: Data(saved.utf8)) == nil)
    }

    @Test func nothingSavedMeansNothingRestored() {
        #expect(Journey.restored(from: nil) == nil)
    }
}
