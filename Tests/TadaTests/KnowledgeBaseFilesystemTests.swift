import Foundation
import Testing
@testable import Tada

// MARK: - KnowledgeBaseFilesystem Tests

@Test func parseFrontmatter_parses_simple_fields() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp"), rootURL: URL(fileURLWithPath: "/tmp"))

    let raw = """
    ---
    title: Test Note
    taskId: 12345
    status: completed
    ---

    Body content
    """

    let meta = await fs.parseFrontmatter(raw)

    #expect(meta["title"] == "Test Note")
    #expect(meta["taskId"] == "12345")
    #expect(meta["status"] == "completed")
}

@Test func parseFrontmatter_parses_quoted_values() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp"), rootURL: URL(fileURLWithPath: "/tmp"))

    let raw = """
    ---
    title: "A \"quoted\" title"
    taskId: abc-123
    ---

    Body
    """

    let meta = await fs.parseFrontmatter(raw)

    #expect(meta["title"] == "A \"quoted\" title")
    #expect(meta["taskId"] == "abc-123")
}

@Test func parseFrontmatter_returns_empty_for_non_frontmatter() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp"), rootURL: URL(fileURLWithPath: "/tmp"))

    #expect((await fs.parseFrontmatter("Just plain text")).isEmpty)
}

@Test func parseFrontmatter_returns_empty_for_incomplete_frontmatter() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp"), rootURL: URL(fileURLWithPath: "/tmp"))

    #expect((await fs.parseFrontmatter("---\ntitle: Test")).isEmpty)
}

@Test func parseFrontmatter_handles_empty_fields() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp"), rootURL: URL(fileURLWithPath: "/tmp"))

    let raw = """
    ---
    title: Test
    emptyField:
    ---

    Body
    """

    let meta = await fs.parseFrontmatter(raw)

    #expect(meta["title"] == "Test")
    #expect(meta["emptyField"] == "")
}

@Test func stripFrontmatter_strips_frontmatter_and_body() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp"), rootURL: URL(fileURLWithPath: "/tmp"))

    let raw = """
    ---
    title: Test
    taskId: 123
    ---

    # Title

    Body content here.
    """

    let stripped = await fs.stripFrontmatterAndMarkers(raw)

    #expect(!stripped.hasPrefix("---"))
    #expect(stripped.contains("# Title"))
    #expect(stripped.contains("Body content here."))
}

@Test func stripFrontmatter_strips_related_markers() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp"), rootURL: URL(fileURLWithPath: "/tmp"))

    let raw = """
    ---
    title: Test
    ---

    # Title

    Some content.

    <!-- tada:related:start -->
    This should be removed.
    <!-- tada:related:end -->

    More content after.
    """

    let stripped = await fs.stripFrontmatterAndMarkers(raw)

    #expect(!stripped.contains("tada:related"))
    #expect(!stripped.contains("This should be removed."))
    #expect(stripped.contains("More content after."))
}

@Test func stripFrontmatter_strips_both_frontmatter_and_markers() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp"), rootURL: URL(fileURLWithPath: "/tmp"))

    let raw = """
    ---
    title: Test
    ---

    # Title

    <!-- tada:related:start -->
    Removed.
    <!-- tada:related:end -->

    Keep this.
    """

    let stripped = await fs.stripFrontmatterAndMarkers(raw)

    #expect(!stripped.hasPrefix("---"))
    #expect(!stripped.contains("tada:related"))
    #expect(stripped.contains("# Title"))
    #expect(stripped.contains("Keep this."))
}

@Test func stripFrontmatter_returns_empty_for_non_frontmatter() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp"), rootURL: URL(fileURLWithPath: "/tmp"))

    let stripped = await fs.stripFrontmatterAndMarkers("Plain text")
    #expect(stripped == "Plain text")
}

@Test func relativePath_same_directory() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp/notes"), rootURL: URL(fileURLWithPath: "/tmp"))

    let target = URL(fileURLWithPath: "/tmp/notes/file.md")
    #expect(await fs.relativePath(from: URL(fileURLWithPath: "/tmp/notes"), to: target) == "file.md")
}

@Test func relativePath_parent_directory() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp/notes"), rootURL: URL(fileURLWithPath: "/tmp"))

    let target = URL(fileURLWithPath: "/tmp/index.md")
    #expect(await fs.relativePath(from: URL(fileURLWithPath: "/tmp/notes"), to: target) == "../index.md")
}

@Test func relativePath_subdirectory() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp/notes"), rootURL: URL(fileURLWithPath: "/tmp"))

    let target = URL(fileURLWithPath: "/tmp/notes/subdir/file.md")
    #expect(await fs.relativePath(from: URL(fileURLWithPath: "/tmp/notes"), to: target) == "subdir/file.md")
}

@Test func relativePath_two_levels_up() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp/notes/a/b"), rootURL: URL(fileURLWithPath: "/tmp"))

    let target = URL(fileURLWithPath: "/tmp/other/file.md")
    #expect(await fs.relativePath(from: URL(fileURLWithPath: "/tmp/notes/a/b"), to: target) == "../../../other/file.md")
}

@Test func subtaskFilename_formats_correctly() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp"), rootURL: URL(fileURLWithPath: "/tmp"))

    let snap = (id: UUID(), order: 0, title: "First Step")
    #expect((await fs.subtaskFilename(for: snap)).hasPrefix("01-"))

    let snap2 = (id: UUID(), order: 4, title: "Fifth Step")
    #expect((await fs.subtaskFilename(for: snap2)).hasPrefix("05-"))
}

@Test func imageFilename_formats_correctly() async {
    let fs = KnowledgeBaseFilesystem(notesURL: URL(fileURLWithPath: "/tmp"), rootURL: URL(fileURLWithPath: "/tmp"))

    #expect((await fs.imageFilename(for: 0, title: "Sketch")).hasSuffix(".png"))
    #expect((await fs.imageFilename(for: 9, title: "Drawing")).hasSuffix(".png"))
}
