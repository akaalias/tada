import Foundation

/// Activated only when the UI test runner launches the app with `-UITestMode 1`.
/// Read once at startup so it's stable for the lifetime of the process.
///
/// No side effects: this exists purely as a flag that adapter classes
/// consult to decide whether to route to deterministic mocks.
enum UITestSupport {
    static let isActive: Bool = UserDefaults.standard.bool(forKey: "UITestMode")
}
