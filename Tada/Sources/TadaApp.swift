import SwiftUI
import SwiftData

@main
struct TadaApp: App {
    private let appServices = AppServices(
        knowledgeBase: nil,
        executiveAI: nil,
        plannerAI: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.appServices, appServices)
        }
        .modelContainer(for: [TodoTask.self, SubTask.self], inMemory: UITestSupport.isActive)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Task") {
                    NotificationCenter.default.post(name: .newTask, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    SettingsWindowManager.shared.openSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let newTask = Notification.Name("newTask")
    /// Posted with the task's `UUID` as `object` to open the focused single-task view.
    static let focusTask = Notification.Name("focusTask")
    static let navigateToTaskInActionItems = Notification.Name("navigateToTaskInActionItems")
    /// Posted to reveal the coach chat sidebar (e.g. from an action card's Help button).
    static let revealCoach = Notification.Name("revealCoach")
}

enum Theme {
    static let fontSize: CGFloat = 16
    static let badgeFontSize: CGFloat = 10
    static let circleSize: CGFloat = 18
    static let externalActionColor = Color(red: 0.25, green: 0.4, blue: 0.65)
    /// Accent color for the discovery phase.
    static let discovery = Color.orange
    /// Accent color for the execution phase.
    static let execution = Color.blue
}
