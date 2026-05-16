import SwiftUI

/// The trailing control shown in a task card's header.
enum TaskCardAccessory {
    /// Chevron that toggles the card's expansion (default).
    case expandChevron
    /// "Take Action" button that opens the focused single-task view.
    case takeAction

    var allowsExpansion: Bool { self == .expandChevron }
}

struct TaskCard<Content: View>: View {
    let task: TodoTask
    var defaultExpanded: Bool = false
    var accessory: TaskCardAccessory = .expandChevron
    var isSelected: Bool = false
    @ViewBuilder let content: () -> Content
    @State private var isExpanded: Bool = false

    private var phaseColor: Color {
        task.isDiscoveryPhase ? .orange : .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TaskHeaderView(task: task, isExpanded: $isExpanded, accessory: accessory)

            if isExpanded && accessory.allowsExpansion {
                content()
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = defaultExpanded
            }
        }
        .onChange(of: task.isPlanning) { wasPlanning, isPlanning in
            if wasPlanning && !isPlanning {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = true
                }
            }
        }
        .padding(16)
        .background(phaseColor.opacity(isSelected ? 0.1 : 0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(phaseColor.opacity(isSelected ? 0.8 : 0.3), lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

struct TaskHeaderView: View {
    let task: TodoTask
    @Binding var isExpanded: Bool
    var accessory: TaskCardAccessory = .expandChevron

    private var phaseColor: Color {
        task.isDiscoveryPhase ? .orange : .blue
    }

    private var phaseLabel: String {
        if task.status == TaskStatus.completed {
            return "Completed:"
        } else if task.isPlanningDiscovery {
            return "Planning Discovery:"
        } else if task.isPlanningExecution {
            return "Planning Execution:"
        } else if task.isDiscoveryPhase {
            return "Discovering:"
        } else {
            return "Executing:"
        }
    }

    private var isPlanning: Bool {
        task.isPlanningDiscovery || task.isPlanningExecution
    }

    private var isCompleted: Bool {
        task.status == TaskStatus.completed
    }

    var body: some View {
        if accessory.allowsExpansion {
            // Chevron sits inline in the title row; description flows below.
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    iconAndTitle
                    Spacer()
                    headerAccessory
                }
                descriptionText
            }
        } else {
            // Accessory is centered against the whole title + description block.
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        iconAndTitle
                        Spacer()
                    }
                    descriptionText
                }
                headerAccessory
            }
        }
    }

    @ViewBuilder
    private var iconAndTitle: some View {
        if isPlanning {
            ProgressView()
                .controlSize(.small)
        } else {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: Theme.circleSize))
                .foregroundColor(phaseColor)
        }

        Text(phaseLabel)
            .font(.system(size: Theme.fontSize, weight: .medium))
            .foregroundColor(phaseColor)

        Text(task.title)
            .font(.system(size: Theme.fontSize, weight: .semibold))
    }

    @ViewBuilder
    private var descriptionText: some View {
        if !task.taskDescription.isEmpty {
            Text(task.taskDescription)
                .font(.system(size: Theme.fontSize))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var headerAccessory: some View {
        switch accessory {
        case .expandChevron:
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("taskCard.toggleExpand")

        case .takeAction:
            Button {
                NotificationCenter.default.post(name: .focusTask, object: task.id)
            } label: {
                Text("Take Action")
                    .font(.system(size: Theme.fontSize - 2, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(phaseColor.opacity(0.15))
                    .foregroundColor(phaseColor)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("taskCard.takeAction")
        }
    }
}

struct SubTaskRowView: View {
    let subTask: SubTask
    let phaseColor: Color
    @State private var isHovering = false

    /// Only the current (next actionable) sub-task is clickable.
    private var isClickable: Bool { subTask.isCurrent }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: subTask.isCompleted ? "checkmark.circle.fill" :
                    (subTask.status == SubTaskStatus.skipped ? "arrow.right.circle" : "circle"))
                .foregroundColor(subTask.isCompleted ? phaseColor :
                    (subTask.status == SubTaskStatus.skipped ? .orange : phaseColor.opacity(0.4)))
                .font(.system(size: Theme.circleSize))

            VStack(alignment: .leading, spacing: 4) {
                Text(subTask.title)
                    .font(.system(size: Theme.fontSize))
                    .foregroundColor(subTask.isCompleted ? .secondary : .primary)
                    .strikethrough(subTask.isCompleted)
            }

            if subTask.isCurrent {
                Text("Current")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(phaseColor.opacity(0.15))
                    .foregroundColor(phaseColor)
                    .cornerRadius(4)
            }

            if subTask.effectiveRequiresExternalAction {
                Text("Outside Work")
                    .font(.system(size: 10, weight: .medium))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .foregroundColor(subTask.isCompleted ? .secondary : .white)
                    .background(subTask.isCompleted ? Color.gray.opacity(0.3) : Theme.externalActionColor)
                    .cornerRadius(4)
            }

            Spacer()
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isClickable && isHovering ? Color.black.opacity(0.25) : Color.clear)
        )
        .opacity(subTask.isCompleted || subTask.isCurrent ? 1.0 : 0.5)
        .contentShape(Rectangle())
        .accessibilityIdentifier(isClickable ? "subTaskRow.current" : "")
        .accessibilityAddTraits(isClickable ? .isButton : [])
        .onTapGesture {
            if let taskId = subTask.task?.id, subTask.isCurrent {
                NotificationCenter.default.post(name: .focusTask, object: taskId)
            }
        }
        .onHover { hovering in
            isHovering = hovering
            guard isClickable else { return }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct SubTaskListContent: View {
    let task: TodoTask
    @State private var discoveryExpanded = false
    @State private var executionExpanded = false

    private var discoveryComplete: Bool {
        !task.discoverySubTasks.isEmpty && task.discoverySubTasks.allSatisfy { $0.isCompleted }
    }

    private var executionComplete: Bool {
        !task.executionSubTasks.isEmpty && task.executionSubTasks.allSatisfy { $0.isCompleted }
    }

    var body: some View {
        if !task.subTasks.isEmpty {
            Divider()

            VStack(alignment: .leading, spacing: 12) {
                // Discovery section
                if !task.discoverySubTasks.isEmpty {
                    CollapsibleSection(
                        title: "Discovery",
                        icon: discoveryComplete ? "checkmark.circle.fill" : "circle",
                        color: .orange,
                        isExpanded: $discoveryExpanded
                    ) {
                        ForEach(task.discoverySubTasks) { subTask in
                            SubTaskRowView(subTask: subTask, phaseColor: .orange)
                        }
                    }
                }

                // Execution section
                if task.isExecutionPhase && !task.executionSubTasks.isEmpty {
                    CollapsibleSection(
                        title: "Execution",
                        icon: executionComplete ? "checkmark.circle.fill" : "circle",
                        color: .blue,
                        isExpanded: $executionExpanded
                    ) {
                        ForEach(task.executionSubTasks) { subTask in
                            SubTaskRowView(subTask: subTask, phaseColor: .blue)
                        }
                    }
                    .padding(.top, 8)
                } else if task.isDiscoveryPhase && !task.isPlanningDiscovery && !task.discoverySubTasks.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.dotted")
                            .font(.system(size: Theme.circleSize))
                            .foregroundColor(.blue.opacity(0.4))
                        Text("Execution")
                            .font(.system(size: Theme.fontSize, weight: .medium))
                            .foregroundColor(.blue.opacity(0.4))
                        Text("(after discovery)")
                            .font(.system(size: Theme.fontSize - 2))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .padding(.top, 8)
                }
            }
            .onAppear {
                // Start collapsed when complete, expanded when in-progress
                if !task.discoverySubTasks.allSatisfy({ $0.isCompleted }) {
                    discoveryExpanded = true
                }
                if !task.executionSubTasks.allSatisfy({ $0.isCompleted }) {
                    executionExpanded = true
                }
            }
        }
    }
}

/// A collapsible section with a chevron toggle for sub-task lists.
struct CollapsibleSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: Theme.circleSize))
                        .foregroundColor(color)

                    Text(title)
                        .font(.system(size: Theme.fontSize, weight: .medium))
                        .foregroundColor(color)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                content()
                    .padding(.top, 4)
            }
        }
    }
}
