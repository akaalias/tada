import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Tada

// MARK: - Task.addDiscoverySubTasks

@MainActor
@Test func task_addDiscoverySubTasks_inserts_capped_and_marks_first_current() throws {
    let schema = Schema([TodoTask.self, SubTask.self])
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    let context = ModelContext(container)

    let task = TodoTask(title: "Plan trip")
    context.insert(task)

    // 12 questions, but cap is AppConstants.maxDiscoveryQuestions (10).
    let plan = TaskPlan(
        title: "Plan trip",
        description: "",
        subTasks: (1...12).map { SubTaskPlan(title: "Q\($0)", description: "d\($0)", requiresExternalAction: false) }
    )

    task.addDiscoverySubTasks(from: plan, into: context)

    #expect(task.subTasks.count == AppConstants.maxDiscoveryQuestions)
    #expect(task.sortedSubTasks.first?.status == .current)
    #expect(task.sortedSubTasks.dropFirst().allSatisfy { $0.status == .pending })
    #expect(task.sortedSubTasks.allSatisfy { $0.isDiscoveryPhase })
}

@MainActor
@Test func task_addDiscoverySubTasks_under_cap_keeps_all() throws {
    let schema = Schema([TodoTask.self, SubTask.self])
    let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(isStoredInMemoryOnly: true)])
    let context = ModelContext(container)

    let task = TodoTask(title: "Quick task")
    context.insert(task)
    let plan = TaskPlan(title: "Quick task", description: "", subTasks: [
        SubTaskPlan(title: "Only question", description: "", requiresExternalAction: false)
    ])

    task.addDiscoverySubTasks(from: plan, into: context)
    #expect(task.subTasks.count == 1)
    #expect(task.subTasks.first?.title == "Only question")
}

// MARK: - Task.phaseColor

@MainActor
@Test func task_phaseColor_reflects_phase() {
    let task = TodoTask(title: "T")
    #expect(task.phaseColor == Theme.discovery)
    task.transitionToExecution()
    #expect(task.phaseColor == Theme.execution)
}

// MARK: - SubTask.effectiveRequiresExternalAction

@Test func subtask_effective_external_action_true_when_flag_set() {
    let st = SubTask(title: "Call", requiresExternalAction: true)
    #expect(st.effectiveRequiresExternalAction == true)
}

@Test func subtask_effective_external_action_false_without_schema_or_flag() {
    let st = SubTask(title: "Note something")
    #expect(st.effectiveRequiresExternalAction == false)
}

@Test func subtask_effective_external_action_reads_from_cached_schema() throws {
    let st = SubTask(title: "Confirm")
    let schema = ActionSchema(type: .form, title: "Confirm", fields: [], requiresExternalAction: true)
    st.actionSchemaData = try JSONEncoder().encode(schema)
    #expect(st.effectiveRequiresExternalAction == true)
}

@Test func subtask_effective_external_action_false_for_inapp_schema() throws {
    let st = SubTask(title: "Record")
    let schema = ActionSchema(type: .form, title: "Record", fields: [], requiresExternalAction: false)
    st.actionSchemaData = try JSONEncoder().encode(schema)
    #expect(st.effectiveRequiresExternalAction == false)
}

@Test func subtask_effective_external_action_handles_corrupt_schema_data() {
    let st = SubTask(title: "Broken")
    st.actionSchemaData = Data("not json".utf8)
    #expect(st.effectiveRequiresExternalAction == false)
}

// MARK: - TableData.markdown / summary edge cases

@Test func tableData_summary_no_items() {
    let table = TableData(columns: [TableData.Column(id: "item", label: "Item", type: "text")], rows: [], total: 0, hasCurrency: false)
    #expect(table.summary == "No items")
}

@Test func tableData_summary_with_currency_total() {
    let table = TableData(
        columns: [
            TableData.Column(id: "item", label: "Item", type: "text"),
            TableData.Column(id: "price", label: "Price", type: "currency"),
        ],
        rows: [["item": "Apples", "price": "5"], ["item": "Oranges", "price": "10"]],
        total: 15,
        hasCurrency: true
    )
    #expect(table.summary == "Apples - €5; Oranges - €10 (Total: €15)")
}

@Test func tableData_markdown_empty_columns_returns_empty() {
    let table = TableData(columns: [], rows: [], total: 0, hasCurrency: false)
    #expect(table.markdown == "")
}

@Test func tableData_markdown_renders_table_with_currency_cells_and_total() {
    let table = TableData(
        columns: [
            TableData.Column(id: "item", label: "Item", type: "text"),
            TableData.Column(id: "price", label: "Price", type: "currency"),
        ],
        rows: [["item": "Apples", "price": "5"]],
        total: 5,
        hasCurrency: true
    )
    let md = table.markdown
    #expect(md.contains("| Item | Price |"))
    #expect(md.contains("| --- | --- |"))
    #expect(md.contains("| Apples | €5 |"))
    #expect(md.contains("_Total: €5_"))
}

@Test func tableData_markdown_omits_total_when_no_currency() {
    let table = TableData(
        columns: [TableData.Column(id: "item", label: "Item", type: "text")],
        rows: [["item": "Notebook"]],
        total: 0,
        hasCurrency: false
    )
    let md = table.markdown
    #expect(md.contains("| Notebook |"))
    #expect(!md.contains("Total"))
}

// MARK: - ResponseValue accessor negative paths

@Test func responseValue_accessors_return_nil_for_wrong_case() {
    let s = ResponseValue.string("x")
    #expect(s.numberValue == nil)
    #expect(s.boolValue == nil)
    #expect(s.dateValue == nil)
    #expect(s.stringArrayValue == nil)
    #expect(s.rangeValue == nil)
    #expect(s.treeValue == nil)
    #expect(s.tableValue == nil)
    #expect(s.imageValue == nil)

    let n = ResponseValue.number(3)
    #expect(n.numberValue == 3)
    #expect(n.stringValue == nil)

    let b = ResponseValue.boolean(true)
    #expect(b.boolValue == true)

    let date = Date()
    let d = ResponseValue.date(date)
    #expect(d.dateValue == date)

    let arr = ResponseValue.stringArray(["a", "b"])
    #expect(arr.stringArrayValue == ["a", "b"])

    let range = ResponseValue.range(lower: 1, upper: 9)
    #expect(range.rangeValue?.lower == 1)
    #expect(range.rangeValue?.upper == 9)
}

// MARK: - formatResponseValue covering all cases

@Test func formatResponseValue_covers_all_cases() {
    #expect(formatResponseValue(.string("hi")) == "hi")
    #expect(formatResponseValue(.boolean(true)) == "Yes")
    #expect(formatResponseValue(.boolean(false)) == "No")
    #expect(formatResponseValue(.stringArray(["a", "b"])) == "a, b")
    #expect(formatResponseValue(.range(lower: 1, upper: 9)) == "1 - 9")
    #expect(formatResponseValue(.tree([TreeNode(label: "Root", depth: 0), TreeNode(label: "Child", depth: 1)])) == "Root, Child")
    #expect(formatResponseValue(.image(png: Data(), description: "Sketch of room")) == "Sketch of room")

    let table = TableData(columns: [TableData.Column(id: "i", label: "I", type: "text")], rows: [["i": "x"]], total: 0, hasCurrency: false)
    #expect(formatResponseValue(.table(table)) == "x")
}

@Test func formatResponseValue_date_abbreviated_vs_full() {
    let date = Date(timeIntervalSince1970: 1_700_000_000)
    let full = formatResponseValue(.date(date), abbreviatedDate: false)
    let abbreviated = formatResponseValue(.date(date), abbreviatedDate: true)
    #expect(!full.isEmpty)
    #expect(!abbreviated.isEmpty)
    #expect(full != abbreviated) // full includes time component
}

@Test func formatResponseValues_empty_is_no_response() {
    #expect(formatResponseValues(ActionResponse()) == "(no response)")
}

@Test func actionResponseToDict_uses_abbreviated_dates() {
    var response = ActionResponse()
    response["name"] = .string("Alice")
    let dict = actionResponseToDict(response)
    #expect(dict["name"] == "Alice")
}
