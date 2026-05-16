import SwiftUI
import SwiftData

/// The coach chat panel that appears on the right side of the app.
struct CoachChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appServices) private var appServices
    @Bindable var viewModel: CoachViewModel
    @FocusState private var isInputFocused: Bool
    @Query private var allTasks: [TodoTask]

    private var selectedTask: TodoTask? {
        guard let selectedId = viewModel.context.selectedTaskId else { return nil }
        return allTasks.first { $0.id == selectedId }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            contextIndicator
            messageList
            inputArea
        }
        .frame(minWidth: 300, idealWidth: 350, maxWidth: 400)
        .task {
            viewModel.modelContext = modelContext
            viewModel.knowledgeBase = appServices?.knowledgeBase
            viewModel.plannerAI = appServices?.plannerAI
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundColor(.purple)

            Text("Coach")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Button {
                viewModel.clearChat()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .help("Clear chat")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var contextIndicator: some View {
        HStack(spacing: 6) {
            Image(systemName: contextIcon)
                .font(.system(size: 10))
            Text(contextLabel)
                .font(.system(size: 11))
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.controlBackgroundColor).opacity(0.5))
    }

    private var contextIcon: String {
        if selectedTask != nil {
            return "scope"
        }
        switch viewModel.context.currentView {
        case .allTasks: return "list.bullet"
        case .actionItems: return "bolt.fill"
        case .completed: return "checkmark.circle"
        case .knowledgeBase: return "book"
        case .console: return "terminal"
        case .settings: return "gear"
        case .focusedTask: return "scope"
        }
    }

    private var contextLabel: String {
        if let task = selectedTask {
            return "Task: \(task.title)"
        }
        switch viewModel.context.currentView {
        case .allTasks: return "Viewing All Tasks"
        case .actionItems: return "Viewing Action Items"
        case .completed: return "Viewing Completed Tasks"
        case .knowledgeBase(let url):
            if let url {
                return "Reading: \(url.deletingPathExtension().lastPathComponent)"
            }
            return "Viewing Knowledge Base"
        case .console: return "Viewing Console"
        case .settings: return "Viewing Settings"
        case .focusedTask: return "Focused on Task"
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }

                    if viewModel.isLoading {
                        HStack {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .id("loading")
                    }
                }
                .padding(16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation {
                    proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.isLoading) { _, isLoading in
                if isLoading {
                    withAnimation {
                        proxy.scrollTo("loading", anchor: .bottom)
                    }
                }
            }
        }
    }

    private var inputArea: some View {
        VStack(spacing: 8) {
            if let error = viewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
            }

            HStack(spacing: 8) {
                TextField("Ask anything...", text: $viewModel.inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .onSubmit {
                        Task {
                            await viewModel.sendMessage()
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(8)

                Button {
                    Task {
                        await viewModel.sendMessage()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(viewModel.inputText.isEmpty ? .secondary : .blue)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.inputText.isEmpty || viewModel.isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

private struct MessageBubble: View {
    let message: CoachMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                Text(markdownContent)
                    .font(.system(size: 13))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubbleBackground)
                    .cornerRadius(12)

                if let toolResults = message.toolResults, !toolResults.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(toolResults) { result in
                            ToolResultView(result: result)
                        }
                    }
                }
            }

            if message.role != .user {
                Spacer()
            }
        }
    }

    private var markdownContent: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: message.content, options: options)) ?? AttributedString(message.content)
    }

    private var bubbleBackground: Color {
        switch message.role {
        case .user:
            return .blue
        case .coach:
            return Color(.controlBackgroundColor)
        case .system:
            return Color.orange.opacity(0.2)
        }
    }
}

private struct ToolResultView: View {
    let result: CoachMessage.ToolResult

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 10))
                .foregroundColor(result.success ? .green : .red)

            Text(result.message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(6)
    }
}

#Preview {
    CoachChatView(viewModel: CoachViewModel(context: CoachContext()))
        .frame(height: 500)
}
