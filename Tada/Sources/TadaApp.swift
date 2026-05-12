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
                .environment(appServices)
        }
        .modelContainer(for: [TodoTask.self, SubTask.self])
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

        Settings {
            SettingsView()
        }
    }
}

extension Notification.Name {
    static let newTask = Notification.Name("newTask")
    static let navigateToInformationRequired = Notification.Name("navigateToInformationRequired")
    static let navigateToActionRequired = Notification.Name("navigateToActionRequired")
    static let navigateToTaskInActionRequired = Notification.Name("navigateToTaskInActionRequired")
    static let showExecutionPlanSheet = Notification.Name("showExecutionPlanSheet")
}

enum Theme {
    static let fontSize: CGFloat = 16
    static let badgeFontSize: CGFloat = 10
    static let circleSize: CGFloat = 18
    static let externalActionColor = Color(red: 0.25, green: 0.4, blue: 0.65)
}
