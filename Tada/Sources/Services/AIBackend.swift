import Foundation

/// Which engine powers AI generation: the remote Claude API or Apple's on-device
/// foundation model.
enum AIBackend: String, CaseIterable, Codable {
    case claude
    case onDevice = "on_device"

    var displayName: String {
        switch self {
        case .claude: return "Claude API (remote)"
        case .onDevice: return "Apple On-Device"
        }
    }
}

/// The user's chosen AI backend, persisted in UserDefaults. Mirrors `ModelPreference`.
enum AIBackendPreference {
    static let defaultBackend: AIBackend = .claude
    private static let key = "ai-backend"
    private static var storage: UserDefaults = .standard

    /// Swap in an isolated UserDefaults for testing.
    static func _setTestingStorage(_ defaults: UserDefaults) {
        storage = defaults
    }

    static var selected: AIBackend {
        get { storage.string(forKey: key).flatMap(AIBackend.init(rawValue:)) ?? defaultBackend }
        set { storage.set(newValue.rawValue, forKey: key) }
    }

    /// The backend that should actually run, given whether the on-device model is
    /// usable on this device. On-device transparently falls back to Claude when the
    /// device can't run the foundation model (older hardware, Apple Intelligence off).
    static func resolved(isOnDeviceAvailable: Bool) -> AIBackend {
        switch selected {
        case .claude: return .claude
        case .onDevice: return isOnDeviceAvailable ? .onDevice : .claude
        }
    }
}
