import Foundation
import Testing

@testable import Tada

// MARK: - OnDeviceDiscoveryService.dropToSeven (exp056 corpus-coverage drop)
//
// The on-device model itself can't run in unit tests, but the deterministic
// corpus-coverage selection that turns the adapter's 8 questions into 7 is pure
// math over injected vectors — so it's fully testable here.

private func q(_ text: String) -> FMQuestion {
    FMQuestion(question: text, detail: "", requiresExternalAction: false)
}

/// Orthonormal basis vector e_i in `dim` dimensions.
private func e(_ i: Int, dim: Int) -> [Double] {
    var v = Array(repeating: 0.0, count: dim)
    v[i] = 1
    return v
}

@Test func dropToSeven_returns_input_unchanged_when_seven_or_fewer() {
    let qs = (0..<7).map { q("q\($0)") }
    let out = OnDeviceDiscoveryService.dropToSeven(qs, titleVecs: nil, axisVecs: nil)
    #expect(out.count == 7)
    #expect(out.map { $0.question } == qs.map { $0.question })
}

@Test func dropToSeven_floors_to_first_seven_when_vectors_missing() {
    let qs = (0..<8).map { q("q\($0)") }
    // No embeddings available (the device-can't-embed / no-corpus floor).
    let out = OnDeviceDiscoveryService.dropToSeven(qs, titleVecs: nil, axisVecs: nil)
    #expect(out.count == 7)
    #expect(out.map { $0.question } == (0..<7).map { "q\($0)" })
}

@Test func dropToSeven_drops_a_redundant_question_and_preserves_coverage() {
    // 7 corpus axes e0..e6. Questions q0..q6 each uniquely cover one axis; q7 is a
    // DUPLICATE of q0's axis (e0) — it adds no new coverage. The selector must drop
    // one of the two e0 questions (removing any uniquely-covering question would
    // strictly lower coverage), and on the tie it drops the earlier (q0), leaving
    // every axis still covered.
    let dim = 7
    // q0 "dup-a" and q6 "dup-b" both cover e0; q1..q5 and q7 cover e1..e6.
    let texts = ["dup-a", "axis1", "axis2", "axis3", "axis4", "axis5", "dup-b", "axis6"]
    let vecs: [[Double]] = [
        e(0, dim: dim), e(1, dim: dim), e(2, dim: dim), e(3, dim: dim),
        e(4, dim: dim), e(5, dim: dim), e(0, dim: dim), e(6, dim: dim),
    ]
    let qs8 = texts.map { q($0) }
    let axes = (0..<7).map { e($0, dim: dim) }

    let out = OnDeviceDiscoveryService.dropToSeven(qs8, titleVecs: vecs, axisVecs: axes)

    #expect(out.count == 7)
    let kept = Set(out.map { $0.question })
    // Earlier duplicate dropped; later duplicate retained (e0 still covered).
    #expect(!kept.contains("dup-a"))
    #expect(kept.contains("dup-b"))
    // Every uniquely-covering question survives.
    for axis in ["axis1", "axis2", "axis3", "axis4", "axis5", "axis6"] {
        #expect(kept.contains(axis))
    }
}

// MARK: - DiscoveryCorpusBank invariants (robust to bundle presence/absence)

@Test func corpusBank_load_yields_only_well_formed_exemplars() {
    // load() is either [] (assets absent) or fully-parsed exemplars — never a
    // partially-parsed one. Every exemplar carries exactly 7 question titles.
    let all = DiscoveryCorpusBank.load()
    for ex in all {
        #expect(ex.questions.count == 7)
        #expect(!ex.input.isEmpty)
    }
}

@Test func corpusBank_nearestSemantic_respects_k_and_leave_one_out() {
    // Returns at most k, and never the query's own exemplar (exact-match drop).
    let query = "Apply for a community allotment plot this season"  // a corpus input
    let near = DiscoveryCorpusBank.nearestSemantic(to: query, k: 3, jaccardCeiling: 0.5)
    #expect(near.count <= 3)
    #expect(!near.contains { $0.input.lowercased() == query.lowercased() })
}
