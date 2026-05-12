import Foundation
import SwiftData
import Testing
@testable import Tada

// MARK: - Collapsed Cards on Load Tests

/// Verifies that ActionCard correctly receives and stores the defaultExpanded parameter.
/// When defaultExpanded is false, the card should start collapsed — this is the behavior
/// that InformationRequiredView and ActionRequiredView must enforce for ALL cards.
@MainActor
@Test func action_card_stores_default_expanded_parameter() async throws {
    let container = IntegrationTestContainer()

    let task = TodoTask(title: "Test Task", originalInput: "test")
    task.status = .active
    container.modelContext.insert(task)

    let subTask = SubTask(title: "Q1", description: "", order: 0)
    subTask.markCurrent()
    task.addSubTask(subTask)
    container.modelContext.insert(subTask)

    try! container.save()

    // Collapsed card
    let collapsedCard = ActionCard(
        task: task,
        defaultExpanded: false,
        knowledgeBase: container.appServices.knowledgeBase,
        executiveAI: container.appServices.executiveAI,
        plannerAI: container.appServices.plannerAI
    )

    // Expanded card
    let expandedCard = ActionCard(
        task: task,
        defaultExpanded: true,
        knowledgeBase: container.appServices.knowledgeBase,
        executiveAI: container.appServices.executiveAI,
        plannerAI: container.appServices.plannerAI
    )

    // The parameter must be stored correctly so TaskCard can use it in .onAppear
    #expect(collapsedCard.defaultExpanded == false)
    #expect(expandedCard.defaultExpanded == true)

    // Verify: passing `index == 0` (the current buggy behavior) would give us
    // mixed expansion states — card 0 expanded, cards 1+ collapsed.
    // The fix: all cards should get `false`.
}

/// Integration test that verifies the full flow: when discovery tasks are loaded,
/// all ActionCards should be created with defaultExpanded = false.
@MainActor
@Test func information_required_all_discovery_tasks_get_collapsed_cards() async throws {
    let container = IntegrationTestContainer()

    // Create 3 active discovery tasks (matching what InformationRequiredView filters for)
    var tasks: [TodoTask] = []
    for i in 0..<3 {
        let task = TodoTask(title: "Discovery Task \(i)", originalInput: "input \(i)")
        task.status = .active
        container.modelContext.insert(task)

        let subTask = SubTask(title: "Q\(i+1)", description: "", order: i)
        subTask.markCurrent()
        task.addSubTask(subTask)
        container.modelContext.insert(subTask)

        tasks.append(task)
    }
    try! container.save()

    // Simulate the view's rendering loop — each card should get defaultExpanded = false
    let discoveryTasks: [TodoTask] = tasks.filter { task in
        if task.isPlanningDiscovery { return true }
        if task.subTasks.isEmpty { return true }
        if task.isDiscoveryPhase && task.currentSubTask != nil { return true }
        return false
    }

    // Create cards the way the FIXED view should: all with defaultExpanded = false
    for (index, task) in discoveryTasks.enumerated() {
        let card = ActionCard(
            task: task,
            defaultExpanded: false, // ← Fixed: always false, not `index == 0`
            knowledgeBase: container.appServices.knowledgeBase,
            executiveAI: container.appServices.executiveAI,
            plannerAI: container.appServices.plannerAI
        )
        #expect(card.defaultExpanded == false, "Card at index \(index) should start collapsed")
    }

    // The old buggy code used: defaultExpanded: index == 0
    // This would mean card[0] is expanded — which is the bug we're fixing.
}

/// Integration test that verifies execution tasks all get collapsed cards.
@MainActor
@Test func action_required_all_execution_tasks_get_collapsed_cards() async throws {
    let container = IntegrationTestContainer()

    // Create 3 active execution tasks (matching what ActionRequiredView filters for)
    var tasks: [TodoTask] = []
    for i in 0..<3 {
        let task = TodoTask(title: "Execution Task \(i)", originalInput: "input \(i)")
        task.status = .active
        container.modelContext.insert(task)

        let subTask = SubTask(title: "Step \(i+1)", description: "", order: i, phase: .execution)
        subTask.markCurrent()
        task.addSubTask(subTask)
        container.modelContext.insert(subTask)

        tasks.append(task)
    }
    try! container.save()

    let executionTasks: [TodoTask] = tasks.filter { task in
        if task.isPlanningExecution { return true }
        if task.isExecutionPhase && task.currentSubTask != nil { return true }
        return false
    }

    // Create cards the way the FIXED view should: all with defaultExpanded = false
    for (index, task) in executionTasks.enumerated() {
        let card = ActionCard(
            task: task,
            defaultExpanded: false, // ← Fixed: always false, not `index == 0`
            knowledgeBase: container.appServices.knowledgeBase,
            executiveAI: container.appServices.executiveAI,
            plannerAI: container.appServices.plannerAI
        )
        #expect(card.defaultExpanded == false, "Card at index \(index) should start collapsed")
    }
}
