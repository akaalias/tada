import Foundation
import Testing
@testable import Tada

// MARK: - KnowledgeGraphBuilder Tests

private func input(
    _ path: String,
    title: String,
    overview: Bool = false,
    entity: Bool = false,
    folder: String,
    body: String = "",
    taskId: String? = nil
) -> KnowledgeGraphBuilder.NoteInput {
    .init(
        relativePath: path,
        title: title,
        isOverview: overview,
        isEntity: entity,
        folderRelativePath: folder,
        body: body,
        taskId: taskId
    )
}

@Test func graph_builds_nodes_with_kinds() {
    let inputs = [
        input("notes/A/_overview.md", title: "Task A", overview: true, folder: "notes/A"),
        input("notes/A/01-foo.md", title: "Foo", folder: "notes/A"),
        input("notes/_entities/openai.md", title: "OpenAI", entity: true, folder: "notes/_entities")
    ]
    let g = KnowledgeGraphBuilder.build(from: inputs)
    #expect(g.nodes.count == 3)
    #expect(g.nodes.first(where: { $0.id == "notes/A/_overview.md" })?.kind == "topLevelTask")
    #expect(g.nodes.first(where: { $0.id == "notes/A/01-foo.md" })?.kind == "subTask")
    #expect(g.nodes.first(where: { $0.id == "notes/_entities/openai.md" })?.kind == "entity")
}

@Test func graph_topLevelTask_node_carries_task_id() {
    let uuid = "11111111-1111-1111-1111-111111111111"
    let inputs = [
        input("notes/A/_overview.md", title: "Task A", overview: true, folder: "notes/A", taskId: uuid)
    ]
    let g = KnowledgeGraphBuilder.build(from: inputs)
    #expect(g.nodes.first?.taskId == uuid)
}

// MARK: - keepingTasks(in:) Tests

@Test func graph_keepingTasks_drops_nodes_and_links_for_other_tasks() {
    let inputs = [
        input("notes/A/_overview.md", title: "A", overview: true, folder: "notes/A", taskId: "task-A"),
        input("notes/A/01-foo.md", title: "Foo", folder: "notes/A",
              body: "[[../_entities/x.md|X]]", taskId: "task-A"),
        input("notes/B/_overview.md", title: "B", overview: true, folder: "notes/B", taskId: "task-B"),
        input("notes/B/01-bar.md", title: "Bar", folder: "notes/B", taskId: "task-B"),
        input("notes/_entities/x.md", title: "X", entity: true, folder: "notes/_entities")
    ]
    let g = KnowledgeGraphBuilder.build(from: inputs)
    let filtered = g.keepingTasks(in: ["task-B"])

    #expect(filtered.nodes.contains(where: { $0.id == "notes/A/_overview.md" }) == false)
    #expect(filtered.nodes.contains(where: { $0.id == "notes/A/01-foo.md" }) == false)
    #expect(filtered.nodes.contains(where: { $0.id == "notes/B/_overview.md" }))
    #expect(filtered.nodes.contains(where: { $0.id == "notes/_entities/x.md" }))

    let ids = Set(filtered.nodes.map(\.id))
    #expect(filtered.links.allSatisfy { ids.contains($0.source) && ids.contains($0.target) })
}

@Test func graph_keepingTasks_empty_set_keeps_only_entities() {
    let inputs = [
        input("notes/A/_overview.md", title: "A", overview: true, folder: "notes/A", taskId: "task-A"),
        input("notes/_entities/x.md", title: "X", entity: true, folder: "notes/_entities")
    ]
    let g = KnowledgeGraphBuilder.build(from: inputs)
    let filtered = g.keepingTasks(in: [])
    #expect(filtered.nodes.map(\.id) == ["notes/_entities/x.md"])
}

// MARK: - GraphTaskState Tests

@Test func graphTaskState_discovery_phase_is_discovery() {
    let t = TodoTask(title: "T")
    t.phase = .discovery
    #expect(GraphTaskState(task: t) == .discovery)
}

@Test func graphTaskState_execution_phase_is_execution() {
    let t = TodoTask(title: "T")
    t.phase = .execution
    #expect(GraphTaskState(task: t) == .execution)
}

@Test func graphTaskState_planning_discovery_overrides_phase() {
    let t = TodoTask(title: "T")
    t.phase = .execution
    t.planningStatus = .planningDiscovery
    #expect(GraphTaskState(task: t) == .discovery)
}

@Test func graphTaskState_planning_execution_overrides_phase() {
    let t = TodoTask(title: "T")
    t.phase = .discovery
    t.planningStatus = .planningExecution
    #expect(GraphTaskState(task: t) == .execution)
}

@Test func graphTaskState_completed_status_is_completed() {
    let t = TodoTask(title: "T")
    t.phase = .discovery
    t.markCompleted()
    #expect(GraphTaskState(task: t) == .completed)
}

@Test func graphTaskState_archived_status_is_completed() {
    let t = TodoTask(title: "T")
    t.status = .archived
    #expect(GraphTaskState(task: t) == .completed)
}

@Test func graph_creates_parent_links_from_overview_to_notes() {
    let inputs = [
        input("notes/A/_overview.md", title: "Task A", overview: true, folder: "notes/A"),
        input("notes/A/01-foo.md", title: "Foo", folder: "notes/A"),
        input("notes/A/02-bar.md", title: "Bar", folder: "notes/A")
    ]
    let g = KnowledgeGraphBuilder.build(from: inputs)
    let parentLinks = g.links.filter { $0.kind == "parent" }
    #expect(parentLinks.count == 2)
    #expect(parentLinks.contains(where: { $0.source == "notes/A/_overview.md" && $0.target == "notes/A/01-foo.md" }))
    #expect(parentLinks.contains(where: { $0.source == "notes/A/_overview.md" && $0.target == "notes/A/02-bar.md" }))
}

@Test func graph_creates_entity_links_from_body_wikilinks() {
    let body = "We use [[../_entities/openai.md|OpenAI]] and also [[../_entities/anthropic.md|Anthropic]]."
    let inputs = [
        input("notes/A/_overview.md", title: "A", overview: true, folder: "notes/A"),
        input("notes/A/01-foo.md", title: "Foo", folder: "notes/A", body: body),
        input("notes/_entities/openai.md", title: "OpenAI", entity: true, folder: "notes/_entities"),
        input("notes/_entities/anthropic.md", title: "Anthropic", entity: true, folder: "notes/_entities")
    ]
    let g = KnowledgeGraphBuilder.build(from: inputs)
    let entityLinks = g.links.filter { $0.kind == "entity" }
    #expect(entityLinks.count == 2)
    #expect(entityLinks.contains(where: { $0.source == "notes/A/01-foo.md" && $0.target == "notes/_entities/openai.md" }))
    #expect(entityLinks.contains(where: { $0.source == "notes/A/01-foo.md" && $0.target == "notes/_entities/anthropic.md" }))
}

@Test func graph_entity_link_target_byte_matches_node_id_across_unicode_normalisation() {
    // Entity filename on disk is NFD-decomposed ("o" + combining diaeresis), as macOS
    // stores it; the wikilink in the note body is NFC-composed ("ö"). Swift compares
    // them equal, but the emitted JSON must carry byte-identical strings or force-graph
    // can't resolve the link's node.
    let entityPathNFD = "notes/_entities/neuko\u{0308}lln.md"   // decomposed
    let body = "See [[../_entities/neuk\u{00F6}lln.md|Neukölln]]"   // composed
    let inputs = [
        input("notes/A/_overview.md", title: "A", overview: true, folder: "notes/A"),
        input("notes/A/01-foo.md", title: "Foo", folder: "notes/A", body: body),
        input(entityPathNFD, title: "Neukölln", entity: true, folder: "notes/_entities")
    ]
    let g = KnowledgeGraphBuilder.build(from: inputs)
    let entityLink = g.links.first { $0.kind == "entity" }
    let entityNode = g.nodes.first { $0.kind == "entity" }
    #expect(entityLink != nil)
    #expect(entityNode != nil)
    // Byte-exact comparison (Swift's == is canonical-equivalence-aware and would hide a mismatch).
    #expect(Array(entityLink!.target.unicodeScalars) == Array(entityNode!.id.unicodeScalars))
}

@Test func graph_skips_entity_links_to_unknown_targets() {
    let body = "References [[../_entities/ghost.md|Ghost]]"
    let inputs = [
        input("notes/A/_overview.md", title: "A", overview: true, folder: "notes/A"),
        input("notes/A/01-foo.md", title: "Foo", folder: "notes/A", body: body)
    ]
    let g = KnowledgeGraphBuilder.build(from: inputs)
    #expect(g.links.filter { $0.kind == "entity" }.isEmpty)
}

@Test func graph_creates_related_links_across_folders() {
    let body = """
    # Foo

    Body here.

    <!-- tada:related:start -->
    ## Related

    - [[../B/01-bar.md|Bar]]
    <!-- tada:related:end -->
    """
    let inputs = [
        input("notes/A/_overview.md", title: "A", overview: true, folder: "notes/A"),
        input("notes/A/01-foo.md", title: "Foo", folder: "notes/A", body: body),
        input("notes/B/_overview.md", title: "B", overview: true, folder: "notes/B"),
        input("notes/B/01-bar.md", title: "Bar", folder: "notes/B")
    ]
    let g = KnowledgeGraphBuilder.build(from: inputs)
    let relatedLinks = g.links.filter { $0.kind == "related" }
    #expect(relatedLinks.count == 1)
    #expect(relatedLinks.first?.source == "notes/A/01-foo.md")
    #expect(relatedLinks.first?.target == "notes/B/01-bar.md")
}

@Test func graph_dedupes_duplicate_links() {
    let body = "[[../_entities/x.md|X]] and again [[../_entities/x.md|X]]"
    let inputs = [
        input("notes/A/_overview.md", title: "A", overview: true, folder: "notes/A"),
        input("notes/A/01-foo.md", title: "Foo", folder: "notes/A", body: body),
        input("notes/_entities/x.md", title: "X", entity: true, folder: "notes/_entities")
    ]
    let g = KnowledgeGraphBuilder.build(from: inputs)
    let entityLinks = g.links.filter { $0.kind == "entity" }
    #expect(entityLinks.count == 1)
}

@Test func graph_overview_has_no_parent_link_to_itself() {
    let inputs = [
        input("notes/A/_overview.md", title: "A", overview: true, folder: "notes/A")
    ]
    let g = KnowledgeGraphBuilder.build(from: inputs)
    #expect(g.links.isEmpty)
}

@Test func graph_emits_valid_json() throws {
    let inputs = [
        input("notes/A/_overview.md", title: "A", overview: true, folder: "notes/A"),
        input("notes/A/01-foo.md", title: "Foo", folder: "notes/A", body: "[[../_entities/x.md|X]]"),
        input("notes/_entities/x.md", title: "X", entity: true, folder: "notes/_entities")
    ]
    let g = KnowledgeGraphBuilder.build(from: inputs)
    let data = try JSONEncoder().encode(g)
    let roundtrip = try JSONDecoder().decode(KnowledgeGraphData.self, from: data)
    #expect(roundtrip == g)
}
