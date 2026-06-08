import Foundation
import Contract

/// One evaluation case: a user input and the gold (Sonnet) output for it.
public struct GoldCase: Codable, Sendable {
    public var id: String
    public var input: String
    public var gold: RambleResult

    public init(id: String, input: String, gold: RambleResult) {
        self.id = id
        self.input = input
        self.gold = gold
    }
}

public enum GoldStore {
    /// Load all gold cases from a directory of `<id>.json` files.
    public static func load(from dir: URL) throws -> [GoldCase] {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let decoder = JSONDecoder()
        return try files.map { try decoder.decode(GoldCase.self, from: Data(contentsOf: $0)) }
    }

    public static func save(_ cases: [GoldCase], to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        for c in cases {
            try encoder.encode(c).write(to: dir.appendingPathComponent("\(c.id).json"))
        }
    }
}
