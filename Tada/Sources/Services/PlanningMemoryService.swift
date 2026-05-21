import Foundation

struct PlanningLearning: Codable, Identifiable {
    let id: UUID
    let date: Date
    let taskContext: String
    let badStepTitle: String
    let lesson: String

    init(taskContext: String, badStepTitle: String, lesson: String) {
        self.id = UUID()
        self.date = Date()
        self.taskContext = taskContext
        self.badStepTitle = badStepTitle
        self.lesson = lesson
    }
}

class PlanningMemoryService {
    static let shared = PlanningMemoryService()

    private let fileURL: URL

    private convenience init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("Tada", isDirectory: true)

        // Create directory if needed
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)

        self.init(fileURL: appFolder.appendingPathComponent("planning_learnings.json"))
    }

    /// Designated initializer. The shared instance stores under Application Support; tests pass a
    /// temp file so they never touch the user's real learnings.
    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func loadLearnings() -> [PlanningLearning] {
        guard let data = try? Data(contentsOf: fileURL),
              let learnings = try? JSONDecoder().decode([PlanningLearning].self, from: data) else {
            return []
        }
        return learnings
    }

    func saveLearning(_ learning: PlanningLearning) {
        var learnings = loadLearnings()
        learnings.append(learning)

        // Keep only the last 20 learnings to avoid bloat
        if learnings.count > 20 {
            learnings = Array(learnings.suffix(20))
        }

        if let data = try? JSONEncoder().encode(learnings) {
            try? data.write(to: fileURL)
        }
    }

    func deleteLearning(id: UUID) {
        var learnings = loadLearnings()
        learnings.removeAll { $0.id == id }

        if let data = try? JSONEncoder().encode(learnings) {
            try? data.write(to: fileURL)
        }
    }

    func clearAllLearnings() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Format learnings for inclusion in AI prompts
    func getLearningsForPrompt() -> String {
        let learnings = loadLearnings()
        guard !learnings.isEmpty else { return "" }

        let formatted = learnings.map { learning in
            "- \(learning.lesson)"
        }.joined(separator: "\n")

        return """
        LEARNINGS FROM PAST MISTAKES (avoid these patterns):
        \(formatted)
        """
    }
}
