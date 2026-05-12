import Foundation
import SwiftData
import Testing
@testable import Tada

// MARK: - Full Task Flow Tests (End-to-End User Journey)

@MainActor
@Test func full_journey_create_task_through_completion() async throws {
    APIKeyManager._setTestingStorage(testUserDefaults())
    let container = IntegrationTestContainer()

    // ── Step 1: Fresh install — no API key ──
    APIKeyManager.deleteAPIKey()
    #expect(APIKeyManager.hasAPIKey == false)

    // ── Step 2: User sets API key in Settings ──
    try! APIKeyManager.setAPIKey(testAPIKey)
    #expect(APIKeyManager.hasAPIKey == true)

    // ── Step 3: User creates a task ──
    container.mockPlanner.discoveryQuestionsProvider = { _ in
        TaskPlan(
            title: "Organize Home Office",
            description: "Setting up a productive home workspace",
            subTasks: [
                SubTaskPlan(title: "What room is the office in?", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "What is your budget?", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "Do you need standing desk capability?", description: "", requiresExternalAction: false)
            ]
        )
    }

    let task = TodoTask(title: "Organize Home Office", originalInput: "Organize home office")
    container.modelContext.insert(task)

    // Simulate planning phase (what NewTaskSheet does after creating the task)
    do {
        let plan = try await container.appServices.plannerAI.generateDiscoveryQuestions(for: "Organize home office")
        await MainActor.run {
            task.title = plan.title
            task.taskDescription = plan.description

            for (index, subPlan) in plan.subTasks.enumerated() {
                let subTask = SubTask(title: subPlan.title, description: subPlan.description, order: index)
                if index == 0 { subTask.markCurrent() }
                task.addSubTask(subTask)
                        subTask.task = task
                container.modelContext.insert(subTask)
            }

            task.planningStatus = .idle
            try? container.modelContext.save()
        }
    } catch {
        throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Discovery planning failed: \(error)"])
    }

    // Verify task is in discovery phase with 3 questions
    let fetchDescriptor = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Organize Home Office" })
    let tasks = try! container.modelContext.fetch(fetchDescriptor)
    let currentTask = try #require(tasks.first)

    #expect(currentTask.isDiscoveryPhase)
    #expect(currentTask.discoverySubTasks.count == 3)
    #expect(currentTask.currentSubTask?.title == "What room is the office in?")

    // ── Step 4: User answers all discovery questions ──
    container.mockExecutive.schemaProvider = { subTask, _, _, _, _ in
        ActionSchema(
            type: .form, title: subTask, description: "", fields: [
                ActionField(id: "text", type: .text, label: subTask, placeholder: nil, options: nil, defaultValue: nil, prefillRows: nil)
            ], submitLabel: "Continue", requiresExternalAction: false
        )
    }

    let answers = ["Home office": "Living room", "Budget?": "$1000", "Standing desk?": "Yes"]
    var previousResponses: [[String: String]] = []

    for subTask in currentTask.discoverySubTasks {
        let schema = try await container.appServices.executiveAI.generateActionUI(
            subTask: subTask.title, subTaskDescription: "", taskContext: currentTask.title,
            previousResponses: previousResponses, taskMemory: "")

        var response = ActionResponse()
        if let field = schema.fields.first {
            response.values[field.id] = .string(answers[subTask.title] ?? "Answer")
        }

        if let data = try? JSONEncoder().encode(response) { subTask.actionResponseData = data }
        subTask.markCompleted()
        container.appServices.knowledgeBase.handleSubtaskCompleted(subTask)

        // Build previous responses for next question
        var dict: [String: String] = ["subTask": subTask.title]
        if let field = schema.fields.first { dict[field.id] = answers[subTask.title] ?? "" }
        previousResponses.append(dict)

        try! container.modelContext.save()
    }

    // Verify all discovery subtasks are completed
    #expect(currentTask.discoverySubTasks.allSatisfy { $0.isCompleted })

    // Verify knowledge base notes were created for each completed subtask
    #expect(container.mockKnowledgeBase.handledSubtaskCompleted.count == 3)

    // ── Step 5: Transition to execution phase ──
    container.mockPlanner.executionPlanProvider = { _, _ in
        TaskPlan(
            title: "Home Office Setup Plan",
            description: "Action plan for organizing the office",
            subTasks: [
                SubTaskPlan(title: "Measure room dimensions", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "Purchase desk and chair", description: "", requiresExternalAction: true),
                SubTaskPlan(title: "Set up lighting", description: "", requiresExternalAction: false),
                SubTaskPlan(title: "Arrange cables and accessories", description: "", requiresExternalAction: false)
            ]
        )
    }

    let discoveryAnswers: [CompletedSubTaskInfo] = currentTask.discoverySubTasks.map { sub in
        var responseStr = ""
        if let data = sub.actionResponseData,
           let resp = try? JSONDecoder().decode(ActionResponse.self, from: data) {
            responseStr = resp.values.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        }
        return CompletedSubTaskInfo(title: sub.title, response: responseStr)
    }

    do {
        let execPlan = try await container.appServices.plannerAI.createExecutionPlan(
            originalTask: "Organize home office", discoveryAnswers: discoveryAnswers)

        await MainActor.run {
            task.transitionToExecution()
            task.title = execPlan.title
            task.taskDescription = execPlan.description

            for (index, subPlan) in execPlan.subTasks.enumerated() {
                let subTask = SubTask(
                    title: subPlan.title, description: subPlan.description, order: index,
                    phase: .execution, requiresExternalAction: subPlan.requiresExternalAction ?? false)
                if index == 0 { subTask.markCurrent() }
                task.addSubTask(subTask)
                        subTask.task = task
                container.modelContext.insert(subTask)
            }

            task.planningStatus = .idle
            try? container.modelContext.save()
        }
    } catch {
        throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Execution planning failed: \(error)"])
    }

    // Verify execution phase
    let fetchExec = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Home Office Setup Plan" })
    let execTasks = try! container.modelContext.fetch(fetchExec)
    let execTask = try #require(execTasks.first)

    #expect(execTask.isExecutionPhase)
    #expect(execTask.executionSubTasks.count == 4)

    // ── Step 6: Complete all execution steps ──
    for subTask in execTask.executionSubTasks {
        let schema = try await container.appServices.executiveAI.generateActionUI(
            subTask: subTask.title, subTaskDescription: "", taskContext: execTask.title,
            previousResponses: [], taskMemory: "")

        var response = ActionResponse()
        if let field = schema.fields.first { response.values[field.id] = .string("Done") }
        if let data = try? JSONEncoder().encode(response) { subTask.actionResponseData = data }
        subTask.markCompleted()
        container.appServices.knowledgeBase.handleSubtaskCompleted(subTask)

        try! container.modelContext.save()
    }

    // Manually mark task completed (in real app this happens after last step)
    execTask.markCompleted()
    container.appServices.knowledgeBase.handleTaskCompleted(execTask)
    try! container.modelContext.save()

    // ── Step 7: Verify final state ──
    let fetchFinal = FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Home Office Setup Plan" })
    let finalTasks = try! container.modelContext.fetch(fetchFinal)
    let finalTask = try #require(finalTasks.first)

    #expect(finalTask.status == .completed)
    #expect(finalTask.completedAt != nil)

    // ── Step 8: Verify knowledge base ──
    #expect(container.mockKnowledgeBase.handledTaskCompleted.count == 1)

    // Discovery notes
    #expect(container.kbFileURL(relativePath: "tasks/organize-home-office/what-room-is-the-office-in.md") != nil)
    #expect(container.kbFileURL(relativePath: "tasks/organize-home-office/what-is-your-budget.md") != nil)
    #expect(container.kbFileURL(relativePath: "tasks/organize-home-office/do-you-need-standing-desk-capability.md") != nil)

    // Execution notes
    #expect(container.kbFileURL(relativePath: "tasks/home-office-setup-plan/measure-room-dimensions.md") != nil)
    #expect(container.kbFileURL(relativePath: "tasks/home-office-setup-plan/purchase-desk-and-chair.md") != nil)
    #expect(container.kbFileURL(relativePath: "tasks/home-office-setup-plan/set-up-lighting.md") != nil)
    #expect(container.kbFileURL(relativePath: "tasks/home-office-setup-plan/arrange-cables-and-accessories.md") != nil)

    // Task summary
    #expect(container.kbFileURL(relativePath: "tasks/home-office-setup-plan/summary.md") != nil)

    // Total KB events
    #expect(container.mockKnowledgeBase.handledSubtaskCompleted.count == 7) // 3 discovery + 4 execution
}

@MainActor
@Test func full_journey_with_external_action_step() async throws {
    APIKeyManager._setTestingStorage(testUserDefaults())
    let container = IntegrationTestContainer()

    try! APIKeyManager.setAPIKey(testAPIKey)
    container.mockPlanner.discoveryQuestionsProvider = { _ in
        TaskPlan(title: "Send Client Report", description: "", subTasks: [
            SubTaskPlan(title: "What report format?", description: "", requiresExternalAction: false)
        ])
    }

    container.mockExecutive.schemaProvider = { subTask, _, _, _, _ in
        ActionSchema(
            type: .form, title: subTask, description: "", fields: [
                ActionField(id: "text", type: .text, label: subTask, placeholder: nil, options: nil, defaultValue: nil, prefillRows: nil)
            ], submitLabel: "Continue", requiresExternalAction: false
        )
    }

    container.mockPlanner.executionPlanProvider = { _, _ in
        TaskPlan(title: "Send Client Report", description: "", subTasks: [
            SubTaskPlan(title: "Compile data", description: "", requiresExternalAction: false),
            SubTaskPlan(title: "Email report to client", description: "", requiresExternalAction: true),
            SubTaskPlan(title: "Confirm receipt", description: "", requiresExternalAction: true)
        ])
    }

    // Create task and run discovery
    let task = TodoTask(title: "Send Client Report", originalInput: "Send client report")
    container.modelContext.insert(task)

    do {
        let plan = try await container.appServices.plannerAI.generateDiscoveryQuestions(for: "Send client report")
        await MainActor.run {
            task.title = plan.title
            for (index, subPlan) in plan.subTasks.enumerated() {
                let subTask = SubTask(title: subPlan.title, description: subPlan.description, order: index)
                if index == 0 { subTask.markCurrent() }
                task.addSubTask(subTask)
                        subTask.task = task
                container.modelContext.insert(subTask)
            }
            task.planningStatus = .idle
            try? container.modelContext.save()
        }
    } catch { throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Discovery failed: \(error)"]) }

    // Complete discovery
    let currentTask = try! container.modelContext.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Send Client Report" })).first!
    for subTask in currentTask.discoverySubTasks {
        let schema = try await container.appServices.executiveAI.generateActionUI(
            subTask: subTask.title, subTaskDescription: "", taskContext: currentTask.title,
            previousResponses: [], taskMemory: "")
        var response = ActionResponse()
        if let field = schema.fields.first { response.values[field.id] = .string("PDF") }
        if let data = try? JSONEncoder().encode(response) { subTask.actionResponseData = data }
        subTask.markCompleted()
        container.appServices.knowledgeBase.handleSubtaskCompleted(subTask)
    }
    try! container.modelContext.save()

    // Transition to execution
    let discoveryAnswers: [CompletedSubTaskInfo] = currentTask.discoverySubTasks.map { sub in
        var respStr = ""
        if let data = sub.actionResponseData, let r = try? JSONDecoder().decode(ActionResponse.self, from: data) {
            respStr = r.values.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        }
        return CompletedSubTaskInfo(title: sub.title, response: respStr)
    }

    do {
        let execPlan = try await container.appServices.plannerAI.createExecutionPlan(
            originalTask: "Send client report", discoveryAnswers: discoveryAnswers)
        await MainActor.run {
            task.transitionToExecution()
            task.title = execPlan.title
            for (index, subPlan) in execPlan.subTasks.enumerated() {
                let st = SubTask(title: subPlan.title, description: subPlan.description, order: index,
                    phase: .execution, requiresExternalAction: subPlan.requiresExternalAction ?? false)
                if index == 0 { st.markCurrent() }
                task.addSubTask(st)
                st.task = task
                container.modelContext.insert(st)
            }
            task.planningStatus = .idle
            try? container.modelContext.save()
        }
    } catch { throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Execution planning failed: \(error)"]) }

    // Complete all execution steps
    let execTask = try! container.modelContext.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.title == "Send Client Report" })).first!
    for subTask in execTask.executionSubTasks {
        let schema = try await container.appServices.executiveAI.generateActionUI(
            subTask: subTask.title, subTaskDescription: "", taskContext: execTask.title,
            previousResponses: [], taskMemory: "")
        var response = ActionResponse()
        if let field = schema.fields.first { response.values[field.id] = .string("Done") }
        if let data = try? JSONEncoder().encode(response) { subTask.actionResponseData = data }
        subTask.markCompleted()
        container.appServices.knowledgeBase.handleSubtaskCompleted(subTask)
    }

    // Verify external action flags were preserved
    let emailStep = try #require(execTask.executionSubTasks.first { $0.title == "Email report to client" })
    #expect(emailStep.effectiveRequiresExternalAction == true)

    let confirmStep = try #require(execTask.executionSubTasks.first { $0.title == "Confirm receipt" })
    #expect(confirmStep.effectiveRequiresExternalAction == true)

    let compileStep = try #require(execTask.executionSubTasks.first { $0.title == "Compile data" })
    #expect(compileStep.effectiveRequiresExternalAction == false)

    // Complete task and verify
    execTask.markCompleted()
    try! container.modelContext.save()

    #expect(execTask.status == .completed)
    #expect(container.mockKnowledgeBase.handledSubtaskCompleted.count == 4) // 1 discovery + 3 execution
}
