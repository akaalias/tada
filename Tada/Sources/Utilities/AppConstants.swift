import Foundation

/// App-wide constants extracted from scattered magic numbers.
enum AppConstants {
    /// Delay before auto-advancing to the next action step (seconds).
    static let autoAdvanceDelay: TimeInterval = 0.8

    /// Maximum number of discovery questions to show at once.
    static let maxDiscoveryQuestions = 5

    /// Default max tokens for Claude API structured messages.
    static let defaultMaxTokens = 2048

    /// Timeout for a single Claude API request (seconds). Large structured
    /// requests can take minutes, so this is generous.
    static let requestTimeout: TimeInterval = 300

    /// Max tokens for short-form AI responses (lessons, summaries).
    static let shortMaxTokens = 100

    /// Max tokens for knowledge base note generation.
    static let kbNoteMaxTokens = 1024

    /// Max tokens for knowledge base cross-link discovery.
    static let kbLinkDiscoveryMaxTokens = 8192

    /// Minimum canvas size for drawing renderer.
    static let minCanvasSize: CGFloat = 100

    /// Slider decimal precision threshold.
    static let sliderDecimalThreshold: Double = 100

    /// Slider decimal precision when range is small.
    static let sliderSmallRangeDecimals = 5

    /// Slider decimal precision when range is large.
    static let sliderLargeRangeDecimals = 0
}
