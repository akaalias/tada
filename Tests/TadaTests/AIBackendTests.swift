import Testing
import Foundation
@testable import Tada

@Suite(.serialized)
struct AIBackendTests {
    @Test func defaults_to_claude() {
        let defaults = UserDefaults(suiteName: "ai-backend-\(UUID())")!
        AIBackendPreference._setTestingStorage(defaults)
        #expect(AIBackendPreference.selected == .claude)
    }

    @Test func persists_selection() {
        let defaults = UserDefaults(suiteName: "ai-backend-\(UUID())")!
        AIBackendPreference._setTestingStorage(defaults)
        AIBackendPreference.selected = .onDevice
        #expect(AIBackendPreference.selected == .onDevice)
    }

    @Test func claude_stays_claude_regardless_of_availability() {
        let defaults = UserDefaults(suiteName: "ai-backend-\(UUID())")!
        AIBackendPreference._setTestingStorage(defaults)
        AIBackendPreference.selected = .claude
        #expect(AIBackendPreference.resolved(isOnDeviceAvailable: true) == .claude)
        #expect(AIBackendPreference.resolved(isOnDeviceAvailable: false) == .claude)
    }

    @Test func onDevice_falls_back_to_claude_when_unavailable() {
        let defaults = UserDefaults(suiteName: "ai-backend-\(UUID())")!
        AIBackendPreference._setTestingStorage(defaults)
        AIBackendPreference.selected = .onDevice
        #expect(AIBackendPreference.resolved(isOnDeviceAvailable: true) == .onDevice)
        #expect(AIBackendPreference.resolved(isOnDeviceAvailable: false) == .claude)
    }
}
