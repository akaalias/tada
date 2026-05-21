import Foundation
import Testing

@testable import Tada

// MARK: - ModelCatalog Parsing

@Test func modelCatalog_parses_models_from_api_response() {
    let json = """
    {"data":[
      {"type":"model","id":"claude-sonnet-4-6","display_name":"Claude Sonnet 4.6","created_at":"2026-01-01T00:00:00Z"},
      {"type":"model","id":"claude-opus-4-7","display_name":"Claude Opus 4.7","created_at":"2026-02-01T00:00:00Z"}
    ],"has_more":false}
    """.data(using: .utf8)!

    let models = ModelCatalog.parseModels(from: json)

    #expect(models.count == 2)
    // Newest first.
    #expect(models.first?.id == "claude-opus-4-7")
    #expect(models.first?.displayName == "Claude Opus 4.7")
    #expect(models.last?.id == "claude-sonnet-4-6")
}

@Test func modelCatalog_returns_empty_for_invalid_json() {
    #expect(ModelCatalog.parseModels(from: Data("not json".utf8)).isEmpty)
}

@Test func modelCatalog_returns_empty_for_missing_data_key() {
    #expect(ModelCatalog.parseModels(from: Data(#"{"has_more":false}"#.utf8)).isEmpty)
}

@Test func modelCatalog_sorts_missing_created_at_last() {
    let json = """
    {"data":[
      {"id":"no-date","display_name":"No Date"},
      {"id":"dated","display_name":"Dated","created_at":"2026-02-01T00:00:00Z"}
    ]}
    """.data(using: .utf8)!
    let models = ModelCatalog.parseModels(from: json)
    #expect(models.first?.id == "dated")
    #expect(models.last?.id == "no-date")
}

@Test func claudeModel_codable_roundtrip() throws {
    let model = ClaudeModel(id: "claude-x", displayName: "Claude X", createdAt: "2026-01-01T00:00:00Z")
    let data = try JSONEncoder().encode(model)
    let decoded = try JSONDecoder().decode(ClaudeModel.self, from: data)
    #expect(decoded == model)
}

// MARK: - ModelPreference

@Suite(.serialized)
struct ModelPreferenceTests {
    @Test func defaults_to_sonnet() {
        let defaults = UserDefaults(suiteName: "model-pref-\(UUID())")!
        ModelPreference._setTestingStorage(defaults)
        #expect(ModelPreference.selectedModel == ModelPreference.defaultModel)
    }

    @Test func persists_selection() {
        let defaults = UserDefaults(suiteName: "model-pref-\(UUID())")!
        ModelPreference._setTestingStorage(defaults)
        ModelPreference.selectedModel = "claude-opus-4-7"
        #expect(ModelPreference.selectedModel == "claude-opus-4-7")
    }
}
