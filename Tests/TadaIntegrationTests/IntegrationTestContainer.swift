import Foundation
import SwiftData
@testable import Tada

/// Test API key used across all integration tests.
let testAPIKey = "sk-ant-test-integration-key"

/// Container that sets up the full app service layer with mock implementations
/// and an in-memory SwiftData container for testing.
@MainActor
final class IntegrationTestContainer {

    let mockPlanner = MockPlannerAIService()
    let mockExecutive = MockExecutiveAIService()
    let mockKnowledgeBase = MockKnowledgeBaseService()

    let appServices: AppServices
    let modelContainer: ModelContainer
    let modelContext: ModelContext

    /// The temp directory used for knowledge base file writes.
    let kbTempDir: URL

    init() {
        // Set up a temp directory for knowledge base writes
        kbTempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("TadaIntegrationTests")
            .appendingPathComponent(UUID().uuidString)

        do {
            try FileManager.default.createDirectory(at: kbTempDir, withIntermediateDirectories: true)
        } catch {
            fatalError("Failed to create temp directory: \(error)")
        }

        // Override mock knowledge base root URL
        mockKnowledgeBase.rootURL = kbTempDir.appendingPathComponent("knowledge")

        // Create AppServices with all mocks
        appServices = AppServices(
            knowledgeBase: mockKnowledgeBase,
            executiveAI: mockExecutive,
            plannerAI: mockPlanner
        )

        // Create in-memory SwiftData container
        let schema = Schema([TodoTask.self, SubTask.self])
        modelContainer = try! ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
        modelContext = ModelContext(modelContainer)
    }

    deinit {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: kbTempDir)
    }

    /// Resets all mock state for a fresh test.
    func resetMocks() {
        mockKnowledgeBase.writtenFiles.removeAll()
        mockKnowledgeBase.handledTaskCreatedOrUpdated.removeAll()
        mockKnowledgeBase.handledSubtaskCompleted.removeAll()
        mockKnowledgeBase.handledTaskCompleted.removeAll()
        mockKnowledgeBase.reconciledTasks.removeAll()

        // Reset planner providers to defaults
        mockPlanner.discoveryQuestionsProvider = nil
        mockPlanner.executionPlanProvider = nil
        mockPlanner.revisionProvider = nil
        mockPlanner.breakdownProvider = nil
        mockPlanner.learningProvider = nil

        // Reset executive provider to default
        mockExecutive.schemaProvider = nil
    }

    /// Saves the model context and returns.
    func save() {
        try? modelContext.save()
    }

    /// Returns the URL of a knowledge base file if it was written.
    nonisolated func kbFileURL(relativePath: String) -> URL? {
        let path = kbTempDir.appendingPathComponent("knowledge").appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: path.path) ? path : nil
    }

    /// Returns the content of a knowledge base file if it was written.
    nonisolated func kbFileContent(relativePath: String) -> String? {
        guard let url = kbFileURL(relativePath: relativePath) else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Returns all knowledge base file paths that were written.
    func kbWrittenPaths() -> [String] {
        let kbRoot = kbTempDir.appendingPathComponent("knowledge")
        guard FileManager.default.fileExists(atPath: kbRoot.path) else { return [] }

        var paths: [String] = []
        if let enumerator = FileManager.default.enumerator(at: kbRoot, includingPropertiesForKeys: []) as? FileManager.DirectoryEnumerator {
            for case let url as URL in enumerator {
                if url.hasDirectoryPath == false, url.pathExtension == "md" {
                    let relative = url.path.replacingOccurrences(of: kbRoot.path, with: "")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    paths.append(relative)
                }
            }
        }
        return paths.sorted()
    }
}
