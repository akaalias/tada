import Foundation
import Contract

/// The real judge: Sonnet compares the candidate's questions against the gold
/// questions for the same task (pairwise) and scores the candidate on the
/// rubric. Part of the immutable harness.
public struct AnthropicJudge: Judge {
    let client: AnthropicClient
    public init(client: AnthropicClient) { self.client = client }

    public func judge(input: String, gold: DiscoveryResult, candidate: DiscoveryResult) async throws -> JudgeVerdict {
        let user = """
        A user entered this task: "\(input)"

        Two assistants each produced a title and 7 clarifying questions to ask the user before planning. Judge impartially.

        SET A (reference):
        title: \(gold.taskTitle)
        \(numbered(gold))

        SET B (candidate):
        title: \(candidate.taskTitle)
        \(numbered(candidate))

        Score SET B on each rubric dimension (1-5), then decide which set is better overall for helping plan this specific task.
        """
        let data = try await client.toolCall(system: Self.system, user: user, tool: Self.tool, maxTokens: 1024)
        let out = try JSONDecoder().decode(JudgeToolOutput.self, from: data)
        let pairwise: Pairwise = {
            switch out.better.uppercased() {
            case "B": return .fmBetter
            case "A": return .goldBetter
            default: return .tie
            }
        }()
        return JudgeVerdict(
            pairwise: pairwise,
            rubric: Rubric(atomicity: clamp(out.atomicity), specificity: clamp(out.specificity),
                           coverage: clamp(out.coverage), naturalness: clamp(out.naturalness),
                           nonRedundancy: clamp(out.nonRedundancy)),
            notes: out.notes
        )
    }

    private func numbered(_ r: DiscoveryResult) -> String {
        r.questions.enumerated().map { i, q in "\(i + 1). \(q.title)" }.joined(separator: "\n")
    }
    private func clamp(_ x: Int) -> Int { min(5, max(1, x)) }

    static let system = """
    You are a strict, impartial evaluator of clarifying questions a task-planning assistant asks a user. Rate SET B (the candidate) on five dimensions, each 1 (poor) to 5 (excellent):
    - atomicity: each question asks exactly ONE thing; never combines two asks with "and"/"or".
    - specificity: questions are concrete to THIS task, not generic filler like "any other preferences?".
    - coverage: the 7 questions together cover the important unknowns needed to plan the task well.
    - naturalness: phrasing reads like a thoughtful human coach — concise, clear, not robotic.
    - nonRedundancy: questions do not overlap or repeat each other.
    Then pick which SET (A or B) is better overall for planning this task, or "tie" if genuinely equal. Be willing to say B is better when it is — do not favour A by default. Judge only what is written.
    """

    struct JudgeToolOutput: Codable {
        let better: String
        let atomicity: Int
        let specificity: Int
        let coverage: Int
        let naturalness: Int
        let nonRedundancy: Int
        let notes: String
    }

    static var tool: [String: Any] { [
        "name": "judge_discovery",
        "description": "Record the pairwise verdict and rubric scores",
        "input_schema": [
            "type": "object",
            "properties": [
                "better": ["type": "string", "enum": ["A", "B", "tie"], "description": "Which set is better overall, or tie"],
                "atomicity": intScore("one ask per question, no and/or"),
                "specificity": intScore("concrete to this task, not generic"),
                "coverage": intScore("the 7 cover the important unknowns"),
                "naturalness": intScore("reads like a thoughtful human coach"),
                "nonRedundancy": intScore("questions do not overlap"),
                "notes": ["type": "string", "description": "One or two sentences: the candidate's main weakness vs the reference, to guide iteration."],
            ],
            "required": ["better", "atomicity", "specificity", "coverage", "naturalness", "nonRedundancy", "notes"],
        ],
    ] }

    static func intScore(_ desc: String) -> [String: Any] {
        ["type": "integer", "minimum": 1, "maximum": 5, "description": desc]
    }
}
