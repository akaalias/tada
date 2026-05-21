import Foundation
import Testing
@testable import Tada

// MARK: - Helpers

private func makeMemoryService() -> (svc: PlanningMemoryService, file: URL) {
    let file = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("PlanningMemoryTests-\(UUID()).json")
    return (PlanningMemoryService(fileURL: file), file)
}

// MARK: - PlanningLearning

@Test func planningLearning_init_sets_fields() {
    let learning = PlanningLearning(taskContext: "Trip", badStepTitle: "Buy roses", lesson: "Avoid invented items")
    #expect(learning.taskContext == "Trip")
    #expect(learning.badStepTitle == "Buy roses")
    #expect(learning.lesson == "Avoid invented items")
    #expect(learning.date <= Date())
}

@Test func planningLearning_codable_roundtrip() throws {
    let learning = PlanningLearning(taskContext: "T", badStepTitle: "B", lesson: "L")
    let data = try JSONEncoder().encode(learning)
    let decoded = try JSONDecoder().decode(PlanningLearning.self, from: data)
    #expect(decoded.id == learning.id)
    #expect(decoded.lesson == "L")
}

// MARK: - PlanningMemoryService

@Test func memoryService_loads_empty_when_no_file() {
    let (svc, file) = makeMemoryService()
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(svc.loadLearnings().isEmpty)
    #expect(svc.getLearningsForPrompt() == "")
}

@Test func memoryService_saves_and_loads() {
    let (svc, file) = makeMemoryService()
    defer { try? FileManager.default.removeItem(at: file) }

    svc.saveLearning(PlanningLearning(taskContext: "T1", badStepTitle: "B1", lesson: "Lesson one"))
    svc.saveLearning(PlanningLearning(taskContext: "T2", badStepTitle: "B2", lesson: "Lesson two"))

    let loaded = svc.loadLearnings()
    #expect(loaded.count == 2)
    #expect(loaded.map(\.lesson) == ["Lesson one", "Lesson two"])
}

@Test func memoryService_getLearningsForPrompt_formats_bullets() {
    let (svc, file) = makeMemoryService()
    defer { try? FileManager.default.removeItem(at: file) }

    svc.saveLearning(PlanningLearning(taskContext: "T", badStepTitle: "B", lesson: "Don't invent items"))
    let prompt = svc.getLearningsForPrompt()
    #expect(prompt.contains("LEARNINGS FROM PAST MISTAKES"))
    #expect(prompt.contains("- Don't invent items"))
}

@Test func memoryService_caps_at_20_learnings() {
    let (svc, file) = makeMemoryService()
    defer { try? FileManager.default.removeItem(at: file) }

    for i in 1...25 {
        svc.saveLearning(PlanningLearning(taskContext: "T", badStepTitle: "B\(i)", lesson: "Lesson \(i)"))
    }
    let loaded = svc.loadLearnings()
    #expect(loaded.count == 20)
    // The earliest five should have been dropped (kept the last 20).
    #expect(loaded.first?.lesson == "Lesson 6")
    #expect(loaded.last?.lesson == "Lesson 25")
}

@Test func memoryService_deletes_by_id() {
    let (svc, file) = makeMemoryService()
    defer { try? FileManager.default.removeItem(at: file) }

    let keep = PlanningLearning(taskContext: "T", badStepTitle: "keep", lesson: "Keep me")
    let drop = PlanningLearning(taskContext: "T", badStepTitle: "drop", lesson: "Drop me")
    svc.saveLearning(keep)
    svc.saveLearning(drop)

    svc.deleteLearning(id: drop.id)
    let loaded = svc.loadLearnings()
    #expect(loaded.count == 1)
    #expect(loaded.first?.lesson == "Keep me")
}

@Test func memoryService_clearAll_removes_file() {
    let (svc, file) = makeMemoryService()
    defer { try? FileManager.default.removeItem(at: file) }

    svc.saveLearning(PlanningLearning(taskContext: "T", badStepTitle: "B", lesson: "L"))
    #expect(FileManager.default.fileExists(atPath: file.path))

    svc.clearAllLearnings()
    #expect(svc.loadLearnings().isEmpty)
    #expect(!FileManager.default.fileExists(atPath: file.path))
}
