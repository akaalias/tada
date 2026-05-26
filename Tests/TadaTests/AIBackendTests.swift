import XCTest
@testable import Tada

final class AIBackendTests: XCTestCase {
    private var defaults: UserDefaults!
    private let suiteName = "AIBackendTests"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        AIBackendPreference._setTestingStorage(defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        AIBackendPreference._setTestingStorage(.standard)
        super.tearDown()
    }

    func test_defaultBackend_isClaude() {
        XCTAssertEqual(AIBackendPreference.selected, .claude)
    }

    func test_selection_persists() {
        AIBackendPreference.selected = .onDevice
        XCTAssertEqual(AIBackendPreference.selected, .onDevice)
    }

    func test_resolved_claudeStaysClaude_regardlessOfAvailability() {
        AIBackendPreference.selected = .claude
        XCTAssertEqual(AIBackendPreference.resolved(isOnDeviceAvailable: true), .claude)
        XCTAssertEqual(AIBackendPreference.resolved(isOnDeviceAvailable: false), .claude)
    }

    func test_resolved_onDeviceFallsBackToClaude_whenUnavailable() {
        AIBackendPreference.selected = .onDevice
        XCTAssertEqual(AIBackendPreference.resolved(isOnDeviceAvailable: true), .onDevice)
        XCTAssertEqual(AIBackendPreference.resolved(isOnDeviceAvailable: false), .claude)
    }
}
