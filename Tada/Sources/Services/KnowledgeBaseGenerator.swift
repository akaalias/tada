import Foundation

// MARK: - Response Extraction Helpers

/// Extracts structured data from a sub-task's response for wiki note generation.
enum KnowledgeResponseExtractor {

    static func responseString(for subTask: SubTask) -> String {
        guard let data = subTask.actionResponseData,
              let response = try? JSONDecoder().decode(ActionResponse.self, from: data) else {
            return "(no response recorded)"
        }
        let parts = response.values.compactMap { _, value -> String? in
            switch value {
            case .string(let s):
                if s.hasPrefix("data:image") { return "(drawing)" }
                return s.isEmpty ? nil : s
            case .number(let n):
                return String(format: "%g", n)
            case .boolean(let b):
                return b ? "Yes" : "No"
            case .stringArray(let arr):
                return arr.isEmpty ? nil : arr.joined(separator: ", ")
            case .date(let d):
                return d.formatted(date: .abbreviated, time: .omitted)
            }
        }
        return parts.isEmpty ? "(no response recorded)" : parts.joined(separator: "; ")
    }

    static func extractPNG(from subTask: SubTask) -> Data? {
        guard let data = subTask.actionResponseData,
              let response = try? JSONDecoder().decode(ActionResponse.self, from: data) else {
            return nil
        }
        for (_, value) in response.values {
            if case .string(let s) = value, s.hasPrefix("data:image/png;base64,") {
                let base64 = String(s.dropFirst("data:image/png;base64,".count))
                return Data(base64Encoded: base64)
            }
        }
        return nil
    }

    static func extractTableMarkdown(from subTask: SubTask) -> String? {
        guard let data = subTask.actionResponseData,
              let response = try? JSONDecoder().decode(ActionResponse.self, from: data) else {
            return nil
        }
        for (_, value) in response.values {
            if case .string(let s) = value, s.hasPrefix("__tada_table__") {
                let json = String(s.dropFirst("__tada_table__".count))
                guard let jsonData = json.data(using: .utf8),
                      let dict = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                      let columns = dict["columns"] as? [[String: String]],
                      let rows = dict["rows"] as? [[String: String]],
                      !columns.isEmpty else { return nil }

                let header = "| " + columns.map { $0["label"] ?? "" }.joined(separator: " | ") + " |"
                let separator = "| " + columns.map { _ in "---" }.joined(separator: " | ") + " |"
                let rowLines = rows.map { row -> String in
                    let cells = columns.map { col -> String in
                        let id = col["id"] ?? ""
                        let raw = row[id] ?? ""
                        if col["type"] == "currency" && !raw.isEmpty {
                            return "€\(raw)"
                        }
                        return raw
                    }
                    return "| " + cells.joined(separator: " | ") + " |"
                }
                var table = ([header, separator] + rowLines).joined(separator: "\n")
                if let total = dict["total"] as? Int,
                   let hasCurrency = dict["hasCurrency"] as? Bool,
                   hasCurrency && total > 0 {
                    table += "\n\n_Total: €\(total)_"
                }
                return table
            }
        }
        return nil
    }
}

// MARK: - Note Generation Orchestration

/// Orchestrates AI-powered note generation for sub-tasks and task overviews.
final actor KnowledgeBaseGenerator {
    private let filesystem: KnowledgeBaseFilesystem

    init(filesystem: KnowledgeBaseFilesystem) {
        self.filesystem = filesystem
    }

    func generateSubtaskNotes(
        _ snapshots: [SubtaskSnapshot],
        taskId: UUID,
        taskTitle: String,
        folderURL: URL
    ) async {
        guard !snapshots.isEmpty, let apiKey = APIKeyManager.getAPIKey() else { return }
        let service = KnowledgeAIService(apiKey: apiKey)

        // Run notes in parallel for speed.
        await withTaskGroup(of: Void.self) { group in
            for snap in snapshots {
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        // If the sub-task captured a sketch, save it next to the note as PNG so the
                        // wiki can embed it and the AI can see it for richer descriptions.
                        var imageMarkdown: String? = nil
                        if let pngData = snap.imagePNG {
                            let imageFilename = await self.filesystem.imageFilename(for: snap.order, title: snap.title)
                            try? pngData.write(to: folderURL.appendingPathComponent(imageFilename))
                            imageMarkdown = "![\(snap.title) sketch](./\(imageFilename))"
                        }

                        let note = try await service.generateSubtaskNote(
                            taskTitle: taskTitle,
                            subtaskTitle: snap.title,
                            subtaskDescription: snap.description,
                            response: snap.response,
                            attachedImage: snap.imagePNG,
                            tableMarkdown: snap.tableMarkdown
                        )

                        // Append the image and/or table to the body so they render on the wiki page.
                        var body = note.body
                        if let imageMarkdown {
                            body += "\n\n\(imageMarkdown)"
                        }
                        if let table = snap.tableMarkdown {
                            body += "\n\n\(table)"
                        }
                        let augmented = GeneratedKnowledgeNote(title: note.title, body: body)

                        await self.filesystem.writeNote(
                            augmented,
                            filename: await self.filesystem.subtaskFilename(for: (snap.id, snap.order, snap.title)),
                            taskId: taskId,
                            parentTitle: taskTitle,
                            folderURL: folderURL,
                            sourceSubtaskTitle: snap.title
                        )
                        print("[KnowledgeBase] Wrote sub-task note: \(await self.filesystem.subtaskFilename(for: (snap.id, snap.order, snap.title)))")
                    } catch {
                        print("[KnowledgeBase] Failed to generate sub-task note for '\(snap.title)': \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    func generateTaskOverviewNote(
        taskId: UUID,
        taskTitle: String,
        originalInput: String,
        taskDescription: String,
        subtaskSummaries: [(title: String, response: String, filename: String)],
        folderURL: URL
    ) async {
        guard let apiKey = APIKeyManager.getAPIKey() else { return }
        do {
            let service = KnowledgeAIService(apiKey: apiKey)
            let note = try await service.generateTaskOverviewNote(
                taskTitle: taskTitle,
                originalInput: originalInput,
                taskDescription: taskDescription,
                subtaskSummaries: subtaskSummaries
            )
            await filesystem.writeNote(
                note,
                filename: "00-\(slugify(note.title)).md",
                taskId: taskId,
                parentTitle: taskTitle,
                folderURL: folderURL,
                sourceSubtaskTitle: nil
            )
            print("[KnowledgeBase] Wrote task overview note")
        } catch {
            print("[KnowledgeBase] Failed to generate task overview note: \(error.localizedDescription)")
        }
    }

    private func slugify(_ s: String) -> String {
        let lowered = s.lowercased()
        let allowed = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        let collapsed = String(allowed).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
        return String(collapsed.prefix(48))
    }
}
