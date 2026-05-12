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
    static let navigateToActionItems = Notification.Name("navigateToActionItems")
    static let navigateToTaskInActionItems = Notification.Name("navigateToTaskInActionItems")
}

enum Theme {
    static let fontSize: CGFloat = 16
    static let badgeFontSize: CGFloat = 10
    static let circleSize: CGFloat = 18
    static let externalActionColor = Color(red: 0.25, green: 0.4, blue: 0.65)
}
