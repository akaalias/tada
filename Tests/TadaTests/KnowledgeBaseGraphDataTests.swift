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
    body: String = ""
) -> KnowledgeGraphBuilder.NoteInput {
    .init(
        relativePath: path,
        title: title,
        isOverview: overview,
        isEntity: entity,
        folderRelativePath: folder,
        body: body
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
    #expect(g.nodes.first(where: { $0.id == "notes/A/_overview.md" })?.kind == "task")
    #expect(g.nodes.first(where: { $0.id == "notes/A/01-foo.md" })?.kind == "note")
    #expect(g.nodes.first(where: { $0.id == "notes/_entities/openai.md" })?.kind == "entity")
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
