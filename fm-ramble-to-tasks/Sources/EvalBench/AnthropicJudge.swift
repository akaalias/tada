import Foundation
import Contract

/// The real judge: Sonnet compares the candidate's extracted tasks against the
/// gold tasks for the same input (pairwise) and scores the candidate on the
/// rubric. Diagnostic signal — the headline number is the set-match F1.
public struct AnthropicJudge: Judge {
    let client: AnthropicClient
    public init(client: AnthropicClient) { self.client = client }

    public func judge(input: String, gold: RambleResult, candidate: RambleResult) async throws -> JudgeVerdict {
        let user = """
        A user brain-dumped this free-form input: "\(input)"

        Two assistants each extracted the distinct, actionable tasks from it. Judge impartially.

        SET A (reference):
        \(numbered(gold))

        SET B (candidate):
        \(numbered(candidate))

        Score SET B on each rubric dimension (1-5), then decide which set better captures the user's actual tasks for this specific input.
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
            rubric: Rubric(faithfulness: clamp(out.faithfulness), atomicity: clamp(out.atomicity),
                           actionability: clamp(out.actionability), coverage: clamp(out.coverage),
                           nonRedundancy: clamp(out.nonRedundancy)),
            notes: out.notes
        )
    }

    private func numbered(_ r: RambleResult) -> String {
        r.tasks.isEmpty ? "(no tasks)" : r.tasks.enumerated().map { i, t in "\(i + 1). \(t)" }.joined(separator: "\n")
    }
    private func clamp(_ x: Int) -> Int { min(5, max(1, x)) }

    static let system = """
    You are a strict, impartial evaluator of how well an assistant extracted the distinct, actionable tasks from a user's free-form brain-dump. Rate SET B (the candidate) on five dimensions, each 1 (poor) to 5 (excellent):
    - faithfulness: every task traces to something in the input; nothing is invented or hallucinated.
    - atomicity: each task is exactly ONE action; never combines two with "and"/"or".
    - actionability: each item is a real thing to DO, not a vague wish, feeling, or musing.
    - coverage: the set captures EVERY distinct intention in the input, missing none.
    - nonRedundancy: no two tasks are the same intention (including a thought the user repeated or returned to).
    An empty set is the correct answer when the input contains no actionable task.
    Then pick which SET (A or B) better captures the user's actual tasks, or "tie" if genuinely equal. Be willing to say B is better when it is — do not favour A by default. Judge only what is written.
    """

    struct JudgeToolOutput: Codable {
        let better: String
        let faithfulness: Int
        let atomicity: Int
        let actionability: Int
        let coverage: Int
        let nonRedundancy: Int
        let notes: String
    }

    static var tool: [String: Any] { [
        "name": "judge_split",
        "description": "Record the pairwise verdict and rubric scores",
        "input_schema": [
            "type": "object",
            "properties": [
                "better": ["type": "string", "enum": ["A", "B", "tie"], "description": "Which set is better overall, or tie"],
                "faithfulness": intScore("every task traces to the input; nothing invented"),
                "atomicity": intScore("each task is ONE action, no and/or"),
                "actionability": intScore("real to-dos, not vague musings"),
                "coverage": intScore("captures every distinct intention in the input"),
                "nonRedundancy": intScore("no two tasks are the same intention"),
                "notes": ["type": "string", "description": "One or two sentences: the candidate's main weakness vs the reference, to guide iteration."],
            ],
            "required": ["better", "faithfulness", "atomicity", "actionability", "coverage", "nonRedundancy", "notes"],
        ],
    ] }

    static func intScore(_ desc: String) -> [String: Any] {
        ["type": "integer", "minimum": 1, "maximum": 5, "description": desc]
    }
}
