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
                return s.isEmpty ? nil : s
            case .number(let n):
                return String(format: "%g", n)
            case .boolean(let b):
                return b ? "Yes" : "No"
            case .stringArray(let arr):
                return arr.isEmpty ? nil : arr.joined(separator: ", ")
            case .date(let d):
                return d.formatted(date: .abbreviated, time: .omitted)
            case .range(let lower, let upper):
                return String(format: "%g - %g", lower, upper)
            case .tree(let nodes):
                return nodes.isEmpty ? nil : nodes.map(\.label).joined(separator: ", ")
            case .table(let table):
                return table.summary
            case .image(_, let description):
                return description.isEmpty ? "(drawing)" : description
            }
        }
        return parts.isEmpty ? "(no response recorded)" : parts.joined(separator: "; ")
    }

    /// Returns the user's raw text input for a sub-task — excluding drawings and structured tables,
    /// which are already preserved separately as PNG/markdown alongside the AI-rewritten note.
    static func originalTextInput(for subTask: SubTask) -> String? {
        guard let data = subTask.actionResponseData,
              let response = try? JSONDecoder().decode(ActionResponse.self, from: data) else {
            return nil
        }
        let parts = response.values.compactMap { _, value -> String? in
            switch value {
            case .string(let s):
                return s.isEmpty ? nil : s
            case .number(let n):
                return String(format: "%g", n)
            case .boolean(let b):
                return b ? "Yes" : "No"
            case .stringArray(let arr):
                return arr.isEmpty ? nil : arr.joined(separator: ", ")
            case .date(let d):
                return d.formatted(date: .abbreviated, time: .omitted)
            case .range(let lower, let upper):
                return String(format: "%g - %g", lower, upper)
            case .tree(let nodes):
                guard !nodes.isEmpty else { return nil }
                return nodes.map { String(repeating: "  ", count: $0.depth) + $0.label }
                    .joined(separator: "\n")
            case .table, .image:
                // Tables and drawings are preserved separately as markdown / PNG.
                return nil
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    static func extractPNG(from subTask: SubTask) -> Data? {
        guard let data = subTask.actionResponseData,
              let response = try? JSONDecoder().decode(ActionResponse.self, from: data) else {
            return nil
        }
        for (_, value) in response.values {
            if case .image(let png, _) = value {
                return png
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
            if case .table(let table) = value, !table.columns.isEmpty {
                return table.markdown
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

    /// Generates the atomic note for each snapshot. Returns the on-disk URLs of the notes that
    /// were successfully written — used to trigger per-note link discovery afterwards.
    @discardableResult
    func generateSubtaskNotes(
        _ snapshots: [SubtaskSnapshot],
        taskId: UUID,
        taskTitle: String,
        folderURL: URL
    ) async -> [URL] {
        guard !snapshots.isEmpty, let apiKey = APIKeyManager.getAPIKey() else { return [] }
        let service = KnowledgeAIService(apiKey: apiKey)

        // Run notes in parallel for speed.
        return await withTaskGroup(of: URL?.self) { group in
            for snap in snapshots {
                group.addTask { [weak self] in
                    guard let self else { return nil }
                    do {
                        // If the sub-task captured a sketch, save it next to the note as PNG so the
                        // wiki can embed it and the AI can see it for richer descriptions.
                        var imageMarkdown: String? = nil
                        if let pngData = snap.imagePNG {
                            let imageFilename = await self.filesystem.imageFilename(for: snap.order, title: snap.title)
                            try? pngData.write(to: folderURL.appendingPathComponent(imageFilename))
                            imageMarkdown = "![\(snap.title) sketch](./\(imageFilename))"
                        }

                        // Both AI passes inherit the sub-task's phase so the Console
                        // colours the request to match the work item it serves.
                        let requestPhase = APIRequestPhase(snap.phase)

                        let note = try await service.generateSubtaskNote(
                            taskTitle: taskTitle,
                            subtaskTitle: snap.title,
                            subtaskDescription: snap.description,
                            response: snap.response,
                            attachedImage: snap.imagePNG,
                            tableMarkdown: snap.tableMarkdown,
                            phase: requestPhase
                        )

                        // Run a second AI pass that extracts high-signal entities into atomic sub-notes
                        // and rewrites the body with first-occurrence wikilinks to them.
                        let entityLinkedBody = await self.runEntityPass(
                            service: service,
                            noteTitle: note.title,
                            noteBody: note.body,
                            phase: requestPhase
                        )

                        // Append the image and/or table to the body so they render on the wiki page.
                        var body = entityLinkedBody
                        if let imageMarkdown {
                            body += "\n\n\(imageMarkdown)"
                        }
                        if let table = snap.tableMarkdown {
                            body += "\n\n\(table)"
                        }
                        let augmented = GeneratedKnowledgeNote(title: note.title, body: body)

                        let filename = await self.filesystem.subtaskFilename(for: (snap.id, snap.order, snap.title))
                        await self.filesystem.writeNote(
                            augmented,
                            filename: filename,
                            taskId: taskId,
                            parentTitle: taskTitle,
                            folderURL: folderURL,
                            sourceSubtaskTitle: snap.title,
                            originalInput: KnowledgeResponseExtractor.originalTextInput(for: snap.subTask)
                        )
                        print("[KnowledgeBase] Wrote sub-task note: \(filename)")
                        return folderURL.appendingPathComponent(filename)
                    } catch {
                        print("[KnowledgeBase] Failed to generate sub-task note for '\(snap.title)': \(AppError.userMessage(from: error))")
                        return nil
                    }
                }
            }

            var writtenURLs: [URL] = []
            for await url in group {
                if let url { writtenURLs.append(url) }
            }
            return writtenURLs
        }
    }

    /// Runs the entity-extraction pass: reads the current entity list, asks the AI to identify
    /// entities + rewrite the body, canonicalises slugs/paths, and writes any new entity notes.
    /// Returns the rewritten body. On error returns the original body unchanged.
    private func runEntityPass(
        service: KnowledgeAIService,
        noteTitle: String,
        noteBody: String,
        phase: APIRequestPhase = .knowledge
    ) async -> String {
        let existing = await filesystem.listEntities()
        let refs = existing.map { ExistingEntityRef(slug: $0.slug, title: $0.title) }
        do {
            let result = try await service.extractEntitiesAndLink(
                noteTitle: noteTitle,
                noteBody: noteBody,
                existingEntities: refs,
                phase: phase
            )
            let existingSlugs = Set(existing.map { $0.slug })
            let canonicalized = KnowledgeBaseEntityLinker.canonicalize(
                linkedBody: result.linkedBody,
                newEntities: result.newEntities,
                existingSlugs: existingSlugs
            )
            for entity in canonicalized.finalNewEntities {
                let created = await filesystem.writeEntityNote(
                    slug: entity.slug,
                    displayName: entity.displayName,
                    body: entity.body
                )
                if created {
                    print("[KnowledgeBase] Wrote entity note: _entities/\(entity.slug).md")
                }
            }
            return canonicalized.body
        } catch {
            print("[KnowledgeBase] Entity extraction failed; keeping unlinked body: \(AppError.userMessage(from: error))")
            return noteBody
        }
    }

    /// Runs the entity-extraction pass on a single note: reads the body, asks the AI for entities,
    /// writes any new `_entities/<slug>.md` files, and splices the linked body back in. Idempotent:
    /// returns false without an AI call if the note already contains entity wikilinks.
    @discardableResult
    func runEntityExtraction(for url: URL) async -> Bool {
        guard let apiKey = APIKeyManager.getAPIKey() else {
            print("[KnowledgeBase] Entity extraction skipped: no API key configured")
            return false
        }
        let service = KnowledgeAIService(apiKey: apiKey)
        return await backfillSingleNote(url: url, service: service)
    }

    /// Returns true if the note was rewritten with entity links.
    private func backfillSingleNote(url: URL, service: KnowledgeAIService) async -> Bool {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return false }
        guard let region = KnowledgeBaseEntityLinker.extractBodyRegion(from: raw) else { return false }
        if region.body.contains("[[\(KnowledgeBaseFilesystem.entityLinkPrefix)") {
            return false  // already linked, skip
        }
        let title = await filesystem.parseFrontmatter(raw)["title"] ?? ""
        let existing = await filesystem.listEntities()
        let refs = existing.map { ExistingEntityRef(slug: $0.slug, title: $0.title) }
        do {
            let result = try await service.extractEntitiesAndLink(
                noteTitle: title,
                noteBody: region.body,
                existingEntities: refs
            )
            let canonicalized = KnowledgeBaseEntityLinker.canonicalize(
                linkedBody: result.linkedBody,
                newEntities: result.newEntities,
                existingSlugs: Set(existing.map { $0.slug })
            )
            for entity in canonicalized.finalNewEntities {
                let created = await filesystem.writeEntityNote(
                    slug: entity.slug,
                    displayName: entity.displayName,
                    body: entity.body
                )
                if created {
                    print("[KnowledgeBase] Backfill wrote entity: _entities/\(entity.slug).md")
                }
            }
            // Splice the linked body back in, preserving surrounding whitespace.
            var updated = raw
            updated.replaceSubrange(region.range, with: "\n" + canonicalized.body + "\n")
            try? updated.write(to: url, atomically: true, encoding: .utf8)
            print("[KnowledgeBase] Backfill linked: \(url.lastPathComponent)")
            return true
        } catch {
            print("[KnowledgeBase] Backfill failed for \(url.lastPathComponent): \(AppError.userMessage(from: error))")
            return false
        }
    }

    /// Generates the task-level overview note. Returns its on-disk URL on success, or nil.
    @discardableResult
    func generateTaskOverviewNote(
        taskId: UUID,
        taskTitle: String,
        originalInput: String,
        taskDescription: String,
        subtaskSummaries: [(title: String, response: String, filename: String)],
        folderURL: URL
    ) async -> URL? {
        guard let apiKey = APIKeyManager.getAPIKey() else { return nil }
        do {
            let service = KnowledgeAIService(apiKey: apiKey)
            let note = try await service.generateTaskOverviewNote(
                taskTitle: taskTitle,
                originalInput: originalInput,
                taskDescription: taskDescription,
                subtaskSummaries: subtaskSummaries
            )
            let entityLinkedBody = await runEntityPass(
                service: service,
                noteTitle: note.title,
                noteBody: note.body
            )
            let augmented = GeneratedKnowledgeNote(title: note.title, body: entityLinkedBody)
            let filename = "00-\(KnowledgeBaseFilesystem.slug(from: note.title)).md"
            await filesystem.writeNote(
                augmented,
                filename: filename,
                taskId: taskId,
                parentTitle: taskTitle,
                folderURL: folderURL,
                sourceSubtaskTitle: nil,
                originalInput: originalInput
            )
            print("[KnowledgeBase] Wrote task overview note")
            return folderURL.appendingPathComponent(filename)
        } catch {
            print("[KnowledgeBase] Failed to generate task overview note: \(AppError.userMessage(from: error))")
            return nil
        }
    }

}
