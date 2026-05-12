import Foundation
import Testing

@testable import Tada

// MARK: - TaskStatus Tests

@Test func taskStatus_isCompleted_returns_correctly() {
    #expect(TaskStatus.active.isCompleted == false)
    #expect(TaskStatus.completed.isCompleted == true)
    #expect(TaskStatus.archived.isCompleted == false)
}

@Test func taskStatus_allCases_contains_expected_values() {
    #expect(TaskStatus.allCases.count == 3)
    #expect(Set(TaskStatus.allCases) == Set([.active, .completed, .archived]))
}

@Test func taskStatus_codable_roundtrip() async throws {
    let statuses: [TaskStatus] = [.active, .completed, .archived]

    for status in statuses {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(status)
        let decoded = try decoder.decode(TaskStatus.self, from: data)

        #expect(decoded == status)
    }
}

// MARK: - SubTaskStatus Tests

@Test func subtaskStatus_isCompleted_returns_correctly() {
    #expect(SubTaskStatus.pending.isCompleted == false)
    #expect(SubTaskStatus.current.isCompleted == false)
    #expect(SubTaskStatus.completed.isCompleted == true)
    #expect(SubTaskStatus.skipped.isCompleted == false)
}

@Test func subtaskStatus_allCases_contains_expected_values() {
    #expect(SubTaskStatus.allCases.count == 4)
    #expect(Set(SubTaskStatus.allCases) == Set([.pending, .current, .completed, .skipped]))
}

@Test func subtaskStatus_codable_roundtrip() async throws {
    let statuses: [SubTaskStatus] = [.pending, .current, .completed, .skipped]

    for status in statuses {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(status)
        let decoded = try decoder.decode(SubTaskStatus.self, from: data)

        #expect(decoded == status)
    }
}

// MARK: - TaskPhase Tests

@Test func taskPhase_allCases_contains_expected_values() {
    #expect(TaskPhase.allCases.count == 2)
    #expect(Set(TaskPhase.allCases) == Set([.discovery, .execution]))
}

@Test func taskPhase_codable_roundtrip() async throws {
    let phases: [TaskPhase] = [.discovery, .execution]

    for phase in phases {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(phase)
        let decoded = try decoder.decode(TaskPhase.self, from: data)

        #expect(decoded == phase)
    }
}

// MARK: - PlanningStatus Tests

@Test func planningStatus_isPlanning_returns_correctly() {
    #expect(PlanningStatus.idle.isPlanning == false)
    #expect(PlanningStatus.planningDiscovery.isPlanning == true)
    #expect(PlanningStatus.planningExecution.isPlanning == true)
}

@Test func planningStatus_allCases_contains_expected_values() {
    #expect(PlanningStatus.allCases.count == 3)
    #expect(Set(PlanningStatus.allCases) == Set([.idle, .planningDiscovery, .planningExecution]))
}

@Test func planningStatus_codable_roundtrip() async throws {
    let statuses: [PlanningStatus] = [.idle, .planningDiscovery, .planningExecution]

    for status in statuses {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(status)
        let decoded = try decoder.decode(PlanningStatus.self, from: data)

        #expect(decoded == status)
    }
}
