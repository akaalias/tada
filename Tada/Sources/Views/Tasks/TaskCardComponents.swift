import SwiftUI

struct TaskCard<Content: View>: View {
    let task: TodoTask
    var defaultExpanded: Bool = false
    @ViewBuilder let content: () -> Content
    @State private var isExpanded: Bool = false

    private var phaseColor: Color {
        task.isDiscoveryPhase ? .orange : .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TaskHeaderView(task: task, isExpanded: $isExpanded)

            if isExpanded {
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
        .background(phaseColor.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(phaseColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
    }
}

struct TaskHeaderView: View {
    let task: TodoTask
    @Binding var isExpanded: Bool

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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
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

                Spacer()

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
            }

            if !task.taskDescription.isEmpty || !task.subTasks.isEmpty {
                HStack(alignment: .top) {
                    if !task.taskDescription.isEmpty {
                        Text(task.taskDescription)
                            .font(.system(size: Theme.fontSize))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if !task.subTasks.isEmpty {
                        ProgressIndicator(
                            progress: task.progress,
                            isDiscovery: task.isDiscoveryPhase
                        )
                    }
                }
            }
        }
    }
}

struct SubTaskRowView: View {
    let subTask: SubTask
    let phaseColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: subTask.isCompleted ? "checkmark.circle.fill" :
                    (subTask.status == SubTaskStatus.skipped ? "arrow.right.circle" : "circle"))
                .foregroundColor(subTask.isCompleted ? phaseColor :
                    (subTask.status == SubTaskStatus.skipped ? .orange : phaseColor.opacity(0.4)))
                .font(.system(size: Theme.circleSize))
                .padding(.top, 2)

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
        .opacity(subTask.isCompleted || subTask.isCurrent ? 1.0 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture {
            if subTask.isCurrent {
                if subTask.isDiscoveryPhase {
                    NotificationCenter.default.post(name: .navigateToInformationRequired, object: nil)
                } else {
                    NotificationCenter.default.post(name: .navigateToActionRequired, object: nil)
                }
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

struct ProgressIndicator: View {
    let progress: Double
    var isDiscovery: Bool = false

    private var phaseColor: Color {
        isDiscovery ? .orange : .blue
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(phaseColor.opacity(0.2), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(phaseColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(phaseColor)
        }
        .frame(width: 40, height: 40)
    }
}
