import Foundation
import FoundationModels

/// Thin wrapper over `SystemLanguageModel` availability so the rest of the app can
/// gate on a simple Bool without importing FoundationModels everywhere.
enum FoundationModelsAvailability {
    /// True when the on-device foundation model can actually run on this device
    /// (Apple Silicon + Apple Intelligence enabled + model assets downloaded).
    static var isAvailable: Bool {
        switch SystemLanguageModel.default.availability {
        case .available:
            return true
        case .unavailable:
            return false
        @unknown default:
            return false
        }
    }

    /// A short human-readable reason when unavailable, for surfacing in Settings.
    static var unavailableReason: String? {
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This Mac isn't eligible for Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is turned off in System Settings."
            case .modelNotReady:
                return "The on-device model is still downloading. Try again shortly."
            @unknown default:
                return "The on-device model is unavailable."
            }
        @unknown default:
            return "The on-device model is unavailable."
        }
    }
}
