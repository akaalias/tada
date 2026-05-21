import Foundation
import Testing
@testable import Tada

// All network-stub tests run serially so the global URLProtocol handler is never shared
// across concurrently-executing tests.
@Suite(.serialized)
struct ClaudeNetworkTests {

    // MARK: - ClaudeAPIError

    @Test func apiError_descriptions() {
        #expect(ClaudeAPIError.invalidResponse.errorDescription == "Invalid response from AI service")
        #expect(ClaudeAPIError.httpError(503).errorDescription == "Connection error (HTTP 503)")
        #expect(ClaudeAPIError.apiError("rate limited").errorDescription == "rate limited")
        #expect(ClaudeAPIError.jsonParsingError(URLError(.badURL)).errorDescription == "Failed to understand AI response. Please try again.")
    }

    // MARK: - ClaudeAPIClient.sendMessage

    @Test func sendMessage_returns_text() async throws {
        let client = ClaudeAPIClient(apiKey: "k", role: .planner, phase: .execution)
        try await withStub({ _ in (200, textBody("hello world")) }) {
            let result = try await client.sendMessage(systemPrompt: "s", userMessage: "u")
            #expect(result == "hello world")
        }
    }

    @Test func sendMessage_httpError_on_non200_plain_body() async throws {
        let client = ClaudeAPIClient(apiKey: "k", role: .planner, phase: .execution)
        try await withStub({ _ in (500, jsonData([:])) }) {
            await #expect(throws: ClaudeAPIError.self) {
                _ = try await client.sendMessage(systemPrompt: "s", userMessage: "u")
            }
        }
    }

    @Test func sendMessage_apiError_on_error_body() async throws {
        let client = ClaudeAPIClient(apiKey: "k", role: .planner, phase: .execution)
        try await withStub({ _ in (400, apiErrorBody("invalid key")) }) {
            await #expect(throws: ClaudeAPIError.self) {
                _ = try await client.sendMessage(systemPrompt: "s", userMessage: "u")
            }
        }
    }

    @Test func sendMessage_invalidResponse_when_no_text() async throws {
        let client = ClaudeAPIClient(apiKey: "k", role: .planner, phase: .execution)
        try await withStub({ _ in (200, jsonData(["content": []])) }) {
            await #expect(throws: ClaudeAPIError.self) {
                _ = try await client.sendMessage(systemPrompt: "s", userMessage: "u")
            }
        }
    }

    // MARK: - ClaudeAPIClient.sendStructuredMessage

    @Test func sendStructured_decodes_taskplan() async throws {
        let client = ClaudeAPIClient(apiKey: "k", role: .planner, phase: .execution)
        let input: [String: Any] = [
            "title": "Trip", "description": "A trip",
            "subTasks": [["title": "Pack", "description": "", "requiresExternalAction": false]]
        ]
        try await withStub({ _ in (200, toolUseBody(input)) }) {
            let plan = try await client.sendStructuredMessage(systemPrompt: "s", userMessage: "u", responseType: TaskPlan.self)
            #expect(plan.title == "Trip")
            #expect(plan.subTasks.first?.title == "Pack")
        }
    }

    @Test func sendStructured_apiError_in_body() async throws {
        let client = ClaudeAPIClient(apiKey: "k", role: .planner, phase: .execution)
        try await withStub({ _ in (200, apiErrorBody("overloaded")) }) {
            await #expect(throws: ClaudeAPIError.self) {
                _ = try await client.sendStructuredMessage(systemPrompt: "s", userMessage: "u", responseType: TaskPlan.self)
            }
        }
    }

    @Test func sendStructured_invalidResponse_when_no_content() async throws {
        let client = ClaudeAPIClient(apiKey: "k", role: .planner, phase: .execution)
        try await withStub({ _ in (200, jsonData(["unexpected": true])) }) {
            await #expect(throws: ClaudeAPIError.self) {
                _ = try await client.sendStructuredMessage(systemPrompt: "s", userMessage: "u", responseType: TaskPlan.self)
            }
        }
    }

    @Test func sendStructured_invalidResponse_when_text_instead_of_tool_use() async throws {
        let client = ClaudeAPIClient(apiKey: "k", role: .planner, phase: .execution)
        try await withStub({ _ in (200, textBody("I cannot do that")) }) {
            await #expect(throws: ClaudeAPIError.self) {
                _ = try await client.sendStructuredMessage(systemPrompt: "s", userMessage: "u", responseType: TaskPlan.self)
            }
        }
    }

    @Test func sendStructured_jsonParsingError_on_bad_input_shape() async throws {
        let client = ClaudeAPIClient(apiKey: "k", role: .planner, phase: .execution)
        try await withStub({ _ in (200, toolUseBody(["totally": "wrong"])) }) {
            await #expect(throws: ClaudeAPIError.self) {
                _ = try await client.sendStructuredMessage(systemPrompt: "s", userMessage: "u", responseType: TaskPlan.self)
            }
        }
    }

    @Test func sendStructured_with_attached_image() async throws {
        let client = ClaudeAPIClient(apiKey: "k", role: .knowledge, phase: .knowledge)
        let input: [String: Any] = ["title": "Note", "body": "body"]
        try await withStub({ _ in (200, toolUseBody(input)) }) {
            let note = try await client.sendStructuredMessage(
                systemPrompt: "s", userMessage: "u", responseType: GeneratedKnowledgeNote.self,
                attachedImages: [Data([0x89, 0x50])]
            )
            #expect(note.title == "Note")
        }
    }

    /// Exercises every branch of getToolSchema by decoding each known response type plus a default.
    struct Misc: Decodable, Equatable { let x: Int }

    @Test func sendStructured_covers_all_tool_schemas() async throws {
        let client = ClaudeAPIClient(apiKey: "k", role: .executive, phase: .execution)

        // ActionSchema
        try await withStub({ _ in (200, toolUseBody([
            "type": "form", "title": "T", "submitLabel": "Go", "requiresExternalAction": false,
            "fields": [["id": "f", "type": "text", "label": "L"]]
        ])) }) {
            let schema = try await client.sendStructuredMessage(systemPrompt: "s", userMessage: "u", responseType: ActionSchema.self)
            #expect(schema.title == "T")
        }

        // PlanRevision
        try await withStub({ _ in (200, toolUseBody(["revised": false])) }) {
            let rev = try await client.sendStructuredMessage(systemPrompt: "s", userMessage: "u", responseType: PlanRevision.self)
            #expect(rev.revised == false)
        }

        // NoteLinkSuggestions
        try await withStub({ _ in (200, toolUseBody(["links": [["targetPath": "p", "targetTitle": "t", "reason": "r"]]])) }) {
            let links = try await client.sendStructuredMessage(systemPrompt: "s", userMessage: "u", responseType: NoteLinkSuggestions.self)
            #expect(links.links.count == 1)
        }

        // EntityExtractionResult
        try await withStub({ _ in (200, toolUseBody(["linkedBody": "b", "newEntities": []])) }) {
            let result = try await client.sendStructuredMessage(systemPrompt: "s", userMessage: "u", responseType: EntityExtractionResult.self)
            #expect(result.newEntities.isEmpty)
        }

        // MicroStepsResponse
        try await withStub({ _ in (200, toolUseBody(["microSteps": [["title": "m", "description": "", "requiresExternalAction": false]]])) }) {
            let micro = try await client.sendStructuredMessage(systemPrompt: "s", userMessage: "u", responseType: MicroStepsResponse.self)
            #expect(micro.microSteps.count == 1)
        }

        // Default branch (unknown type)
        try await withStub({ _ in (200, toolUseBody(["x": 7])) }) {
            let misc = try await client.sendStructuredMessage(systemPrompt: "s", userMessage: "u", responseType: Misc.self)
            #expect(misc.x == 7)
        }
    }

    // MARK: - ClaudeAPIClient.sendRequest

    @Test func sendRequest_returns_json() async throws {
        let client = ClaudeAPIClient(apiKey: "k", role: .coach, phase: .execution)
        try await withStub({ _ in (200, textBody("hi")) }) {
            let json = try await client.sendRequest(body: ["model": "m"], phase: .execution, taskTitle: nil)
            #expect(json["content"] != nil)
        }
    }

    // MARK: - ExecutiveAIService

    @Test func executive_generateActionUI_decodes_schema() async throws {
        let executive = ExecutiveAIService(apiKey: "k")
        let input: [String: Any] = [
            "type": "form", "title": "Pick a date", "submitLabel": "Continue", "requiresExternalAction": false,
            "fields": [["id": "f", "type": "date", "label": "When"]]
        ]
        try await withStub({ _ in (200, toolUseBody(input)) }) {
            let schema = try await executive.generateActionUI(
                subTask: "Pick a date", subTaskDescription: "desc", taskContext: "Trip",
                previousResponses: [["subTask": "earlier", "field": "answer"]],
                taskMemory: "Always mornings", phase: .discovery
            )
            #expect(schema.title == "Pick a date")
            #expect(schema.fields.first?.type == .date)
        }
    }

    // MARK: - PlannerAIService

    @Test func planner_generateDiscoveryQuestions() async throws {
        let planner = PlannerAIService(apiKey: "k")
        let input: [String: Any] = ["title": "Plan", "description": "d",
                                    "subTasks": [["title": "Q1", "description": "", "requiresExternalAction": false]]]
        try await withStub({ _ in (200, toolUseBody(input)) }) {
            let plan = try await planner.generateDiscoveryQuestions(for: "do a thing")
            #expect(plan.subTasks.first?.title == "Q1")
        }
    }

    @Test func planner_createExecutionPlan() async throws {
        let planner = PlannerAIService(apiKey: "k")
        let input: [String: Any] = ["title": "Exec", "description": "d",
                                    "subTasks": [["title": "S1", "description": "", "requiresExternalAction": true]]]
        try await withStub({ _ in (200, toolUseBody(input)) }) {
            let plan = try await planner.createExecutionPlan(
                originalTask: "task", discoveryAnswers: [CompletedSubTaskInfo(title: "Q", response: "A")])
            #expect(plan.subTasks.first?.requiresExternalAction == true)
        }
    }

    @Test func planner_revisePlan() async throws {
        let planner = PlannerAIService(apiKey: "k")
        try await withStub({ _ in (200, toolUseBody(["revised": true, "reason": "split",
            "subTasks": [["title": "A", "description": "", "requiresExternalAction": false]]])) }) {
            let revision = try await planner.revisePlan(
                originalTask: "t", completedSubTasks: [CompletedSubTaskInfo(title: "x", response: "y")],
                remainingSubTasks: ["leftover"])
            #expect(revision.revised == true)
            #expect(revision.subTasks?.count == 1)
        }
    }

    @Test func planner_breakDownStep_returns_microsteps() async throws {
        let planner = PlannerAIService(apiKey: "k")
        try await withStub({ _ in (200, toolUseBody(["microSteps": [
            ["title": "Sub A", "description": "", "requiresExternalAction": false],
            ["title": "Sub B", "description": "", "requiresExternalAction": false]
        ]])) }) {
            let steps = try await planner.breakDownStep(
                stepTitle: "Big", stepDescription: "", taskContext: "T",
                discoveryContext: "", executionProgress: "")
            #expect(steps.map(\.title) == ["Sub A", "Sub B"])
        }
    }

    @Test func planner_generateLearning_trims_text() async throws {
        let planner = PlannerAIService(apiKey: "k")
        try await withStub({ _ in (200, textBody("  Avoid invented items.  ")) }) {
            let lesson = try await planner.generateLearning(
                badStepTitle: "Buy roses", taskContext: "Garden",
                discoveryContext: "", executionProgress: "")
            #expect(lesson == "Avoid invented items.")
        }
    }

    // MARK: - KnowledgeAIService

    @Test func knowledgeAI_generateSubtaskNote() async throws {
        let svc = KnowledgeAIService(apiKey: "k")
        try await withStub({ _ in (200, toolUseBody(["title": "Budget Set", "body": "I set €1000."])) }) {
            let note = try await svc.generateSubtaskNote(
                taskTitle: "Trip", subtaskTitle: "Budget?", subtaskDescription: "",
                response: "1000", attachedImage: Data([0x89]), tableMarkdown: "| a |\n| - |",
                phase: .knowledge)
            #expect(note.title == "Budget Set")
        }
    }

    @Test func knowledgeAI_discoverLinks_entity_and_task() async throws {
        let svc = KnowledgeAIService(apiKey: "k")
        let body = toolUseBody(["links": [["targetPath": "notes/_entities/x.md", "targetTitle": "X", "reason": "same theme"]]])

        try await withStub({ _ in (200, body) }) {
            let entity = try await svc.discoverLinksForNote(
                note: (path: "p", title: "t", body: "b", context: "mentioned in: foo"),
                candidates: [(path: "c", title: "ct", body: "cb", context: "")],
                newNoteIsEntity: true)
            #expect(entity.links.count == 1)
        }
        try await withStub({ _ in (200, body) }) {
            let task = try await svc.discoverLinksForNote(
                note: (path: "p", title: "t", body: "b", context: ""),
                candidates: [(path: "c", title: "ct", body: "cb", context: "mentioned in: bar")],
                newNoteIsEntity: false)
            #expect(task.links.count == 1)
        }
    }

    @Test func knowledgeAI_extractEntities_with_and_without_original_input() async throws {
        let svc = KnowledgeAIService(apiKey: "k")
        let body = toolUseBody(["linkedBody": "linked", "newEntities": [
            ["slug": "openai", "displayName": "OpenAI", "body": "An AI lab."]
        ]])

        try await withStub({ _ in (200, body) }) {
            let r = try await svc.extractEntitiesAndLink(
                noteTitle: "N", noteBody: "OpenAI is a lab",
                existingEntities: [ExistingEntityRef(slug: "anthropic", title: "Anthropic")])
            #expect(r.newEntities.first?.slug == "openai")
        }
        try await withStub({ _ in (200, body) }) {
            let r = try await svc.extractEntitiesAndLink(
                noteTitle: "N", noteBody: "body", originalInput: "I like OpenAI",
                existingEntities: [])
            #expect(r.linkedBody == "linked")
        }
    }

    @Test func knowledgeAI_generateTaskOverviewNote() async throws {
        let svc = KnowledgeAIService(apiKey: "k")
        try await withStub({ _ in (200, toolUseBody(["title": "Overview", "body": "summary"])) }) {
            let note = try await svc.generateTaskOverviewNote(
                taskTitle: "T", originalInput: "orig", taskDescription: "desc",
                subtaskSummaries: [(title: "S", response: "R", filename: "01-s.md")])
            #expect(note.title == "Overview")
        }
    }

    // MARK: - CoachService

    @Test func coachService_chat_returns_text() async throws {
        let svc = CoachService(apiKey: "k")
        try await withStub({ _ in (200, textBody("How can I help?")) }) {
            let response = try await svc.chat(
                userMessage: "hi", context: "All Tasks", conversationHistory: [],
                taskSummary: "- A task [discovery, 0% done]")
            #expect(response.message == "How can I help?")
            #expect(response.toolCalls == nil)
        }
    }

    @Test func coachService_chat_parses_tool_use() async throws {
        let svc = CoachService(apiKey: "k")
        let body = jsonData(["content": [
            ["type": "text", "text": "Creating that task"],
            ["type": "tool_use", "id": "tu_1", "name": "create_task", "input": ["description": "Buy milk"]]
        ]])
        // Conversation history with a prior tool call+result to exercise history serialization.
        let prior = CoachMessage(
            role: .coach, content: "earlier",
            toolCalls: [ToolCall(id: "old", name: "search_tasks", arguments: ["query": "x"])],
            toolResults: [CoachMessage.ToolResult(toolUseId: "old", toolName: "search_tasks", success: true, message: "found")]
        )
        try await withStub({ _ in (200, body) }) {
            let response = try await svc.chat(
                userMessage: "make a task", context: "ctx", conversationHistory: [prior],
                taskSummary: nil,
                toolResults: [CoachMessage.ToolResult(toolUseId: "old", toolName: "search_tasks", success: true, message: "found")])
            #expect(response.toolCalls?.first?.name == "create_task")
            #expect(response.toolCalls?.first?.arguments["description"] == "Buy milk")
        }
    }

    // MARK: - ModelCatalog.fetchModels

    @Test func modelCatalog_fetchModels_success() async throws {
        let body = jsonData(["data": [
            ["id": "claude-opus-4-7", "display_name": "Opus", "created_at": "2026-02-01T00:00:00Z"]
        ]])
        try await withStub({ _ in (200, body) }) {
            let models = try await ModelCatalog.fetchModels(apiKey: "k")
            #expect(models.first?.id == "claude-opus-4-7")
        }
    }

    @Test func modelCatalog_fetchModels_apiError() async throws {
        try await withStub({ _ in (401, apiErrorBody("invalid api key")) }) {
            await #expect(throws: ClaudeAPIError.self) {
                _ = try await ModelCatalog.fetchModels(apiKey: "bad")
            }
        }
    }

    @Test func modelCatalog_fetchModels_httpError() async throws {
        try await withStub({ _ in (500, jsonData([:])) }) {
            await #expect(throws: ClaudeAPIError.self) {
                _ = try await ModelCatalog.fetchModels(apiKey: "k")
            }
        }
    }
}
