import SwiftUI

/// A focused, single-task view: shows only the given task's action card,
/// vertically centered in the main content area. Reached by clicking the
/// current (actionable) sub-task in the All Tasks list.
struct FocusedTaskView: View {
    let task: TodoTask
    let onBack: () -> Void
    @Environment(\.appServices) private var appServices

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) {
                    Label("All Tasks", systemImage: "chevron.left")
                        .font(.system(size: Theme.fontSize))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .accessibilityIdentifier("focusedTask.back")

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            GeometryReader { geo in
                ScrollView {
                    ActionCard(
                        task: task,
                        defaultExpanded: true,
                        knowledgeBase: appServices?.knowledgeBase,
                        executiveAI: appServices?.executiveAI,
                        plannerAI: appServices?.plannerAI
                    )
                    .frame(maxWidth: 820)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(24)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                }
            }
        }
    }
}
