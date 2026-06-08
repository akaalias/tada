import Foundation

/// One corpus exemplar: a task input and the question titles Sonnet asked for it.
/// (The champion exp056 pipeline only needs the input — for nearest-neighbour
/// retrieval — and the question strings — as external coverage axes.)
struct GoldExemplar: Sendable {
    let input: String
    let questions: [String]
}

/// The corpus-backed coverage bank. Loads the 600+ Sonnet (task → 7 questions)
/// sets bundled under `OnDeviceModels/corpus/`, used by the champion pipeline as
/// an EXTERNAL coverage prior: the questions Sonnet asks for the nearest task
/// types name the decision-critical axes the on-device draft should cover.
/// Ported from the FMDiscovery research `CorpusBank`, reading from the app bundle
/// instead of a source-relative directory.
enum DiscoveryCorpusBank {
    /// Load all corpus exemplars from the bundled `corpus/` directory. Returns []
    /// when the corpus is absent (e.g. tests/CI without bundled assets) — the
    /// pipeline then floors gracefully (drops the 8th question) without it.
    static func load() -> [GoldExemplar] {
        guard let dir = OnDeviceAssets.corpusURL,
              let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var out: [GoldExemplar] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = obj["input"] as? String,
                  let gold = obj["gold"] as? [String: Any],
                  let qs = gold["questions"] as? [[String: Any]] else { continue }
            let questions = qs.compactMap { $0["title"] as? String }
            guard questions.count == 7 else { continue }
            out.append(GoldExemplar(input: input, questions: questions))
        }
        return out
    }

    /// k nearest corpus exemplars with a NEAR-DUPLICATE CEILING: drop any exemplar
    /// whose input word-overlap Jaccard with the query is ≥ `jaccardCeiling` (and
    /// any exact match), so demonstrations stay genuinely OTHER tasks.
    static func nearestSemantic(to query: String, k: Int, jaccardCeiling: Double) -> [GoldExemplar] {
        func wordSet(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !$0.isLetter }.map(String.init).filter { !$0.isEmpty })
        }
        let qn = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let qWords = wordSet(query)
        let pool = load().filter { ex in
            let exn = ex.input.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if exn == qn { return false }
            let w = wordSet(ex.input)
            let uni = qWords.union(w).count
            let j = uni == 0 ? 0 : Double(qWords.intersection(w).count) / Double(uni)
            return j < jaccardCeiling
        }
        return SemanticRetrieval.nearest(query: query, candidates: pool, k: k,
                                         fallback: { q, kk in jaccardNearest(q, in: pool, k: kk) })
    }

    private static func jaccardNearest(_ query: String, in pool: [GoldExemplar], k: Int) -> [GoldExemplar] {
        func wordSet(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !$0.isLetter }.map(String.init).filter { !$0.isEmpty })
        }
        let q = wordSet(query)
        return pool.map { ex -> (GoldExemplar, Double) in
            let w = wordSet(ex.input)
            let inter = q.intersection(w).count, uni = q.union(w).count
            return (ex, uni == 0 ? 0 : Double(inter) / Double(uni))
        }
        .sorted { $0.1 > $1.1 }.prefix(k).map { $0.0 }
    }
}
