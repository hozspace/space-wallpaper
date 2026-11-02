import Foundation
import SpaceCore

enum JourneyStore {
    private static let key = "journey"

    static func load() -> Journey? {
        Journey.restored(from: UserDefaults.standard.data(forKey: key))
    }

    static func save(_ journey: Journey) {
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(journey), forKey: key)
        } catch {
            NSLog("SpaceWallpaper: could not save the journey: \(error)")
        }
    }
}
