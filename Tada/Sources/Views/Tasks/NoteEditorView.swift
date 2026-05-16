import SwiftUI

struct NoteEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var isPresented: Bool
    let onSave: (String, String) -> Void
    let existingNotes: [(slug: String, title: String)]

    @State private var title: String = ""
    @State private var noteBody: String = ""
    @State private var showingAutocomplete: Bool = false
    @State private var autocompleteQuery: String = ""
    @State private var autocompletePosition: CGPoint = .zero
    @State private var cursorPosition: Int = 0
    @FocusState private var isBodyFocused: Bool

    private var filteredNotes: [(slug: String, title: String)] {
        if autocompleteQuery.isEmpty {
            return existingNotes
        }
        return existingNotes.filter { note in
            note.title.localizedCaseInsensitiveContains(autocompleteQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Note")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape, modifiers: [])
                Button("Save") {
                    saveNote()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(title.isEmpty)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold))
                    .padding(.horizontal, 4)

                Divider()

                ZStack(alignment: .topLeading) {
                    WikilinkTextEditor(
                        text: $noteBody,
                        showingAutocomplete: $showingAutocomplete,
                        autocompleteQuery: $autocompleteQuery,
                        onInsertLink: insertLink
                    )
                    .focused($isBodyFocused)
                    .font(.system(size: 14))

                    if showingAutocomplete && !filteredNotes.isEmpty {
                        autocompleteOverlay
                    }
                }
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
        .onAppear {
            isBodyFocused = true
        }
    }

    private var autocompleteOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(filteredNotes.prefix(8).enumerated()), id: \.element.slug) { index, note in
                Button {
                    insertLink(note.title, note.slug)
                } label: {
                    HStack {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text(note.title)
                            .font(.system(size: 13))
                            .foregroundColor(.primary)
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(Color(.controlBackgroundColor))

                if index < min(filteredNotes.count, 8) - 1 {
                    Divider()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.windowBackgroundColor))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(.separatorColor), lineWidth: 1)
        )
        .frame(maxWidth: 300)
        .padding(.top, 60)
        .padding(.leading, 4)
    }

    private func insertLink(_ title: String, _ slug: String) {
        let linkText = "[[../_notes/\(slug).md|\(title)]]"

        if let range = noteBody.range(of: "[[" + autocompleteQuery, options: .backwards) {
            noteBody.replaceSubrange(range, with: linkText)
        } else if let range = noteBody.range(of: "[[", options: .backwards) {
            noteBody.replaceSubrange(range, with: linkText)
        }

        showingAutocomplete = false
        autocompleteQuery = ""
    }

    private func saveNote() {
        guard !title.isEmpty else { return }
        onSave(title, noteBody)
        isPresented = false
    }
}

struct WikilinkTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var showingAutocomplete: Bool
    @Binding var autocompleteQuery: String
    let onInsertLink: (String, String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = NSColor.textColor
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: WikilinkTextEditor
        private var isProcessingAutocomplete = false

        init(_ parent: WikilinkTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string

            checkForWikilinkTrigger(in: textView)
        }

        private func checkForWikilinkTrigger(in textView: NSTextView) {
            let text = textView.string
            let cursorPosition = textView.selectedRange().location

            guard cursorPosition > 0 else {
                parent.showingAutocomplete = false
                return
            }

            let textBeforeCursor = String(text.prefix(cursorPosition))

            if let lastOpenBracket = textBeforeCursor.range(of: "[[", options: .backwards) {
                let afterBracket = textBeforeCursor[lastOpenBracket.upperBound...]

                if !afterBracket.contains("]]") && !afterBracket.contains("\n") {
                    parent.autocompleteQuery = String(afterBracket)
                    parent.showingAutocomplete = true
                    return
                }
            }

            parent.showingAutocomplete = false
            parent.autocompleteQuery = ""
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                if parent.showingAutocomplete {
                    parent.showingAutocomplete = false
                    parent.autocompleteQuery = ""
                    return true
                }
            }
            return false
        }
    }
}

#Preview {
    NoteEditorView(
        isPresented: .constant(true),
        onSave: { _, _ in },
        existingNotes: [
            ("test-note", "Test Note"),
            ("another-note", "Another Note"),
            ("project-ideas", "Project Ideas")
        ]
    )
}
