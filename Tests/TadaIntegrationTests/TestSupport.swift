import Foundation
@testable import Tada

/// Creates an isolated UserDefaults for tests so they never touch the user's real API key.
func testUserDefaults() -> UserDefaults {
    let suiteName = "TadaTestUserDefaults" + UUID().uuidString
    return UserDefaults(suiteName: suiteName)!
}
