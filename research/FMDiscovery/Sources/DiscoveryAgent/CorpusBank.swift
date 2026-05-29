import Foundation

/// EXP-014: corpus-backed demonstration bank. Every prior retrieval variant
/// (exp003/007/008) drew from only the 12 generic hardcoded `GoldExemplars`, so
/// the "nearest" exemplar for a given task was frequently OFF-DOMAIN and modeled
/// the wrong decision-critical unknowns. `corpus/` holds 100+ Sonnet
/// (task → 7 questions) sets across diverse, specific task types — a far richer
/// retrieval bank the rules explicitly encourage growing and using. Retrieving
/// genuinely close-DOMAIN demonstrations should finally model the right
/// decision-critical unknowns for THIS task type (the coverage wall).
enum CorpusBank {
    /// Load all corpus exemplars from disk. The directory is derived from this
    /// source file's location so it resolves wherever the package is built/run.
    /// Falls back to the 12 hardcoded `GoldExemplars` if the corpus is unreadable.
    static func load() -> [GoldExemplar] {
        guard let dir = corpusDir,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return GoldExemplars.all
        }
        var out: [GoldExemplar] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let input = obj["input"] as? String,
                  let gold = obj["gold"] as? [String: Any],
                  let title = gold["taskTitle"] as? String,
                  let qs = gold["questions"] as? [[String: Any]] else { continue }
            let questions = qs.compactMap { $0["title"] as? String }
            guard questions.count == 7 else { continue }
            out.append(GoldExemplar(input: input, title: title, questions: questions, dimensions: []))
        }
        return out.isEmpty ? GoldExemplars.all : out
    }

    private static var corpusDir: URL? {
        // This file: <pkg>/Sources/DiscoveryAgent/CorpusBank.swift
        let pkg = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // DiscoveryAgent
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // FMDiscovery (package root)
        let dir = pkg.appendingPathComponent("corpus", isDirectory: true)
        return FileManager.default.fileExists(atPath: dir.path) ? dir : nil
    }

    /// k nearest corpus exemplars by on-device semantic similarity (NLEmbedding
    /// cosine), with a word-overlap Jaccard fallback when embeddings are absent.
    static func nearestSemantic(to query: String, k: Int) -> [GoldExemplar] {
        let pool = load()
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
