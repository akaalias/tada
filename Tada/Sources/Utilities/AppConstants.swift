import Foundation

/// App-wide constants extracted from scattered magic numbers.
enum AppConstants {
    /// Delay before auto-advancing to the next action step (seconds).
    static let autoAdvanceDelay: TimeInterval = 0.8

    /// Maximum number of discovery questions to show at once.
    static let maxDiscoveryQuestions = 10

    /// Timeout for a single Claude API request (seconds). Large structured
    /// requests can take minutes, so this is generous.
    static let requestTimeout: TimeInterval = 300

    /// Max tokens for knowledge base cross-link discovery.
    static let kbLinkDiscoveryMaxTokens = 8192
}
