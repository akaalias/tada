import Testing

@testable import Tada

// MARK: - TodoTask Tests

@Test func task_initialization_sets_defaults() {
    let task = TodoTask(title: "Test Task", originalInput: "Original input")

    #expect(task.title == "Test Task")
    #expect(task.originalInput == "Original input")
    #expect(task.taskDescription == "")
    #expect(task.status == .active)
    #expect(task.phase == .discovery)
    #expect(task.planningStatus == .idle)
    #expect(task.completedAt == nil)
    #expect(task.id != nil)
}

@Test func task_markCompleted_sets_status_and_date() {
    let task = TodoTask(title: "Test Task")
    task.markCompleted()

    #expect(task.status == .completed)
    #expect(task.completedAt != nil)
}

@Test func task_progress_returns_zero_when_no_subtasks() {
    let task = TodoTask(title: "Test Task")

    #expect(task.progress == 0)
}

@Test func task_progress_calculates_correctly() {
    let task = TodoTask(title: "Test Task")

    // Add 3 subtasks in discovery phase
    let st1 = SubTask(title: "Step 1", description: "", order: 0, phase: .discovery)
    let st2 = SubTask(title: "Step 2", description: "", order: 1, phase: .discovery)
    let st3 = SubTask(title: "Step 3", description: "", order: 2, phase: .discovery)

    task.addSubTask(st1)
    task.addSubTask(st2)
    task.addSubTask(st3)

    // 0/3 completed
    #expect(task.progress == 0.0)

    st1.markCompleted()
    // 1/3 completed
    #expect(task.progress == 1.0 / 3.0)

    st2.markCompleted()
    // 2/3 completed
    #expect(task.progress == 2.0 / 3.0)

    st3.markCompleted()
    // 3/3 completed
    #expect(task.progress == 1.0)
}

@Test func task_progress_ignores_execution_subtasks_when_in_discovery() {
    let task = TodoTask(title: "Test Task")

    let discoverySubtask = SubTask(title: "Discovery", description: "", order: 0, phase: .discovery)
    let executionSubtask = SubTask(title: "Execute", description: "", order: 1, phase: .execution)

    task.addSubTask(discoverySubtask)
    task.addSubTask(executionSubtask)

    // Task is in discovery phase, so only discovery subtasks count
    #expect(task.progress == 0.0)

    discoverySubtask.markCompleted()
    #expect(task.progress == 1.0)

    // Even if execution subtask is completed, it shouldn't affect progress
    executionSubtask.markCompleted()
    #expect(task.progress == 1.0)
}

@Test func task_current_phase_subtasks_filters_by_phase() {
    let task = TodoTask(title: "Test Task")

    let discovery1 = SubTask(title: "D1", description: "", order: 0, phase: .discovery)
    let discovery2 = SubTask(title: "D2", description: "", order: 1, phase: .discovery)
    let execution1 = SubTask(title: "E1", description: "", order: 2, phase: .execution)

    task.addSubTask(discovery1)
    task.addSubTask(discovery2)
    task.addSubTask(execution1)

    #expect(task.discoverySubTasks.count == 2)
    #expect(task.executionSubTasks.count == 1)

    task.transitionToExecution()
    #expect(task.currentPhaseSubTasks.count == 1)
    #expect(task.currentPhaseSubTasks[0] === execution1)
}

@Test func task_current_subtask_returns_first_non_completed() {
    let task = TodoTask(title: "Test Task")

    let st1 = SubTask(title: "Step 1", description: "", order: 0, phase: .discovery)
    let st2 = SubTask(title: "Step 2", description: "", order: 1, phase: .discovery)
    let st3 = SubTask(title: "Step 3", description: "", order: 2, phase: .discovery)

    task.addSubTask(st1)
    task.addSubTask(st2)
    task.addSubTask(st3)

    // st1 is current (pending)
    #expect(task.currentSubTask === st1)

    // Mark st1 as completed, st2 becomes current
    st1.markCompleted()
    #expect(task.currentSubTask === st2)

    // Mark all as completed, no current subtask
    st2.markCompleted()
    st3.markCompleted()
    #expect(task.currentSubTask == nil)
}

@Test func task_current_subtask_skips_completed_and_returns_pending_or_current() {
    let task = TodoTask(title: "Test Task")

    let st1 = SubTask(title: "Step 1", description: "", order: 0, phase: .discovery)
    let st2 = SubTask(title: "Step 2", description: "", order: 1, phase: .discovery)

    task.addSubTask(st1)
    task.addSubTask(st2)

    st1.markCompleted()
    st2.markCurrent()

    #expect(task.currentSubTask === st2)
}

@Test func task_sorted_subtasks_orders_by_order() {
    let task = TodoTask(title: "Test Task")

    // Add in reverse order - addSubTask sets the order automatically
    let st3 = SubTask(title: "Step 3", description: "", order: -1, phase: .discovery)
    let st1 = SubTask(title: "Step 1", description: "", order: -1, phase: .discovery)
    let st2 = SubTask(title: "Step 2", description: "", order: -1, phase: .discovery)

    task.addSubTask(st3) // order = 0
    task.addSubTask(st1) // order = 1
    task.addSubTask(st2) // order = 2

    let sorted = task.sortedSubTasks
    #expect(sorted[0] === st3) // order 0
    #expect(sorted[1] === st1) // order 1
    #expect(sorted[2] === st2) // order 2
}

@Test func task_isPlanning_returns_correctly() {
    let task = TodoTask(title: "Test Task")

    #expect(task.isPlanning == false)
    #expect(task.isPlanningDiscovery == false)
    #expect(task.isPlanningExecution == false)

    task.planningStatus = .planningDiscovery
    #expect(task.isPlanning == true)
    #expect(task.isPlanningDiscovery == true)

    task.planningStatus = .planningExecution
    #expect(task.isPlanning == true)
    #expect(task.isPlanningExecution == true)

    task.planningStatus = .idle
    #expect(task.isPlanning == false)
}

@Test func task_addSubTask_sets_order() {
    let task = TodoTask(title: "Test Task")

    let st1 = SubTask(title: "Step 1", description: "", order: -1, phase: .discovery)
    let st2 = SubTask(title: "Step 2", description: "", order: -1, phase: .discovery)

    task.addSubTask(st1)
    #expect(st1.order == 0)

    task.addSubTask(st2)
    #expect(st2.order == 1)
}

// MARK: - SubTask Tests

@Test func subtask_initialization_sets_defaults() {
    let st = SubTask(title: "Test Step", description: "Description", order: 5, phase: .execution)

    #expect(st.title == "Test Step")
    #expect(st.subTaskDescription == "Description")
    #expect(st.order == 5)
    #expect(st.phase == .execution)
    #expect(st.status == .pending)
    #expect(st.requiresExternalAction == false)
    #expect(st.actionSchemaData == nil)
    #expect(st.actionResponseData == nil)
}

@Test func subtask_markCompleted_sets_status_and_date() {
    let st = SubTask(title: "Test Step")
    st.markCompleted()

    #expect(st.status == .completed)
    #expect(st.completedAt != nil)
}

@Test func subtask_markCurrent_sets_status() {
    let st = SubTask(title: "Test Step")

    #expect(st.status == .pending)
    st.markCurrent()
    #expect(st.status == .current)
}

@Test func subtask_skip_sets_status() {
    let st = SubTask(title: "Test Step")

    #expect(st.status == .pending)
    st.skip()
    #expect(st.status == .skipped)
}

@Test func subtask_status_properties() {
    let st = SubTask(title: "Test Step")

    #expect(st.isPending == true)
    #expect(st.isCurrent == false)
    #expect(st.isCompleted == false)

    st.markCurrent()
    #expect(st.isPending == false)
    #expect(st.isCurrent == true)

    st.markCompleted()
    #expect(st.isPending == false)
    #expect(st.isCurrent == false)
    #expect(st.isCompleted == true)

    st.skip()
    #expect(st.isCompleted == false)
}

@Test func subtask_phase_properties() {
    let discovery = SubTask(title: "D", description: "", order: 0, phase: .discovery)
    let execution = SubTask(title: "E", description: "", order: 0, phase: .execution)

    #expect(discovery.isDiscoveryPhase == true)
    #expect(discovery.isExecutionPhase == false)

    #expect(execution.isDiscoveryPhase == false)
    #expect(execution.isExecutionPhase == true)
}
