import Foundation

/// Dummy API key injected into the launched app via the `-claude-api-key`
/// launch argument (UserDefaults argument domain). Under `-UITestMode 1` all
/// AI calls are mocked, so this value is never sent anywhere — it exists only
/// to satisfy the app's `APIKeyManager.hasAPIKey`/`hasValidAPIKey` gates so the
/// task-planning and action-UI flows run. Chosen to look valid (starts with
/// `sk-ant-`, ≥50 chars, not the `sk-ant-test` form) so the API-key banner
/// stays hidden during the journey.
let uiTestAPIKey = "sk-ant-api03-uitestuitestuitestuitestuitestuitest12345678"
